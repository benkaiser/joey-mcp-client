import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/mcp_server.dart';
import '../models/elicitation.dart';
import '../providers/conversation_provider.dart';
import '../services/openrouter_service.dart';
import '../services/default_model_service.dart';
import '../services/database_service.dart';
import '../services/mcp_client_service.dart';
import '../services/chat_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/sampling_request_dialog.dart';
import '../widgets/elicitation_url_card.dart';
import '../widgets/elicitation_form_card.dart';
import '../widgets/thinking_indicator.dart';

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
  bool _authenticationRequired = false;
  // Map of elicitation message IDs to their responder callbacks
  final Map<String, Function(Map<String, dynamic>)> _elicitationResponders = {};
  // Track responded elicitations to prevent duplicate sends
  final Set<String> _respondedElicitationIds = {};

  @override
  void initState() {
    super.initState();
    _loadModelDetails();
    _loadMcpServers();
    _loadShowThinking();
  }

  Future<void> _loadShowThinking() async {
    final showThinking = await DefaultModelService.getShowThinking();
    if (mounted) {
      setState(() {
        _showThinking = showThinking;
      });
    }
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

    // Navigate to auth screen - replace entire navigation stack
    Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
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

  Future<void> _stopMessage() async {
    if (_chatService != null && _isLoading) {
      final provider = context.read<ConversationProvider>();
      final messages = provider.getMessages(widget.conversation.id);

      await _chatService!.cancelCurrentRequest(
        conversationId: widget.conversation.id,
        messages: List.from(messages),
      );

      setState(() {
        _isLoading = false;
        _streamingContent = '';
        _streamingReasoning = '';
        _currentToolName = null;
        _isToolExecuting = false;
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
        _authenticationRequired = false; // Reset auth flag on new message
        _respondedElicitationIds
            .clear(); // Clear responded IDs for new conversation turn
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

    if (event is StreamingStarted) {
      // New iteration starting - clear tool execution state
      setState(() {
        _currentToolName = null;
        _isToolExecuting = false;
      });
    } else if (event is ContentChunk) {
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
    } else if (event is ElicitationRequestReceived) {
      // Create an elicitation message that will be displayed inline
      final elicitationMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: MessageRole.elicitation,
        content: event.request.message,
        timestamp: DateTime.now(),
        elicitationData: jsonEncode({
          'id': event.request.id,
          'mode': event.request.mode.toJson(),
          'message': event.request.message,
          'elicitationId': event.request.elicitationId,
          'url': event.request.url,
          'requestedSchema': event.request.requestedSchema,
        }),
      );

      // Store the responder callback keyed by message ID
      _elicitationResponders[elicitationMessage.id] = event.onRespond;

      // Add message to provider
      provider.addMessage(elicitationMessage);
      _scrollToBottom();
    } else if (event is AuthenticationRequired) {
      // Handle auth error by showing a message in the chat
      // The error will be displayed as a special card in the message list
      setState(() {
        _isLoading = false;
        _streamingContent = '';
        _streamingReasoning = '';
        _currentToolName = null;
        _isToolExecuting = false;
        _authenticationRequired = true;
      });
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

  /// Handle URL mode elicitation response
  Future<void> _handleUrlElicitationResponse(
    String messageId,
    ElicitationRequest request,
    ElicitationAction action,
  ) async {
    final responder = _elicitationResponders[messageId];
    if (responder == null) return;

    final elicitationId = request.elicitationId ?? messageId;

    // Check if we've already responded to this elicitation
    if (_respondedElicitationIds.contains(elicitationId)) {
      print('Already responded to elicitation $elicitationId, skipping');
      return;
    }

    final response = request.toResponseJson(action: action);
    responder(response);

    // Mark as responded
    setState(() {
      _respondedElicitationIds.add(elicitationId);
    });

    // Update the message with response state
    final provider = context.read<ConversationProvider>();
    final messages = provider.getMessages(widget.conversation.id);
    final messageIndex = messages.indexWhere((m) => m.id == messageId);
    if (messageIndex != -1) {
      final message = messages[messageIndex];
      final elicitationData = jsonDecode(message.elicitationData!);
      elicitationData['responseState'] = action.toJson();
      final updatedMessage = message.copyWith(
        elicitationData: jsonEncode(elicitationData),
      );
      await provider.updateFullMessage(updatedMessage);
    }
  }

  /// Handle form mode elicitation response
  Future<void> _handleFormElicitationResponse(
    String messageId,
    ElicitationRequest request,
    ElicitationAction action,
    Map<String, dynamic>? content,
  ) async {
    final responder = _elicitationResponders[messageId];
    if (responder == null) return;

    final elicitationId = request.elicitationId ?? messageId;

    // Check if we've already responded to this elicitation
    if (_respondedElicitationIds.contains(elicitationId)) {
      print('Already responded to elicitation $elicitationId, skipping');
      return;
    }

    final response = request.toResponseJson(action: action, content: content);
    responder(response);

    // Mark as responded
    setState(() {
      _respondedElicitationIds.add(elicitationId);
    });

    // Update the message with response state and submitted content
    final provider = context.read<ConversationProvider>();
    final messages = provider.getMessages(widget.conversation.id);
    final messageIndex = messages.indexWhere((m) => m.id == messageId);
    if (messageIndex != -1) {
      final message = messages[messageIndex];
      final elicitationData = jsonDecode(message.elicitationData!);
      elicitationData['responseState'] = action.toJson();
      if (content != null) {
        elicitationData['submittedContent'] = content;
      }
      final updatedMessage = message.copyWith(
        elicitationData: jsonEncode(elicitationData),
      );
      await provider.updateFullMessage(updatedMessage);
    }
  }

  Widget _buildAuthRequiredCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: Theme.of(context).colorScheme.error,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Authentication Required',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Your OpenRouter session has expired. Please sign in again to continue chatting.',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Navigate to auth screen (replaces current screen)
                    Navigator.pushReplacementNamed(context, '/auth');
                  },
                  icon: const Icon(Icons.login),
                  label: const Text('Sign In with OpenRouter'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteMessage(
    String messageId,
    ConversationProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text(
          'Are you sure you want to delete this message? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.deleteMessage(messageId);
    }
  }

  Future<void> _editMessage(
    Message message,
    ConversationProvider provider,
  ) async {
    final controller = TextEditingController(text: message.content);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit your message below. All messages after this one will be removed, and the conversation will continue from this point.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Type your message...',
              ),
              maxLines: null,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Edit and Resend'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (result != null && result.isNotEmpty && mounted) {
      // Get all messages in the conversation
      final allMessages = provider.getMessages(widget.conversation.id);

      // Find the index of the message being edited
      final editIndex = allMessages.indexWhere((m) => m.id == message.id);

      if (editIndex >= 0) {
        // Delete this message and all messages after it
        for (int i = editIndex; i < allMessages.length; i++) {
          await provider.deleteMessage(allMessages[i].id);
        }

        // Set the edited text in the message controller and trigger normal send flow
        _messageController.text = result;
        await _sendMessage();
      }
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
            title: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _showRenameDialog(conversation.title),
                child: Column(
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
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: [
              IconButton(
                icon: Icon(
                  _showThinking ? Icons.visibility : Icons.visibility_off,
                ),
                tooltip: _showThinking ? 'Hide thinking' : 'Show thinking',
                onPressed: () async {
                  final newValue = !_showThinking;
                  await DefaultModelService.setShowThinking(newValue);
                  setState(() {
                    _showThinking = newValue;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.note_add),
                tooltip: 'Start new conversation',
                onPressed: () => _startNewConversation(),
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
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Filter messages based on thinking mode and role
                    final displayMessages = messages.where((msg) {
                      // Always show user messages
                      if (msg.role == MessageRole.user) return true;

                      // Always show elicitation messages
                      if (msg.role == MessageRole.elicitation) return true;

                      // Show tool role messages (as indicators when thinking disabled)
                      if (msg.role == MessageRole.tool) {
                        return true;
                      }

                      // Hide empty assistant messages without tool calls or reasoning
                      if (msg.role == MessageRole.assistant &&
                          msg.content.isEmpty &&
                          msg.reasoning == null &&
                          msg.toolCallData == null) {
                        return false;
                      }

                      // Show assistant messages with tool calls (as indicators when thinking disabled)
                      if (msg.role == MessageRole.assistant &&
                          msg.toolCallData != null) {
                        return true;
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
                              : 0) +
                          (_authenticationRequired ? 1 : 0),
                      itemBuilder: (context, index) {
                        // Show auth required card at the end
                        if (_authenticationRequired &&
                            index ==
                                displayMessages.length +
                                    ((_streamingContent.isNotEmpty ||
                                            _streamingReasoning.isNotEmpty)
                                        ? 1
                                        : 0)) {
                          return _buildAuthRequiredCard();
                        }

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
                            onDelete: null, // Can't delete while streaming
                            onEdit: null,
                          );
                        }

                        final message = displayMessages[index];

                        // Render elicitation messages as cards
                        if (message.role == MessageRole.elicitation) {
                          final elicitationData = jsonDecode(
                            message.elicitationData!,
                          );
                          final request = ElicitationRequest(
                            id: elicitationData['id'] ?? message.id,
                            mode: ElicitationMode.fromString(
                              elicitationData['mode'] ?? 'form',
                            ),
                            message: elicitationData['message'] ?? '',
                            elicitationId: elicitationData['elicitationId'],
                            url: elicitationData['url'],
                            requestedSchema: elicitationData['requestedSchema'],
                          );

                          // Check if already responded
                          final responseStateStr =
                              elicitationData['responseState'] as String?;
                          final responseState = responseStateStr != null
                              ? ElicitationAction.fromString(responseStateStr)
                              : null;
                          final submittedContent =
                              elicitationData['submittedContent']
                                  as Map<String, dynamic>?;

                          if (request.mode == ElicitationMode.url) {
                            return ElicitationUrlCard(
                              request: request,
                              responseState: responseState,
                              onRespond: responseState == null
                                  ? (action) => _handleUrlElicitationResponse(
                                      message.id,
                                      request,
                                      action,
                                    )
                                  : null,
                            );
                          } else {
                            return ElicitationFormCard(
                              request: request,
                              responseState: responseState,
                              submittedContent: submittedContent,
                              onRespond: responseState == null
                                  ? (action, content) =>
                                        _handleFormElicitationResponse(
                                          message.id,
                                          request,
                                          action,
                                          content,
                                        )
                                  : null,
                            );
                          }
                        }

                        // Format tool result messages
                        if (message.role == MessageRole.tool) {
                          // Show minimal indicator when thinking is disabled
                          if (!_showThinking) {
                            return ThinkingIndicator(message: message);
                          }
                          // Check if this is an error result
                          final isError =
                              message.content.startsWith(
                                'Failed to parse tool arguments',
                              ) ||
                              message.content.startsWith(
                                'Error executing tool',
                              ) ||
                              message.content.startsWith('Tool not found') ||
                              message.content.startsWith('MCP error');
                          final icon = isError ? '❌' : '✅';
                          final formattedMessage = message.copyWith(
                            content:
                                '$icon **Result from ${message.toolName}:**\n\n${message.content}',
                          );
                          return MessageBubble(
                            message: formattedMessage,
                            showThinking: _showThinking,
                            onDelete: () =>
                                _deleteMessage(formattedMessage.id, provider),
                            onEdit: null, // Tool messages can't be edited
                          );
                        }

                        // Format assistant messages with tool calls
                        if (message.role == MessageRole.assistant &&
                            message.toolCallData != null) {
                          // Show minimal indicator when thinking is disabled
                          if (!_showThinking) {
                            return ThinkingIndicator(message: message);
                          }

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
                                // Show the raw arguments when parsing fails
                                toolCallContent +=
                                    '\n\nArguments (failed to parse):\n```\n$toolArgsStr\n```';
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
                            onDelete: () =>
                                _deleteMessage(formattedMessage.id, provider),
                            onEdit: null, // Tool call messages can't be edited
                          );
                        }

                        return MessageBubble(
                          message: message,
                          showThinking: _showThinking,
                          onDelete: () => _deleteMessage(message.id, provider),
                          onEdit: message.role == MessageRole.user
                              ? () => _editMessage(message, provider)
                              : null,
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            color: Colors.black.withValues(alpha: 0.3),
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
                  if (!_isLoading) {
                    _sendMessage();
                  }
                  _focusNode.requestFocus();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _isLoading ? _stopMessage : _sendMessage,
              icon: Icon(_isLoading ? Icons.stop : Icons.send),
              style: IconButton.styleFrom(
                backgroundColor: _isLoading
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
                foregroundColor: _isLoading
                    ? Theme.of(context).colorScheme.onError
                    : Theme.of(context).colorScheme.onPrimary,
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

  Future<void> _startNewConversation() async {
    final provider = context.read<ConversationProvider>();

    // Create a new conversation with the same model as the current one
    final newConversation = await provider.createConversation(
      model: widget.conversation.model,
    );

    // Copy MCP servers from current conversation to new conversation
    if (_mcpServers.isNotEmpty) {
      final serverIds = _mcpServers.map((s) => s.id).toList();
      await DatabaseService.instance.setConversationMcpServers(
        newConversation.id,
        serverIds,
      );
    }

    if (mounted) {
      // Replace current chat screen with the new conversation
      // Use fade transition to indicate this is a replacement, not forward navigation
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              ChatScreen(conversation: newConversation),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 200),
        ),
      );
    }
  }

  void _showRenameDialog(String currentTitle) {
    showDialog(
      context: context,
      builder: (dialogContext) => _RenameDialog(
        initialTitle: currentTitle,
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
