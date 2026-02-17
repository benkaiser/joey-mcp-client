import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:mcp_dart/mcp_dart.dart' show TextContent;
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/mcp_server.dart';
import '../models/elicitation.dart';
import '../providers/conversation_provider.dart';
import '../services/openrouter_service.dart';
import '../services/default_model_service.dart';
import '../services/database_service.dart';
import '../services/chat_service.dart';
import '../services/mcp_oauth_manager.dart';
import '../services/mcp_server_manager.dart';
import '../utils/audio_attachment_handler.dart';
import '../utils/image_attachment_handler.dart';
import 'chat_event_handler.dart';
import 'conversation_actions.dart';
import '../widgets/auth_required_card.dart';
import '../widgets/edit_message_dialog.dart';
import '../widgets/loading_status_indicator.dart';
import '../widgets/command_palette.dart';
import '../widgets/message_input.dart';
import '../widgets/message_list.dart';
import '../widgets/mcp_oauth_card.dart';
import '../widgets/mcp_server_selection_dialog.dart';
import '../widgets/usage_info_button.dart';
import 'mcp_debug_screen.dart';
import 'mcp_prompts_screen.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;

  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with ChatEventHandlerMixin, ConversationActionsMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  Map<String, dynamic>? _modelDetails;
  bool _hasGeneratedTitle = false;
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
  // Track MCP progress notifications
  McpProgressNotificationReceived? _currentProgress;

  // Delegates
  final ImageAttachmentHandler _imageHandler = ImageAttachmentHandler();
  final AudioAttachmentHandler _audioHandler = AudioAttachmentHandler();
  final McpOAuthManager _oauthManager = McpOAuthManager();
  final McpServerManager _serverManager = McpServerManager();

  // --- ChatEventHandlerMixin interface ---
  @override
  bool get isLoading => _isLoading;
  @override
  set isLoadingValue(bool value) => _isLoading = value;
  @override
  String get streamingContent => _streamingContent;
  @override
  set streamingContentValue(String value) => _streamingContent = value;
  @override
  String get streamingReasoning => _streamingReasoning;
  @override
  set streamingReasoningValue(String value) => _streamingReasoning = value;
  @override
  String? get currentToolName => _currentToolName;
  @override
  set currentToolNameValue(String? value) => _currentToolName = value;
  @override
  bool get isToolExecuting => _isToolExecuting;
  @override
  set isToolExecutingValue(bool value) => _isToolExecuting = value;
  @override
  bool get authenticationRequired => _authenticationRequired;
  @override
  set authenticationRequiredValue(bool value) => _authenticationRequired = value;
  @override
  McpProgressNotificationReceived? get currentProgress => _currentProgress;
  @override
  set currentProgressValue(McpProgressNotificationReceived? value) =>
      _currentProgress = value;
  @override
  Map<String, Function(Map<String, dynamic>)> get elicitationResponders =>
      _elicitationResponders;
  @override
  Set<String> get respondedElicitationIds => _respondedElicitationIds;
  @override
  ChatService? get chatService => _chatService;

  // --- ConversationActionsMixin interface ---
  @override
  Map<String, dynamic>? get modelDetails => _modelDetails;
  @override
  List<McpServer> get mcpServers => _serverManager.mcpServers;

  // --- Shared interface methods ---
  @override
  String getCurrentModel() => _getCurrentModel();
  @override
  void loadModelDetails() => _loadModelDetails();
  @override
  void refreshToolsForServer(String serverId) =>
      _serverManager.refreshToolsForServer(serverId);
  @override
  void handleServerNeedsOAuth(String serverId, String serverUrl) {
    final server = _serverManager.mcpServers.firstWhere(
      (s) => s.id == serverId || s.url == serverUrl,
      orElse: () => _serverManager.mcpServers.first,
    );
    _oauthManager.handleServerNeedsOAuth(server, _serverManager.mcpServers);
  }

  @override
  void initState() {
    super.initState();
    _loadModelDetails();
    _loadShowThinking();
    _focusNode.onKeyEvent = _handleKeyEvent;

    // Wire up image handler
    _imageHandler.onStateChanged = () => setState(() {});

    // Wire up audio handler
    _audioHandler.onStateChanged = () => setState(() {});

    // Wire up OAuth manager
    _oauthManager.addListener(_onMcpStateChanged);
    _oauthManager.onReinitializeServer = (server) async {
      // Close existing client and clear session before re-init
      if (_serverManager.mcpClients.containsKey(server.id)) {
        await _serverManager.mcpClients[server.id]!.close();
        _serverManager.mcpClients.remove(server.id);
        _serverManager.mcpTools.remove(server.id);
      }
      await DatabaseService.instance.updateMcpSessionId(
        widget.conversation.id,
        server.id,
        null,
      );
      await _serverManager.initializeMcpServer(server);
    };
    _oauthManager.onShowMessage = (message, color) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: color),
        );
      }
    };
    _oauthManager.onServerOAuthRequired = (serverName) {
      if (mounted) {
        final provider = context.read<ConversationProvider>();
        final oauthMessage = Message(
          id: const Uuid().v4(),
          conversationId: widget.conversation.id,
          role: MessageRole.modelChange,
          content: 'OAuth required for $serverName',
          timestamp: DateTime.now(),
        );
        provider.addTransientMessage(oauthMessage);
      }
    };
    _oauthManager.initDeepLinkListener();

    // Wire up server manager
    _serverManager.oauthManager = _oauthManager;
    _serverManager.addListener(_onMcpStateChanged);
    _serverManager.onServerNeedsOAuth = (server) {
      _oauthManager.handleServerNeedsOAuth(server, _serverManager.mcpServers);
    };
    _serverManager.onServerDisconnected = (serverName) {
      if (mounted) {
        final provider = context.read<ConversationProvider>();
        final disconnectedMessage = Message(
          id: const Uuid().v4(),
          conversationId: widget.conversation.id,
          role: MessageRole.modelChange,
          content: 'Disconnected from $serverName',
          timestamp: DateTime.now(),
        );
        provider.addTransientMessage(disconnectedMessage);
      }
    };
    _serverManager.onServerConnected = (serverName) {
      if (mounted) {
        final provider = context.read<ConversationProvider>();
        final connectedMessage = Message(
          id: const Uuid().v4(),
          conversationId: widget.conversation.id,
          role: MessageRole.modelChange,
          content: 'Connected to $serverName',
          timestamp: DateTime.now(),
        );
        provider.addTransientMessage(connectedMessage);
      }
    };
    _serverManager.loadMcpServers(widget.conversation.id);
  }

  void _onMcpStateChanged() {
    if (mounted) setState(() {});
  }

  /// Handle key events for the message input.
  /// Enter sends the message; Shift+Enter inserts a newline.
  /// Cmd/Ctrl+V pastes images from clipboard on desktop.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      if (!_isLoading) {
        _sendMessage();
      }
      return KeyEventResult.handled;
    }
    // Intercept Cmd/Ctrl+V on desktop to paste images
    if (_imageHandler.isDesktop &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)) {
      _imageHandler.handleDesktopPaste();
      // Don't consume the event — let the text field also handle normal text paste
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _loadShowThinking() async {
    final showThinking = await DefaultModelService.getShowThinking();
    if (mounted) {
      setState(() {
        _showThinking = showThinking;
      });
    }
  }

  Future<void> _loadModelDetails() async {
    try {
      final currentModel = _getCurrentModel();
      final openRouterService = context.read<OpenRouterService>();
      final models = await openRouterService.getModels();
      final model = models.firstWhere(
        (m) => m['id'] == currentModel,
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
    _audioHandler.dispose();
    _oauthManager.removeListener(_onMcpStateChanged);
    _serverManager.removeListener(_onMcpStateChanged);
    _oauthManager.dispose();
    _serverManager.dispose();
    super.dispose();
  }

  /// Handle OpenRouter authentication errors by navigating to auth screen
  void _handleAuthError() {
    if (!mounted) return;

    // Navigate to auth screen - replace entire navigation stack
    Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
  }

  void _scrollToBottom() {
    // With reverse: true on ListView, position 0 is the bottom.
    // We only need to scroll if user has scrolled up to view history.
    if (_scrollController.hasClients && _scrollController.position.pixels > 0) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
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
      if (text.isEmpty && _imageHandler.pendingImages.isEmpty && _audioHandler.pendingAudios.isEmpty) return;

      final provider = context.read<ConversationProvider>();
      final openRouterService = context.read<OpenRouterService>();

      // Encode pending images as base64 JSON
      String? imageDataJson;
      if (_imageHandler.pendingImages.isNotEmpty) {
        final imageList = _imageHandler.pendingImages
            .map(
              (img) => {
                'data': base64Encode(img.bytes),
                'mimeType': img.mimeType,
              },
            )
            .toList();
        imageDataJson = jsonEncode(imageList);
      }

      // Encode pending audios as base64 JSON
      String? audioDataJson;
      if (_audioHandler.pendingAudios.isNotEmpty) {
        final audioList = _audioHandler.pendingAudios
            .map(
              (audio) => {
                'data': base64Encode(audio.bytes),
                'mimeType': audio.mimeType,
              },
            )
            .toList();
        audioDataJson = jsonEncode(audioList);
      }

      // Add user message
      final userMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: MessageRole.user,
        content: text,
        timestamp: DateTime.now(),
        imageData: imageDataJson,
        audioData: audioDataJson,
      );

      await provider.addMessage(userMessage);
      _messageController.text = '';
      _imageHandler.clear();
      _audioHandler.clear();
      setState(() {});
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
            mcpClients: _serverManager.mcpClients,
            mcpTools: _serverManager.mcpTools,
            serverNames: _serverManager.serverNames,
          );

          // Listen to chat events
          _chatService!.events.listen((event) {
            handleChatEvent(event, provider);
          });
        }

        // Get all messages for context
        final messages = provider.getMessages(widget.conversation.id);

        // Check if the model supports image input
        final modelSupportsImages =
            _modelDetails != null &&
            _modelDetails!['architecture'] != null &&
            (_modelDetails!['architecture']['input_modalities'] as List?)
                    ?.contains('image') ==
                true;

        // Check if the model supports audio input
        final modelSupportsAudio =
            _modelDetails != null &&
            _modelDetails!['architecture'] != null &&
            (_modelDetails!['architecture']['input_modalities'] as List?)
                    ?.contains('audio') ==
                true;

        // Get max tool calls setting
        final maxToolCalls = await DefaultModelService.getMaxToolCalls();

        // Run the agentic loop in the chat service
        await _chatService!.runAgenticLoop(
          conversationId: widget.conversation.id,
          model: _getCurrentModel(),
          messages: List.from(messages), // Pass a copy
          maxIterations: maxToolCalls,
          modelSupportsImages: modelSupportsImages,
          modelSupportsAudio: modelSupportsAudio,
        );

        // Auto-generate title after first response if enabled
        if (!_hasGeneratedTitle && mounted) {
          _hasGeneratedTitle = true;
          final autoTitleEnabled =
              await DefaultModelService.getAutoTitleEnabled();
          if (autoTitleEnabled) {
            generateConversationTitle(provider, openRouterService);
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
    return const AuthRequiredCard();
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

  /// Regenerate the last assistant response.
  /// Deletes all messages from the last assistant turn (assistant message +
  /// associated tool call/result messages) and re-sends the conversation.
  Future<void> _regenerateLastResponse(ConversationProvider provider) async {
    if (_isLoading) return;

    final messages = provider.getMessages(widget.conversation.id);
    if (messages.isEmpty) return;

    // Walk backwards from the end to find the start of the last assistant turn.
    // A "turn" includes: the final assistant message, plus any preceding
    // assistant+tool message pairs that belong to that turn (i.e. all messages
    // after the last user message).
    int lastUserIndex = -1;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == MessageRole.user) {
        lastUserIndex = i;
        break;
      }
    }

    if (lastUserIndex < 0) return; // No user message found — nothing to retry

    // Delete all messages after the last user message (the entire assistant turn)
    final messagesToDelete = messages.sublist(lastUserIndex + 1);
    for (final msg in messagesToDelete) {
      await provider.deleteMessage(msg.id);
    }

    // Now re-send: set loading state and trigger the agentic loop
    setState(() {
      _isLoading = true;
      _streamingContent = '';
      _streamingReasoning = '';
      _authenticationRequired = false;
      _respondedElicitationIds.clear();
    });

    try {
      final openRouterService = context.read<OpenRouterService>();

      // Initialize ChatService if needed
      if (_chatService == null) {
        _chatService = ChatService(
          openRouterService: openRouterService,
          mcpClients: _serverManager.mcpClients,
          mcpTools: _serverManager.mcpTools,
          serverNames: _serverManager.serverNames,
        );

        _chatService!.events.listen((event) {
          handleChatEvent(event, provider);
        });
      }

      // Get remaining messages for context
      final remainingMessages = provider.getMessages(widget.conversation.id);

      final modelSupportsImages =
          _modelDetails != null &&
          _modelDetails!['architecture'] != null &&
          (_modelDetails!['architecture']['input_modalities'] as List?)
                  ?.contains('image') ==
              true;

      final modelSupportsAudio =
          _modelDetails != null &&
          _modelDetails!['architecture'] != null &&
          (_modelDetails!['architecture']['input_modalities'] as List?)
                  ?.contains('audio') ==
              true;

      final maxToolCalls = await DefaultModelService.getMaxToolCalls();

      await _chatService!.runAgenticLoop(
        conversationId: widget.conversation.id,
        model: _getCurrentModel(),
        messages: List.from(remainingMessages),
        maxIterations: maxToolCalls,
        modelSupportsImages: modelSupportsImages,
        modelSupportsAudio: modelSupportsAudio,
      );
    } on OpenRouterAuthException {
      _handleAuthError();
    } catch (e, stackTrace) {
      print('Error in _regenerateLastResponse: $e');
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
  }

  Future<void> _editMessage(
    Message message,
    ConversationProvider provider,
  ) async {
    final result = await showDialog<EditMessageResult>(
      context: context,
      builder: (context) => EditMessageDialog(
        initialText: message.content,
        imageDataJson: message.imageData,
        audioDataJson: message.audioData,
      ),
    );

    if (result != null &&
        (result.text.isNotEmpty || result.images.isNotEmpty || result.audios.isNotEmpty) &&
        mounted) {
      // Get all messages in the conversation
      final allMessages = provider.getMessages(widget.conversation.id);

      // Find the index of the message being edited
      final editIndex = allMessages.indexWhere((m) => m.id == message.id);

      if (editIndex >= 0) {
        // Delete this message and all messages after it
        for (int i = editIndex; i < allMessages.length; i++) {
          await provider.deleteMessage(allMessages[i].id);
        }

        // Restore surviving images into the image handler so _sendMessage
        // picks them up when building the new Message.
        _imageHandler.clear();
        for (final img in result.images) {
          _imageHandler.pendingImages.add(img);
        }

        // Restore surviving audios into the audio handler so _sendMessage
        // picks them up when building the new Message.
        _audioHandler.clear();
        for (final audio in result.audios) {
          _audioHandler.pendingAudios.add(audio);
        }

        // Set the edited text in the message controller and trigger normal send flow
        _messageController.text = result.text;
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
                onTap: () => showRenameDialog(conversation.title),
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
                          child: GestureDetector(
                            onTap: changeModel,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    conversation.model,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.swap_horiz,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_modelDetails != null &&
                            _modelDetails!['pricing'] != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            getPricingText(),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                  fontSize: 11,
                                ),
                          ),
                        ],
                        if (_serverManager.mcpServers.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.dns,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_serverManager.mcpServers.length} MCP',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
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
                icon: const Icon(Icons.bar_chart_rounded),
                tooltip: 'Conversation usage',
                onPressed: () {
                  final messages = provider.getMessages(widget.conversation.id);
                  showDialog(
                    context: context,
                    builder: (context) =>
                        ConversationUsageDialog(messages: messages),
                  );
                },
              ),
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
                icon: const Icon(Icons.share),
                tooltip: 'Share conversation',
                onPressed: () => shareConversation(),
              ),
              IconButton(
                icon: const Icon(Icons.note_add),
                tooltip: 'Start new conversation',
                onPressed: () => startNewConversation(),
              ),
            ],
          ),
          body: Column(
            children: [
              // Show OAuth banner if servers need authentication
              if (_oauthManager.serversNeedingOAuth.any((s) =>
                  _oauthManager.serverOAuthStatus[s.id] != McpOAuthCardStatus.completed))
                McpOAuthBanner(
                  serversNeedingAuth: _oauthManager.serversNeedingOAuth,
                  serverOAuthStatus: _oauthManager.serverOAuthStatus,
                  onAuthenticate: (server) => _oauthManager.startServerOAuth(server),
                  onSkip: (server) => _oauthManager.skipServerOAuth(server),
                  onDismiss: () {
                    _oauthManager.dismissAll();
                  },
                ),
              Expanded(
                child: MessageList(
                  conversationId: widget.conversation.id,
                  showThinking: _showThinking,
                  streamingContent: _streamingContent,
                  streamingReasoning: _streamingReasoning,
                  isLoading: _isLoading,
                  authenticationRequired: _authenticationRequired,
                  scrollController: _scrollController,
                  buildCommandPalette: _buildCommandPalette,
                  buildAuthRequiredCard: _buildAuthRequiredCard,
                  buildLoadingIndicator: _isLoading
                      ? () => LoadingStatusIndicator(
                            currentToolName: _currentToolName,
                            isToolExecuting: _isToolExecuting,
                            currentProgress: _currentProgress,
                          )
                      : null,
                  onDeleteMessage: _deleteMessage,
                  onEditMessage: _editMessage,
                  onRegenerateLastResponse: _regenerateLastResponse,
                  onUrlElicitationResponse: _handleUrlElicitationResponse,
                  onFormElicitationResponse: _handleFormElicitationResponse,
                ),
              ),
              _buildMessageInput(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommandPalette() {
    return CommandPalette(
      mcpServers: _serverManager.mcpServers,
      connectedServerIds: _serverManager.mcpClients.keys.toSet(),
      onOpenPrompts: _openMcpPromptsScreen,
      onOpenServers: _showMcpServerSelector,
      onOpenDebug: _openMcpDebugScreen,
    );
  }

  Future<void> _showMcpServerSelector() async {
    final currentServerIds = _serverManager.mcpServers.map((s) => s.id).toList();

    final selectedServerIds = await showDialog<List<String>>(
      context: context,
      builder: (context) =>
          McpServerSelectionDialog(initialSelectedServerIds: currentServerIds, isEditing: true),
    );

    // User cancelled
    if (selectedServerIds == null) return;

    // Determine which servers were added and removed
    final currentIds = currentServerIds.toSet();
    final newIds = selectedServerIds.toSet();

    if (currentIds.length == newIds.length && currentIds.containsAll(newIds)) {
      return; // No change
    }

    final removedIds = currentIds.difference(newIds);
    final addedIds = newIds.difference(currentIds);

    // Close removed server clients
    for (final id in removedIds) {
      _oauthManager.removeServer(id);
      await _serverManager.disconnectServer(id, widget.conversation.id);
    }

    // Save the new association to the database
    await DatabaseService.instance.setConversationMcpServers(
      widget.conversation.id,
      selectedServerIds,
    );

    // Reload servers from DB and initialize new ones
    final allServers = await DatabaseService.instance.getAllMcpServers();
    final newMcpServers = allServers
        .where((s) => newIds.contains(s.id))
        .toList();

    _serverManager.updateServerList(newMcpServers);

    // Initialize newly added servers
    for (final id in addedIds) {
      final server = newMcpServers.firstWhere((s) => s.id == id);
      await _serverManager.initializeMcpServer(server);
    }

    // Update ChatService with the new server names
    if (_chatService != null) {
      _chatService!.updateServers(
        mcpClients: _serverManager.mcpClients,
        mcpTools: _serverManager.mcpTools,
        serverNames: _serverManager.serverNames,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('MCP servers updated (${_serverManager.mcpServers.length} active)'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openMcpPromptsScreen() async {
    final result = await Navigator.push<PromptSelectionResult>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            McpPromptsScreen(servers: _serverManager.mcpServers, clients: _serverManager.mcpClients),
      ),
    );

    if (result != null && mounted) {
      // Extract text from the prompt messages and inject into chat
      final textParts = <String>[];
      for (final msg in result.messages) {
        if (msg.content is TextContent) {
          textParts.add((msg.content as TextContent).text);
        }
      }

      if (textParts.isNotEmpty) {
        final promptText = textParts.join('\n\n');
        _messageController.text = promptText;
        _focusNode.requestFocus();
      }
    }
  }

  void _openMcpDebugScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => McpDebugScreen(
          serverManager: _serverManager,
          oauthManager: _oauthManager,
          conversationId: widget.conversation.id,
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return MessageInput(
      messageController: _messageController,
      focusNode: _focusNode,
      isLoading: _isLoading,
      pendingImages: _imageHandler.pendingImages,
      pendingAudios: _audioHandler.pendingAudios,
      isRecording: _audioHandler.isRecording,
      recordingDuration: _audioHandler.recordingDuration,
      onSend: _sendMessage,
      onStop: _stopMessage,
      onPickImageFromGallery: () => _imageHandler.pickImageFromGallery(context),
      onPickImageFromCamera: () => _imageHandler.pickImageFromCamera(context),
      onPickAudioFile: () => _audioHandler.pickAudioFile(context),
      onStartRecording: () => _audioHandler.startRecording(context),
      onStopRecording: () => _audioHandler.stopRecording(),
      onCancelRecording: () => _audioHandler.cancelRecording(),
      onRemovePendingImage: (index) {
        _imageHandler.removeAt(index);
      },
      onRemovePendingAudio: (index) {
        _audioHandler.removeAt(index);
      },
      onContentInserted: _imageHandler.onContentInserted,
    );
  }

  /// Get the current model from the provider (live data)
  String _getCurrentModel() {
    final provider = context.read<ConversationProvider>();
    final conversation = provider.conversations.firstWhere(
      (c) => c.id == widget.conversation.id,
      orElse: () => widget.conversation,
    );
    return conversation.model;
  }
}
