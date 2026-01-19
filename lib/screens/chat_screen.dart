import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/mcp_server.dart';
import '../providers/conversation_provider.dart';
import '../services/openrouter_service.dart';
import '../services/default_model_service.dart';
import '../services/database_service.dart';
import '../services/mcp_client_service.dart';
import '../services/chat_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/sampling_request_dialog.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;

  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  Map<String, dynamic>? _modelDetails;
  bool _hasGeneratedTitle = false;
  List<McpServer> _mcpServers = [];
  final Map<String, McpClientService> _mcpClients = {};
  final Map<String, List<McpTool>> _mcpTools = {};
  bool _showThinking = true;
  String _streamingContent = '';
  String _streamingReasoning = '';
  ChatService? _chatService;
  String? _currentToolName;
  bool _isToolExecuting = false; // true = calling, false = called

  @override
  void initState() {
    super.initState();
    _loadModelDetails();
    _loadMcpServers();
  }

  Future<void> _loadMcpServers() async {
    try {
      final servers = await DatabaseService.instance.getConversationMcpServers(
        widget.conversation.id,
      );
      setState(() {
        _mcpServers = servers;
      });

      // Initialize MCP clients for each server
      for (final server in servers) {
        try {
          final client = McpClientService(
            serverUrl: server.url,
            headers: server.headers,
          );
          await client.initialize();
          final tools = await client.listTools();

          _mcpClients[server.id] = client;
          _mcpTools[server.id] = tools;
        } catch (e) {
          debugPrint('Failed to initialize MCP server ${server.name}: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to load MCP servers: $e');
    }
  }

  Future<void> _loadModelDetails() async {
    try {
      final openRouterService = context.read<OpenRouterService>();
      final models = await openRouterService.getModels();
      final model = models.firstWhere(
        (m) => m['id'] == widget.conversation.model,
        orElse: () => {},
      );
      if (mounted) {
        setState(() {
          _modelDetails = model;
        });
      }
    } on OpenRouterAuthException {
      _handleAuthError();
    } catch (e) {
      // Silently fail - pricing is not critical
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _chatService?.dispose();
    // Close all MCP clients
    for (final client in _mcpClients.values) {
      client.close();
    }
    super.dispose();
  }

  /// Handle OpenRouter authentication errors by navigating to auth screen
  void _handleAuthError() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Authentication expired. Please log in again.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );

    // Navigate back to conversation list, which will redirect to auth
    Navigator.of(context).pop();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _sendMessage() async {
    try {
      final text = _messageController.text.trim();
      if (text.isEmpty) return;

      final provider = context.read<ConversationProvider>();
      final openRouterService = context.read<OpenRouterService>();

      // Add user message
      final userMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: MessageRole.user,
        content: text,
        timestamp: DateTime.now(),
      );

      await provider.addMessage(userMessage);
      _messageController.text = '';
      _scrollToBottom();

      // Get AI response
      setState(() {
        _isLoading = true;
        _streamingContent = '';
      });

      try {
        // Initialize ChatService if not already done
        if (_chatService == null) {
          _chatService = ChatService(
            openRouterService: openRouterService,
            mcpClients: _mcpClients,
            mcpTools: _mcpTools,
          );

          // Listen to chat events
          _chatService!.events.listen((event) {
            _handleChatEvent(event, provider);
          });
        }

        // Get all messages for context
        final messages = provider.getMessages(widget.conversation.id);

        // Run the agentic loop in the chat service
        await _chatService!.runAgenticLoop(
          conversationId: widget.conversation.id,
          model: widget.conversation.model,
          messages: List.from(messages), // Pass a copy
        );

        // Auto-generate title after first response if enabled
        if (!_hasGeneratedTitle && mounted) {
          _hasGeneratedTitle = true;
          final autoTitleEnabled =
              await DefaultModelService.getAutoTitleEnabled();
          if (autoTitleEnabled) {
            _generateConversationTitle(provider, openRouterService);
          }
        }
      } on OpenRouterAuthException {
        _handleAuthError();
      } catch (e, stackTrace) {
        print('Error in _sendMessage: $e');
        print('Stack trace: $stackTrace');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _streamingContent = '';
            _streamingReasoning = '';
            _currentToolName = null;
            _isToolExecuting = false;
          });
        }
      }
    } catch (e, stackTrace) {
      print('Fatal error in _sendMessage: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fatal error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  /// Handle events from the ChatService
  void _handleChatEvent(ChatEvent event, ConversationProvider provider) {
    if (!mounted) return;

    if (event is ContentChunk) {
      setState(() {
        _streamingContent = event.content;
        _currentToolName = null; // Clear tool name when content is streaming
        _isToolExecuting = false;
      });
      _scrollToBottom();
    } else if (event is ReasoningChunk) {
      setState(() {
        _streamingReasoning = event.content;
      });
      _scrollToBottom();
    } else if (event is MessageCreated) {
      // Clear streaming state when message is persisted
      setState(() {
        _streamingContent = '';
        _streamingReasoning = '';
      });
      // Add message to provider
      provider.addMessage(event.message);
      _scrollToBottom();
    } else if (event is ToolExecutionStarted) {
      setState(() {
        _currentToolName = event.toolName;
        _isToolExecuting = true; // Now calling the tool
      });
    } else if (event is ToolExecutionCompleted) {
      setState(() {
        // Keep the tool name but mark as completed
        _isToolExecuting = false;
      });
    } else if (event is ConversationComplete) {
      setState(() {
        _streamingContent = '';
        _streamingReasoning = '';
        _currentToolName = null;
        _isToolExecuting = false;
        _isLoading = false;
      });
    } else if (event is MaxIterationsReached) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum tool call iterations reached'),
          backgroundColor: Colors.orange,
        ),
      );
    } else if (event is SamplingRequestReceived) {
      _showSamplingRequestDialog(event);
    } else if (event is ErrorOccurred) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${event.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Show the sampling request dialog for user approval
  void _showSamplingRequestDialog(SamplingRequestReceived event) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SamplingRequestDialog(
        request: event.request,
        onApprove: (approvedRequest) async {
          try {
            // Process the approved sampling request
            final response = await _chatService!.processSamplingRequest(
              request: approvedRequest,
              preferredModel: widget.conversation.model,
            );

            // Return the response to the MCP server
            event.onApprove(approvedRequest, response);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Sampling error: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            event.onReject();
          }
        },
        onReject: () async {
          event.onReject();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationProvider>(
      builder: (context, provider, child) {
        final conversation = provider.conversations.firstWhere(
          (c) => c.id == widget.conversation.id,
          orElse: () => widget.conversation,
        );

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conversation.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        conversation.model,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_modelDetails != null &&
                        _modelDetails!['pricing'] != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        _getPricingText(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (_mcpServers.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.dns,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_mcpServers.length} MCP',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: [
              IconButton(
                icon: Icon(
                  _showThinking ? Icons.visibility : Icons.visibility_off,
                ),
                tooltip: _showThinking ? 'Hide thinking' : 'Show thinking',
                onPressed: () {
                  setState(() {
                    _showThinking = !_showThinking;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _showRenameDialog(),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Consumer<ConversationProvider>(
                  builder: (context, provider, child) {
                    final messages = provider.getMessages(
                      widget.conversation.id,
                    );

                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.message_outlined,
                              size: 64,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Start a conversation',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Type a message below to begin',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      );
                    }

                    // Filter messages based on thinking mode and role
                    final displayMessages = messages.where((msg) {
                      // Always show user messages
                      if (msg.role == MessageRole.user) return true;

                      // Hide tool role messages when thinking is disabled
                      // Show them when thinking is enabled for transparency
                      if (msg.role == MessageRole.tool) {
                        return _showThinking;
                      }

                      // Hide empty assistant messages without tool calls or reasoning
                      if (msg.role == MessageRole.assistant &&
                          msg.content.isEmpty &&
                          msg.reasoning == null &&
                          msg.toolCallData == null) {
                        return false;
                      }

                      // Hide assistant messages with tool calls when thinking is disabled
                      if (msg.role == MessageRole.assistant &&
                          msg.toolCallData != null &&
                          !_showThinking) {
                        return false;
                      }

                      return true;
                    }).toList();

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount:
                          displayMessages.length +
                          ((_streamingContent.isNotEmpty ||
                                  _streamingReasoning.isNotEmpty)
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        // Show streaming content as last item
                        if ((_streamingContent.isNotEmpty ||
                                _streamingReasoning.isNotEmpty) &&
                            index == displayMessages.length) {
                          final streamingMessage = Message(
                            id: 'streaming',
                            conversationId: widget.conversation.id,
                            role: MessageRole.assistant,
                            content: _streamingContent,
                            timestamp: DateTime.now(),
                            reasoning: _streamingReasoning.isNotEmpty
                                ? _streamingReasoning
                                : null,
                          );
                          return MessageBubble(
                            message: streamingMessage,
                            isStreaming: true,
                            showThinking: _showThinking,
                          );
                        }

                        final message = displayMessages[index];

                        // Format tool result messages
                        if (message.role == MessageRole.tool && _showThinking) {
                          final formattedMessage = message.copyWith(
                            content:
                                '✅ **Result from ${message.toolName}:**\n\n${message.content}',
                          );
                          return MessageBubble(
                            message: formattedMessage,
                            showThinking: _showThinking,
                          );
                        }

                        // Format assistant messages with tool calls
                        if (message.role == MessageRole.assistant &&
                            message.toolCallData != null &&
                            _showThinking) {
                          // Build tool call display content
                          String toolCallContent = '';

                          try {
                            final toolCalls =
                                jsonDecode(message.toolCallData!) as List;
                            for (final toolCall in toolCalls) {
                              final toolName = toolCall['function']['name'];
                              final toolArgsStr =
                                  toolCall['function']['arguments'];

                              if (toolCallContent.isNotEmpty) {
                                toolCallContent += '\n\n';
                              }

                              toolCallContent +=
                                  '🔧 **Calling tool:** $toolName';

                              // Add formatted arguments
                              try {
                                final Map<String, dynamic> toolArgs;
                                if (toolArgsStr is String) {
                                  toolArgs = Map<String, dynamic>.from(
                                    const JsonCodec().decode(toolArgsStr),
                                  );
                                } else {
                                  toolArgs = Map<String, dynamic>.from(
                                    toolArgsStr,
                                  );
                                }

                                if (toolArgs.isNotEmpty) {
                                  final prettyArgs =
                                      const JsonEncoder.withIndent(
                                        '  ',
                                      ).convert(toolArgs);
                                  toolCallContent +=
                                      '\n\nArguments:\n```json\n$prettyArgs\n```';
                                }
                              } catch (e) {
                                toolCallContent +=
                                    '\n\nArguments: (failed to parse)';
                              }
                            }
                          } catch (e) {
                            // Failed to parse tool calls
                          }

                          // Move original content to reasoning field (thinking bubble)
                          // and show tool calls as the main content
                          String displayReasoning = (message.reasoning ?? '')
                              .trim();
                          final trimmedContent = message.content.trim();

                          if (trimmedContent.isNotEmpty) {
                            if (displayReasoning.isNotEmpty) {
                              displayReasoning += '\n\n';
                            }
                            displayReasoning += trimmedContent;
                          }

                          final formattedMessage = Message(
                            id: message.id,
                            conversationId: message.conversationId,
                            role: message.role,
                            content: toolCallContent,
                            timestamp: message.timestamp,
                            reasoning: displayReasoning.isNotEmpty
                                ? displayReasoning
                                : null,
                            toolCallData: message.toolCallData,
                            toolCallId: message.toolCallId,
                            toolName: message.toolName,
                          );
                          return MessageBubble(
                            message: formattedMessage,
                            showThinking: _showThinking,
                          );
                        } else if (message.role == MessageRole.assistant &&
                            message.toolCallData != null &&
                            !_showThinking) {
                          // Hide thinking messages when thinking is disabled
                          return const SizedBox.shrink();
                        }

                        return MessageBubble(
                          message: message,
                          showThinking: _showThinking,
                        );
                      },
                    );
                  },
                ),
              ),
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _currentToolName != null
                            ? (_isToolExecuting
                                  ? 'Calling tool $_currentToolName...'
                                  : 'Called tool $_currentToolName')
                            : 'Thinking...',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              _buildMessageInput(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -1),
            blurRadius: 4,
            color: Colors.black.withValues(alpha: 0.1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8.0),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (val) {
                  _sendMessage();
                  _focusNode.requestFocus();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _isLoading ? null : _sendMessage,
              icon: const Icon(Icons.send),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                disabledBackgroundColor: Colors.grey[300],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateConversationTitle(
    ConversationProvider provider,
    OpenRouterService openRouterService,
  ) async {
    // Only generate if conversation still has default title
    final currentTitle = widget.conversation.title;
    if (!currentTitle.startsWith('New Chat')) return;

    try {
      final messages = provider.getMessages(widget.conversation.id);
      if (messages.isEmpty) return;

      // Create a prompt for title generation
      final apiMessages = [
        {
          'role': 'user',
          'content':
              'Based on this conversation, generate a short, descriptive title (less than 10 words, no quotes): ${messages.first.content}',
        },
      ];

      final response = await openRouterService.chatCompletion(
        model: widget.conversation.model,
        messages: apiMessages,
      );

      final title = (response['choices'][0]['message']['content'] as String)
          .trim()
          .replaceAll('"', '')
          .replaceAll("'", '');

      if (title.isNotEmpty && mounted) {
        await provider.updateConversationTitle(widget.conversation.id, title);
      }
    } catch (e) {
      // Silently fail - title generation is not critical
    }
  }

  void _showRenameDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => _RenameDialog(
        initialTitle: widget.conversation.title,
        onSave: (newTitle) async {
          await context.read<ConversationProvider>().updateConversationTitle(
            widget.conversation.id,
            newTitle,
          );
        },
      ),
    );
  }

  String _getPricingText() {
    if (_modelDetails == null || _modelDetails!['pricing'] == null) {
      return '';
    }

    final pricing = _modelDetails!['pricing'] as Map<String, dynamic>;
    final completionPrice = pricing['completion'];

    if (completionPrice == null) return '';

    // Convert string price to double and multiply by 1M
    final pricePerToken = double.tryParse(completionPrice.toString()) ?? 0.0;
    final pricePerMillion = pricePerToken * 1000000;

    return '(\$${pricePerMillion.toStringAsFixed(2)}/M out)';
  }
}

class _RenameDialog extends StatefulWidget {
  final String initialTitle;
  final Future<void> Function(String) onSave;

  const _RenameDialog({required this.initialTitle, required this.onSave});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename Conversation'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Conversation Title',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            final newTitle = _controller.text.trim();
            if (newTitle.isNotEmpty) {
              await widget.onSave(newTitle);
            }
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
