import 'dart:convert';
import 'dart:math' as math;
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
import '../widgets/message_bubble.dart';

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
  String? _streamingMessageId;
  String _streamingContent = '';
  String _streamingReasoning = '';

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
      print('=== _sendMessage called ===');
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
      setState(() => _isLoading = true);

      try {
      // Get all messages for context
      final messages = provider.getMessages(widget.conversation.id);

        // Format messages for OpenRouter API (exclude display-only messages)
      final apiMessages = messages
            .where((msg) => !msg.isDisplayOnly) // Exclude tool display messages
            .map<Map<String, dynamic>>((msg) => msg.toApiMessage())
          .toList();

        print(
          'ChatScreen: Built apiMessages with ${apiMessages.length} messages',
        );
        print('ChatScreen: Full apiMessages structure:');
        for (int i = 0; i < apiMessages.length; i++) {
          print('  [$i]: ${jsonEncode(apiMessages[i])}');
        }

        // Aggregate all tools from MCP servers
        final allTools = <Map<String, dynamic>>[];
        for (final tools in _mcpTools.values) {
          allTools.addAll(tools.map((t) => t.toJson()));
        }

        // Use non-streaming when tools available to detect tool calls,
        // but use streaming for final responses
        if (allTools.isNotEmpty) {
          await _handleNonStreamingResponse(
            openRouterService,
            apiMessages,
            allTools,
            provider,
          );
        } else {
          // No tools, use streaming
          await _handleStreamingResponse(
            openRouterService,
            apiMessages,
            allTools,
            provider,
          );
        }

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
        // Show error message
        print('=== INNER CATCH: Error in _sendMessage ===');
        print('Error: $e');
        print('Error type: ${e.runtimeType}');
        print('Stack trace:');
        print(stackTrace);
        print('========================================');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        setState(() => _isLoading = false);
      }
    } catch (e, stackTrace) {
      print('=== OUTER CATCH: Fatal error in _sendMessage ===');
      print('Error: $e');
      print('Error type: ${e.runtimeType}');
      print('Stack trace:');
      print(stackTrace);
      print('==============================================');
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

  Future<void> _handleStreamingResponse(
    OpenRouterService openRouterService,
    List<Map<String, dynamic>> apiMessages,
    List<Map<String, dynamic>> allTools,
    ConversationProvider provider,
  ) async {
    // Create a placeholder message for streaming
    final messageId = const Uuid().v4();
    final assistantMessage = Message(
      id: messageId,
      conversationId: widget.conversation.id,
      role: MessageRole.assistant,
      content: '', // Start empty, will be updated
      timestamp: DateTime.now(),
    );
    await provider.addMessage(assistantMessage);
    _scrollToBottom();

    setState(() {
      _streamingMessageId = messageId;
      _streamingContent = '';
    });

    try {
      print('ChatScreen: Starting stream for message $messageId');
      int tokenCount = 0;
      await for (final chunk in openRouterService.chatCompletionStream(
        model: widget.conversation.model,
        messages: apiMessages,
        tools: allTools.isNotEmpty ? allTools : null,
      )) {
        if (!mounted) break;

        tokenCount++;
        print('ChatScreen: Received token #$tokenCount: "$chunk"');

        setState(() {
          // Separate reasoning from content based on prefix
          if (chunk.startsWith('REASONING:')) {
            // Remove the prefix and add to reasoning
            _streamingReasoning += chunk.substring('REASONING:'.length);
            print(
              'ChatScreen: Added to reasoning, total length=${_streamingReasoning.length}',
            );
          } else {
            // Regular content
            _streamingContent += chunk;
            print(
              'ChatScreen: Added to content, total length=${_streamingContent.length}',
            );
          }
        });

        _scrollToBottom();
      }

      print('ChatScreen: Stream completed with $tokenCount tokens');

      // Only update database once at the end
      if (mounted) {
        if (_streamingContent.isNotEmpty) {
          await provider.updateMessage(
            messageId,
            _streamingContent, // Only save the actual content, not reasoning
          );
        } else {
          // No content received, delete the placeholder message
          await provider.deleteMessage(messageId);
        }
      }
    } catch (e, stackTrace) {
      print('ChatScreen: Error in streaming response:');
      print('Error: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error during streaming: $e')));
      }
      rethrow;
    } finally {
      setState(() {
        _streamingMessageId = null;
        _streamingContent = '';
        _streamingReasoning = ''; // Clear reasoning too
      });
    }
  }

  Future<void> _handleNonStreamingResponse(
    OpenRouterService openRouterService,
    List<Map<String, dynamic>> apiMessages,
    List<Map<String, dynamic>> allTools,
    ConversationProvider provider,
  ) async {
    // Make non-streaming API request to handle tool calls
    final response = await openRouterService.chatCompletion(
      model: widget.conversation.model,
      messages: apiMessages,
      tools: allTools.isNotEmpty ? allTools : null,
    );

    // Process response
    final choices = response['choices'] as List;
    if (choices.isEmpty) {
      throw Exception('No response from API');
    }

    final choice = choices[0];
    final message = choice['message'];
    final toolCalls = message['tool_calls'] as List?;

    if (toolCalls != null && toolCalls.isNotEmpty) {
      // Handle tool calls
      await _handleToolCalls(
        toolCalls,
        provider,
        openRouterService,
        apiMessages,
        allTools,
      );
    } else {
      // No tool calls, just show the response
      final content = message['content'] as String? ?? '';
      final assistantMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content: content,
        timestamp: DateTime.now(),
      );
      await provider.addMessage(assistantMessage);
      _scrollToBottom();
    }
  }

  Future<void> _handleToolCalls(
    List toolCalls,
    ConversationProvider provider,
    OpenRouterService openRouterService,
    List<Map<String, dynamic>> apiMessages,
    List<Map<String, dynamic>> allTools,
  ) async {
    // Show tool call messages with arguments
    for (final toolCall in toolCalls) {
      final toolName = toolCall['function']['name'];
      final toolArgsStr = toolCall['function']['arguments'];

      // Parse arguments for display
      String argsDisplay = '';
      try {
        final Map<String, dynamic> toolArgs;
        if (toolArgsStr is String) {
          toolArgs = Map<String, dynamic>.from(
            const JsonCodec().decode(toolArgsStr),
          );
        } else {
          toolArgs = Map<String, dynamic>.from(toolArgsStr);
        }

        if (toolArgs.isNotEmpty) {
          final prettyArgs = const JsonEncoder.withIndent(
            '  ',
          ).convert(toolArgs);
          argsDisplay = '\n\nArguments:\n```json\n$prettyArgs\n```';
        }
      } catch (e) {
        argsDisplay = '\n\nArguments: (failed to parse)';
      }

      final toolMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content: '🔧 Calling tool: $toolName$argsDisplay',
        timestamp: DateTime.now(),
        isDisplayOnly: true, // Don't send this to the LLM
      );
      await provider.addMessage(toolMessage);
    }
    _scrollToBottom();

    // Save the assistant message with tool_calls (for API reconstruction)
    final toolCallMessage = Message(
      id: const Uuid().v4(),
      conversationId: widget.conversation.id,
      role: MessageRole.assistant,
      content: '', // Empty content for tool call messages
      timestamp: DateTime.now(),
      toolCallData: jsonEncode(toolCalls),
    );
    await provider.addMessage(toolCallMessage);

    // Execute tool calls
    final toolResults = <Map<String, dynamic>>[];
    for (final toolCall in toolCalls) {
      final toolId = toolCall['id'];
      final toolName = toolCall['function']['name'];
      final toolArgsStr = toolCall['function']['arguments'];

      // Parse arguments
      final Map<String, dynamic> toolArgs;
      if (toolArgsStr is String) {
        toolArgs = Map<String, dynamic>.from(
          const JsonCodec().decode(toolArgsStr),
        );
      } else {
        toolArgs = Map<String, dynamic>.from(toolArgsStr);
      }

      // Find which MCP server has this tool
      String? result;
      for (final entry in _mcpTools.entries) {
        final serverId = entry.key;
        final tools = entry.value;

        if (tools.any((t) => t.name == toolName)) {
          // Execute the tool
          try {
            final mcpClient = _mcpClients[serverId];
            if (mcpClient != null) {
              final toolResult = await mcpClient.callTool(toolName, toolArgs);
              result = toolResult.content.map((c) => c.text ?? '').join('\n');
            }
          } catch (e) {
            result = 'Error executing tool: $e';
          }
          break;
        }
      }

      toolResults.add({
        'tool_call_id': toolId,
        'role': 'tool',
        'name': toolName,
        'content': result ?? 'Tool not found',
      });

      // Save tool result message (for API reconstruction - not displayed)
      final toolResultMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: MessageRole.tool,
        content: result ?? 'Tool not found',
        timestamp: DateTime.now(),
        toolCallId: toolId,
        toolName: toolName,
      );
      await provider.addMessage(toolResultMessage);

      // Create a display-only message to show the result when thinking is enabled
      final displayResult = result ?? 'Tool not found';
      final displayMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content: '✅ Result from $toolName:\n\n$displayResult',
        timestamp: DateTime.now(),
        isDisplayOnly: true, // Don't send this to the LLM
      );
      await provider.addMessage(displayMessage);
      _scrollToBottom();
    }

    // Reload messages to get the tool calls and results we just saved
    final updatedMessages = provider.getMessages(widget.conversation.id);
    final updatedApiMessages = updatedMessages
        .where((msg) => !msg.isDisplayOnly)
        .map<Map<String, dynamic>>((msg) => msg.toApiMessage())
        .toList();

    // Get final response with tool results using streaming to capture reasoning
    final messageId = const Uuid().v4();
    final assistantMessage = Message(
      id: messageId,
      conversationId: widget.conversation.id,
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
    );
    await provider.addMessage(assistantMessage);
    _scrollToBottom();

    setState(() {
      _streamingMessageId = messageId;
      _streamingContent = '';
      _streamingReasoning = '';
    });

    try {
      print(
        'ChatScreen: Starting stream for tool response with ${updatedApiMessages.length} messages',
      );
      print('ChatScreen: Full updatedApiMessages structure:');
      for (int i = 0; i < updatedApiMessages.length; i++) {
        print('  [$i]: ${jsonEncode(updatedApiMessages[i])}');
      }

      await for (final chunk in openRouterService.chatCompletionStream(
        model: widget.conversation.model,
        messages: updatedApiMessages,
        tools: allTools,
      )) {
        if (!mounted) break;

        print('ChatScreen: RAW CHUNK: "$chunk"');

        setState(() {
          if (chunk.startsWith('REASONING:')) {
            _streamingReasoning += chunk.substring('REASONING:'.length);
          } else {
            _streamingContent += chunk;
          }
        });
        _scrollToBottom();
      }

      print('ChatScreen: FINAL RAW CONTENT: "$_streamingContent"');
      print('ChatScreen: FINAL RAW REASONING: "$_streamingReasoning"');

      // Update message with final content
      if (mounted) {
        if (_streamingContent.isNotEmpty) {
          await provider.updateMessage(messageId, _streamingContent);
        } else {
          // No content received, delete the placeholder message
          await provider.deleteMessage(messageId);
        }
      }
    } catch (e, stackTrace) {
      print('ChatScreen: Error in tool response streaming:');
      print('Error: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during tool response: $e')),
        );
      }
      rethrow;
    } finally {
      setState(() {
        _streamingMessageId = null;
        _streamingContent = '';
        _streamingReasoning = '';
      });
    }
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
                Text(conversation.title),
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

                    print(
                      'ChatScreen: Building ListView with ${messages.length} messages, streaming: $_streamingMessageId, content length: ${_streamingContent.length}',
                    );

                    // Filter messages based on thinking mode
                    final displayMessages = messages.where((msg) {
                      // Always show user messages
                      if (msg.role == MessageRole.user) return true;
                      
                      // Hide display-only messages when thinking is hidden
                      if (!_showThinking && msg.isDisplayOnly) return false;
                      
                      // Hide tool role messages (internal only, always hidden from UI)
                      // These are sent to the API but never shown to users
                      if (msg.role == MessageRole.tool) return false;
                      
                      // Hide empty assistant messages unless they're actively streaming
                      if (msg.role == MessageRole.assistant && 
                          msg.content.isEmpty && 
                          msg.id != _streamingMessageId) {
                        return false;
                      }
                      
                      return true;
                    }).toList();

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: displayMessages.length,
                      itemBuilder: (context, index) {
                        final message = displayMessages[index];
                        // If this is the streaming message, show live content
                        if (message.id == _streamingMessageId) {
                          print(
                            'ChatScreen: Rendering streaming message ${message.id} with reasoning: ${_streamingReasoning.length}, content: ${_streamingContent.length}',
                          );

                          // Build content with reasoning if available
                          String displayContent = '';
                          if (_showThinking && _streamingReasoning.isNotEmpty) {
                            displayContent =
                                '<thinking>\n$_streamingReasoning\n</thinking>\n\n';
                          }
                          displayContent += _streamingContent;

                          if (displayContent.isNotEmpty) {
                            final streamingMessage = Message(
                              id: message.id,
                              conversationId: message.conversationId,
                              role: message.role,
                              content: displayContent,
                              timestamp: message.timestamp,
                            );
                            return MessageBubble(
                              message: streamingMessage,
                              isStreaming: true,
                            );
                          } else {
                            // Show empty message with streaming indicator
                            return MessageBubble(
                              message: message,
                              isStreaming: true,
                            );
                          }
                        }
                        return MessageBubble(message: message);
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
                        'Thinking...',
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
              'Based on this conversation, generate a short, descriptive title (maximum 6 words, no quotes): ${messages.first.content}',
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
