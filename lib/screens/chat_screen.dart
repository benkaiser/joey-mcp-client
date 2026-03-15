import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:mcp_dart/mcp_dart.dart' show TextContent;
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/mcp_app_ui.dart';
import '../models/mcp_server.dart';
import '../models/elicitation.dart';
import '../models/pending_image.dart';
import '../providers/conversation_provider.dart';
import '../services/openrouter_service.dart';
import '../services/default_model_service.dart';
import '../services/database_service.dart';
import '../services/chat_service.dart';
import '../services/mcp_oauth_manager.dart';
import '../services/mcp_server_manager.dart';
import '../services/background_chat_manager.dart';
import '../services/mcp_app_ui_service.dart';
import '../services/mcp_client_service.dart';
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
import '../widgets/mcp_app_webview.dart';
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
  bool _isAtBottom = true;
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
  McpOAuthManager _oauthManager = McpOAuthManager();
  McpServerManager _serverManager = McpServerManager();

  // Cached provider reference for use in dispose()
  ConversationProvider? _cachedProvider;
  // Stream subscription for chat events (so we can cancel on dispose)
  StreamSubscription? _chatEventSubscription;
  // Manual disposed flag for async safety
  bool _disposed = false;

  // Display mode state for MCP App WebViews
  /// GlobalKeys for McpAppWebView instances, keyed by message ID.
  /// Owned here so the same key can be used both inline (MessageList) and
  /// in overlay positions (fullscreen/PIP), enabling reparenting without
  /// recreating the WebView.
  final Map<String, GlobalKey<State<McpAppWebView>>> _webViewKeys = {};

  /// Current display mode per message ID: 'inline' | 'fullscreen' | 'pip' | 'hidden'
  final Map<String, String> _webViewDisplayModes = {};

  /// View-declared available display modes per message ID
  final Map<String, List<String>> _viewAvailableDisplayModes = {};

  /// LayerLinks for CompositedTransformTarget/Follower pairs (inline mode).
  /// The target is placed in MessageList's placeholder; the follower wraps
  /// the WebView in the ChatScreen Stack so it visually tracks the placeholder
  /// without ever moving in the widget tree.
  final Map<String, LayerLink> _webViewLayerLinks = {};

  /// Current reported heights per WebView (from size-changed notifications)
  final Map<String, double> _webViewHeights = {};

  /// Host-supported display modes
  static const List<String> _hostAvailableDisplayModes = ['inline', 'fullscreen', 'pip'];

  /// Whether we're currently loading uiData blobs
  bool _loadingUiData = false;

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
  void scrollToBottomIfAtBottom() {
    // With reverse: true, new content at position 0 is auto-visible.
    // No explicit scroll needed.
  }

  @override
  void initState() {
    super.initState();
    _loadModelDetails();
    _loadShowThinking();
    _focusNode.onKeyEvent = _handleKeyEvent;

    // Check if there's a background chat to reattach
    final bgChat = BackgroundChatManager.instance.detach(widget.conversation.id);
    final reattached = bgChat != null;
    if (bgChat != null) {
      _chatService = bgChat.chatService;
      _serverManager = bgChat.serverManager;
      _oauthManager = bgChat.oauthManager;
      _isLoading = true;

      // Re-subscribe to events
      final provider = context.read<ConversationProvider>();
      _chatEventSubscription = _chatService!.events.listen((event) {
        handleChatEvent(event, provider);
      });
    }

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
    if (!reattached) {
      _serverManager.loadMcpServers(widget.conversation.id);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cachedProvider = context.read<ConversationProvider>();
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
    _disposed = true;
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _audioHandler.dispose();
    _oauthManager.removeListener(_onMcpStateChanged);
    _serverManager.removeListener(_onMcpStateChanged);

    // Cancel the UI event subscription so no more setState calls fire
    _chatEventSubscription?.cancel();
    _chatEventSubscription = null;

    // If agentic loop is still running, hand off to background manager
    if (_isLoading && _chatService != null && _cachedProvider != null) {
      BackgroundChatManager.instance.register(
        ActiveChat(
          chatService: _chatService!,
          serverManager: _serverManager,
          oauthManager: _oauthManager,
          conversationId: widget.conversation.id,
          model: widget.conversation.model,
        ),
        _cachedProvider!,
      );
      // Don't dispose the services — background manager owns them now
    } else {
      _chatService?.dispose();
      _oauthManager.dispose();
      _serverManager.dispose();
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
    // With reverse: true on ListView, position 0 is the bottom.
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
            uiService: _serverManager.uiService,
            appOnlyTools: _serverManager.appOnlyTools,
          );

          // Listen to chat events
          _chatEventSubscription = _chatService!.events.listen((event) {
            handleChatEvent(event, provider);
          });
        }

        // Get all messages for context (load blobs first for API calls)
        await provider.loadAllBlobsForConversation(widget.conversation.id);
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
      } on OpenRouterPaymentRequiredException {
        // Handled by ChatEventHandlerMixin via PaymentRequired event
      } on OpenRouterRateLimitException {
        // Handled by ChatEventHandlerMixin via RateLimitExceeded event
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
        if (!_disposed && mounted) {
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
      if (_disposed || !mounted) return;
      print('Fatal error in _sendMessage: $e');
      print('Stack trace: $stackTrace');
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

  /// Get or create a GlobalKey for the McpAppWebView associated with a message.
  GlobalKey<State<McpAppWebView>> _webViewKeyFor(String messageId) {
    return _webViewKeys.putIfAbsent(
        messageId, () => GlobalKey<State<McpAppWebView>>());
  }

  /// Get or create a LayerLink for the inline anchor of a WebView.
  LayerLink _layerLinkFor(String messageId) {
    return _webViewLayerLinks.putIfAbsent(messageId, () => LayerLink());
  }

  /// Handle height change reported by a WebView.
  void _handleWebViewHeightChanged(String messageId, double height) {
    if (_webViewHeights[messageId] != height) {
      setState(() {
        _webViewHeights[messageId] = height;
      });
    }
  }

  /// Set display mode for a WebView (host-side UI control).
  /// Validates that the view supports the requested mode before switching.
  /// Set [viewRequested] to true when the view itself requested the mode
  /// (via ui/request-display-mode), which bypasses the view-capabilities check
  /// since the view obviously supports any mode it requests.
  void _setDisplayMode(String messageId, String mode, {bool viewRequested = false}) {
    // 'hidden' is always allowed (host-only feature)
    if (mode != 'inline' && mode != 'hidden' && !viewRequested) {
      final viewModes = _viewAvailableDisplayModes[messageId] ?? [];
      if (!viewModes.contains(mode)) {
        // View doesn't support this mode, fall back to inline
        debugPrint('ChatScreen: View $messageId does not support mode "$mode" (declared: $viewModes), falling back to inline');
        mode = 'inline';
      }
    }

    // Only one fullscreen at a time — return any existing fullscreen to inline
    if (mode == 'fullscreen') {
      final existingFullscreen = _webViewDisplayModes.entries
          .where((e) => e.value == 'fullscreen' && e.key != messageId)
          .toList();
      for (final entry in existingFullscreen) {
        _webViewDisplayModes[entry.key] = 'inline';
      }
    }

    debugPrint('ChatScreen: Setting display mode for $messageId to "$mode"');
    setState(() {
      _webViewDisplayModes[messageId] = mode;
    });
  }

  /// Handle a display mode request from a WebView (programmatic, via ui/request-display-mode).
  void _handleRequestDisplayMode(String messageId, String requestedMode) {
    _setDisplayMode(messageId, requestedMode, viewRequested: true);
  }

  /// Handle view capabilities received from a WebView (via ui/initialize).
  void _handleViewCapabilitiesReceived(String messageId, List<String> modes) {
    setState(() {
      _viewAvailableDisplayModes[messageId] = modes;
    });
  }

  Widget _buildAuthRequiredCard() {
    return const AuthRequiredCard();
  }

  /// Handle a message from an MCP App WebView
  void _handleUiMessage(String message, {List<PendingImage> images = const []}) {
    // Add any images from the MCP App to the pending images
    for (final image in images) {
      _imageHandler.pendingImages.add(image);
    }
    // Insert the message into the text input and trigger send
    _messageController.text = message;
    _sendMessage();
  }

  /// Handle model context update from an MCP App WebView.
  /// Persists the context as a mcpAppContext message linked to the parent tool result.
  Future<void> _handleUpdateModelContext(
    String parentMessageId,
    List<dynamic> content,
    Map<String, dynamic>? structuredContent,
  ) async {
    final provider = context.read<ConversationProvider>();
    final messages = provider.getMessages(widget.conversation.id);

    // Check for existing mcpAppContext message with matching toolCallId
    final existingIndex = messages.indexWhere(
      (m) => m.role == MessageRole.mcpAppContext && m.toolCallId == parentMessageId,
    );

    final contentJson = jsonEncode(content);
    final structuredContentJson = structuredContent != null ? jsonEncode(structuredContent) : null;

    if (existingIndex != -1) {
      // Update existing context message in place
      final existing = messages[existingIndex];
      final updated = existing.copyWith(
        content: contentJson,
        notificationData: structuredContentJson,
      );
      await provider.updateFullMessage(updated);
    } else {
      // Create a new mcpAppContext message
      final contextMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: MessageRole.mcpAppContext,
        content: contentJson,
        timestamp: DateTime.now(),
        toolCallId: parentMessageId,
        notificationData: structuredContentJson,
      );
      await provider.addMessage(contextMessage);
    }
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

    // Capture context-dependent service before any async gaps
    final openRouterService = context.read<OpenRouterService>();

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
      // Initialize ChatService if needed
      if (_chatService == null) {
        _chatService = ChatService(
          openRouterService: openRouterService,
          mcpClients: _serverManager.mcpClients,
          mcpTools: _serverManager.mcpTools,
          serverNames: _serverManager.serverNames,
          uiService: _serverManager.uiService,
          appOnlyTools: _serverManager.appOnlyTools,
        );

        _chatEventSubscription = _chatService!.events.listen((event) {
          handleChatEvent(event, provider);
        });
      }

      // Get remaining messages for context (load blobs first for API calls)
      await provider.loadAllBlobsForConversation(widget.conversation.id);
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
    } on OpenRouterPaymentRequiredException {
      // Handled by ChatEventHandlerMixin via PaymentRequired event
    } on OpenRouterRateLimitException {
      // Handled by ChatEventHandlerMixin via RateLimitExceeded event
    } catch (e, stackTrace) {
      print('Error in _regenerateLastResponse: $e');
      print('Stack trace: $stackTrace');
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (!_disposed && mounted) {
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
    // Load blob data for this message so images/audio are available in the edit dialog
    await provider.loadBlobData(widget.conversation.id, message.id);
    if (!mounted) return;
    // Re-fetch message after blob load to get updated imageData/audioData
    final messages = provider.getMessages(widget.conversation.id);
    final updatedMessage = messages.firstWhere(
      (m) => m.id == message.id,
      orElse: () => message,
    );

    final result = await showDialog<EditMessageResult>(
      context: context,
      builder: (context) => EditMessageDialog(
        initialText: updatedMessage.content,
        imageDataJson: updatedMessage.imageData,
        audioDataJson: updatedMessage.audioData,
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
                          Flexible(
                            child: Text(
                              getPricingText(),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                    fontSize: 11,
                                  ),
                              overflow: TextOverflow.ellipsis,
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
              PopupMenuButton<String>(
                icon: const Icon(Icons.share),
                tooltip: 'Share / Export',
                onSelected: (value) {
                  if (value == 'share_text') {
                    shareConversation();
                  } else if (value == 'export_json') {
                    exportConversationAsJson();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'share_text',
                    child: ListTile(
                      leading: Icon(Icons.text_snippet),
                      title: Text('Share as Text'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'export_json',
                    child: ListTile(
                      leading: Icon(Icons.download),
                      title: Text('Export as JSON'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.note_add),
                tooltip: 'Start new conversation',
                onPressed: () => startNewConversation(),
              ),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  // Show OAuth banner if servers need authentication
                  if (_oauthManager.serversNeedingOAuth.any((s) =>
                      _oauthManager.serverOAuthStatus[s.id] != McpOAuthCardStatus.completed))
                    McpOAuthBanner(
                      serversNeedingAuth: _oauthManager.serversNeedingOAuth,
                      serverOAuthStatus: _oauthManager.serverOAuthStatus,
                      onAuthenticate: (server) => _oauthManager.startServerOAuth(
                        server,
                        mcpServers: _serverManager.mcpServers,
                      ),
                      onSkip: (server) => _oauthManager.skipServerOAuth(server),
                      onDismiss: () {
                        _oauthManager.dismissAll();
                      },
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        MessageList(
                          conversationId: widget.conversation.id,
                          showThinking: _showThinking,
                          streamingContent: _streamingContent,
                          streamingReasoning: _streamingReasoning,
                          isLoading: _isLoading,
                          authenticationRequired: _authenticationRequired,
                          scrollController: _scrollController,
                          onAtBottomChanged: (atBottom) {
                            setState(() {
                              _isAtBottom = atBottom;
                            });
                          },
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
                          webViewDisplayModes: _webViewDisplayModes,
                          viewAvailableDisplayModes: _viewAvailableDisplayModes,
                          webViewHeights: _webViewHeights,
                          onSetDisplayMode: _setDisplayMode,
                          layerLinkFor: _layerLinkFor,
                          hostAvailableDisplayModes: _hostAvailableDisplayModes,
                        ),
                        // Command palette — visible when at bottom
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 0,
                          child: IgnorePointer(
                            ignoring: !_isAtBottom,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: _isAtBottom ? 1.0 : 0.0,
                              child: _buildCommandPalette(),
                            ),
                          ),
                        ),
                        // "New content below" bubble — visible when scrolled up during streaming
                        if (_isLoading && !_isAtBottom &&
                            _scrollController.hasClients &&
                            _scrollController.position.maxScrollExtent > 0)
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: 1.0,
                                child: GestureDetector(
                                  onTap: _scrollToBottom,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.15),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'New content below',
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.keyboard_arrow_down,
                                          size: 18,
                                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _buildMessageInput(),
                ],
              ),
              // All active WebViews rendered here so they never move in the tree
              ..._buildWebViewOverlays(provider),
            ],
          ),
        );
      },
    );
  }

  /// Build all active (non-hidden) WebView overlays.
  /// Every WebView is always rendered here in the Stack — never in MessageList —
  /// so switching display modes doesn't cause the platform view to be recreated.
  /// Each WebView is wrapped in a _WebViewHost with a stable ValueKey so that
  /// mode changes only affect the host's build output, not the WebView itself.
  List<Widget> _buildWebViewOverlays(ConversationProvider provider) {
    final messages = provider.getMessages(widget.conversation.id);

    // Find all messages that have UI data (active WebViews)
    // Use hasUiData flag which is available even when uiData blob isn't loaded
    final uiMessages = messages.where((m) => m.hasUiData).toList();
    if (uiMessages.isEmpty) return [];

    // Check if any messages need their uiData loaded
    final needsLoading = uiMessages.any((m) => m.uiData == null);
    if (needsLoading) {
      // Trigger async load of uiData for messages that need it (once)
      if (!_loadingUiData) {
        _loadingUiData = true;
        provider.loadUiDataForConversation(widget.conversation.id).then((_) {
          _loadingUiData = false;
        });
      }
      // Return empty for now — will rebuild when data is loaded via notifyListeners
      return [];
    }

    final widgets = <Widget>[];

    for (final message in uiMessages) {
      final messageId = message.id;
      final currentMode = _webViewDisplayModes[messageId] ?? 'inline';

      // Hidden mode: don't render the WebView at all (unmounted)
      if (currentMode == 'hidden') continue;

      McpAppUiData uiData;
      try {
        uiData = McpAppUiData.fromJson(
          jsonDecode(message.uiData!) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('ChatScreen: Failed to parse uiData for $messageId: $e');
        continue;
      }

      final mcpClient = _serverManager.mcpClients[uiData.serverId];
      Map<String, McpTool>? serverAppOnlyTools;
      final appOnlyList = _serverManager.appOnlyTools[uiData.serverId];
      if (appOnlyList != null) {
        serverAppOnlyTools = { for (final t in appOnlyList) t.name: t };
      }

      final viewModes = _viewAvailableDisplayModes[messageId] ?? [];
      final inlineHeight = _webViewHeights[messageId] ?? 300.0;

      widgets.add(
        _WebViewHost(
          // Stable key per message — never changes across mode switches
          key: ValueKey('webview_host_$messageId'),
          messageId: messageId,
          uiData: uiData,
          mcpClient: mcpClient,
          uiService: _serverManager.uiService,
          appOnlyTools: serverAppOnlyTools,
          displayMode: currentMode,
          hostAvailableDisplayModes: _hostAvailableDisplayModes,
          viewAvailableDisplayModes: viewModes,
          inlineHeight: inlineHeight,
          layerLink: _layerLinkFor(messageId),
          onUiMessage: _handleUiMessage,
          onUpdateModelContext: _handleUpdateModelContext,
          onRequestDisplayMode: _handleRequestDisplayMode,
          onViewCapabilitiesReceived: _handleViewCapabilitiesReceived,
          onHeightChanged: _handleWebViewHeightChanged,
          onSetDisplayMode: _setDisplayMode,
          toolName: _toolNameFromUri(uiData.resourceUri),
          webViewKey: _webViewKeyFor(messageId),
        ),
      );
    }

    return widgets;
  }

  /// Extract tool name from URI like "ui://server/toolName"
  String _toolNameFromUri(String uri) {
    final parts = Uri.tryParse(uri);
    if (parts != null && parts.pathSegments.isNotEmpty) {
      return parts.pathSegments.last;
    }
    return uri;
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
        uiService: _serverManager.uiService,
        appOnlyTools: _serverManager.appOnlyTools,
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
      modelSupportsImages: modelSupportsImages,
      modelSupportsAudio: modelSupportsAudio,
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

/// A stable host widget for a single McpAppWebView.
///
/// **Critical design constraint:** Flutter platform views (InAppWebView) are
/// destroyed and recreated whenever their element is unmounted. To prevent this
/// when switching display modes, the [build] method must always return the
/// **exact same widget-type chain** from [_WebViewHostState] down to the
/// [McpAppWebView]. Changing ancestor widget types (e.g. swapping
/// `CompositedTransformFollower` for `Material`) would cause Flutter's element
/// reconciliation to unmount the subtree, destroying the native WebView.
///
/// The approach: every mode returns
///   Positioned → CompositedTransformFollower → SizedBox → Material → SafeArea
///     → Stack → [ Column → [toolbar, Expanded → webView], ...pip chrome ]
/// Only the *properties* of these widgets change (constraints, link, colors);
/// the widget *types* are identical across modes.
class _WebViewHost extends StatefulWidget {
  final String messageId;
  final McpAppUiData uiData;
  final McpClientService? mcpClient;
  final McpAppUiService? uiService;
  final Map<String, McpTool>? appOnlyTools;
  final String displayMode;
  final List<String> hostAvailableDisplayModes;
  final List<String> viewAvailableDisplayModes;
  final double inlineHeight;
  final LayerLink layerLink;
  final String toolName;
  final GlobalKey webViewKey;
  final void Function(String message, {List<PendingImage> images})? onUiMessage;
  final void Function(String messageId, List<dynamic> content, Map<String, dynamic>? structuredContent)? onUpdateModelContext;
  final void Function(String messageId, String requestedMode)? onRequestDisplayMode;
  final void Function(String messageId, List<String> modes)? onViewCapabilitiesReceived;
  final void Function(String messageId, double height)? onHeightChanged;
  final void Function(String messageId, String mode) onSetDisplayMode;

  const _WebViewHost({
    super.key,
    required this.messageId,
    required this.uiData,
    this.mcpClient,
    this.uiService,
    this.appOnlyTools,
    required this.displayMode,
    required this.hostAvailableDisplayModes,
    required this.viewAvailableDisplayModes,
    required this.inlineHeight,
    required this.layerLink,
    required this.toolName,
    required this.webViewKey,
    this.onUiMessage,
    this.onUpdateModelContext,
    this.onRequestDisplayMode,
    this.onViewCapabilitiesReceived,
    this.onHeightChanged,
    required this.onSetDisplayMode,
  });

  @override
  State<_WebViewHost> createState() => _WebViewHostState();
}

class _WebViewHostState extends State<_WebViewHost> {
  @override
  void initState() {
    super.initState();
    debugPrint('_WebViewHost [${widget.messageId}]: initState (hashCode=$hashCode)');
  }

  @override
  void dispose() {
    debugPrint('_WebViewHost [${widget.messageId}]: dispose (hashCode=$hashCode)');
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _WebViewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.displayMode != widget.displayMode) {
      debugPrint('_WebViewHost [${widget.messageId}]: displayMode changed ${oldWidget.displayMode} → ${widget.displayMode} (hashCode=$hashCode)');
    }
  }

  // PIP drag / resize state (kept here so it survives mode switches)
  Offset _pipOffset = const Offset(16, 16);
  double _pipWidth = 280;
  double _pipHeight = 200;
  static const double _pipHeaderHeight = 32;
  static const double _pipMinWidth = 180;
  static const double _pipMinHeight = 120;
  static const double _pipEdgePadding = 8;
  static const double _pipTopPadding = 56;
  static const double _pipResizeHandleSize = 16;

  void _clampPipOffset(Size parentSize) {
    final totalHeight = _pipHeight + _pipHeaderHeight;
    final maxRight = parentSize.width - _pipWidth - _pipEdgePadding;
    final maxBottom = parentSize.height - totalHeight - _pipTopPadding;
    _pipOffset = Offset(
      _pipOffset.dx.clamp(_pipEdgePadding, maxRight.clamp(_pipEdgePadding, double.infinity)),
      _pipOffset.dy.clamp(_pipEdgePadding, maxBottom.clamp(_pipEdgePadding, double.infinity)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webView = McpAppWebView(
      key: widget.webViewKey,
      uiData: widget.uiData,
      messageId: widget.messageId,
      mcpClient: widget.mcpClient,
      uiService: widget.uiService,
      appOnlyTools: widget.appOnlyTools,
      onUiMessage: widget.onUiMessage,
      onUpdateModelContext: widget.onUpdateModelContext,
      displayMode: widget.displayMode,
      hostAvailableDisplayModes: widget.hostAvailableDisplayModes,
      onRequestDisplayMode: widget.onRequestDisplayMode,
      onViewCapabilitiesReceived: widget.onViewCapabilitiesReceived,
      onHeightChanged: widget.onHeightChanged,
    );

    final bool isFullscreen = widget.displayMode == 'fullscreen';
    final bool isPip = widget.displayMode == 'pip';
    final supportsPip = widget.viewAvailableDisplayModes.contains('pip');
    final supportsFullscreen = widget.viewAvailableDisplayModes.contains('fullscreen');

    // Simple approach: let the WebView resize naturally per mode.
    // The McpAppWebView caches its InAppWebView instance in initState
    // so the same widget is always returned from build().

    if (isFullscreen) {
      return Positioned.fill(
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            child: Column(
              children: [
                _buildFullscreenToolbar(context, supportsPip),
                Expanded(child: webView),
              ],
            ),
          ),
        ),
      );
    }

    if (isPip) {
      final screenSize = MediaQuery.of(context).size;
      _clampPipOffset(screenSize);
      final maxPipW = screenSize.width * 0.9;
      final maxPipH = screenSize.height * 0.8;

      return Positioned(
        right: _pipOffset.dx,
        bottom: _pipOffset.dy,
        width: _pipWidth,
        height: _pipHeight + _pipHeaderHeight,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Stack(
            children: [
              Column(
                children: [
                  _buildPipHeader(context, supportsFullscreen),
                  Expanded(child: webView),
                ],
              ),
              ..._buildPipResizeHandles(screenSize, maxPipW, maxPipH),
            ],
          ),
        ),
      );
    }

    // Inline mode — cap height at 40% of screen.
    // The CompositedTransformFollower aligns its child to the Target in the
    // MessageList.  The Target sits inside the ListView's 16px padding, so
    // it is (stackWidth - 32px) wide.  We give the Container that same width
    // so the WebView + border + scrollbar fit exactly within the message
    // content area.
    final screenHeight = MediaQuery.of(context).size.height;
    final clampedInlineHeight = widget.inlineHeight.clamp(50.0, screenHeight * 0.4);

    // Determine which mode buttons to show
    final showFullscreen = widget.viewAvailableDisplayModes.contains('fullscreen')
        && widget.hostAvailableDisplayModes.contains('fullscreen');
    final showPip = widget.viewAvailableDisplayModes.contains('pip')
        && widget.hostAvailableDisplayModes.contains('pip');

    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: widget.layerLink,
        showWhenUnlinked: false,
        child: Container(
          // screenWidth - 32 for ListView padding, - 32 for extra left+right
          // margin to visually inset the WebView within the message area.
          width: MediaQuery.of(context).size.width - 64.0,
          height: clampedInlineHeight,
          margin: const EdgeInsets.only(left: 16.0, top: 4.0, bottom: 4.0),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          // Use a ClipRRect child instead of clipBehavior on Container,
          // so the clip doesn't cut into the border's rounded corners.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Stack(
              children: [
                Positioned.fill(child: webView),
                // Bottom-anchored floating toolbar
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
                          Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.only(top: 12.0, bottom: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showFullscreen)
                          _InlineToolbarButton(
                            icon: Icons.fullscreen,
                            tooltip: 'Fullscreen',
                            onPressed: () => widget.onSetDisplayMode(widget.messageId, 'fullscreen'),
                          ),
                        if (showPip)
                          _InlineToolbarButton(
                            icon: Icons.picture_in_picture_alt,
                            tooltip: 'Picture-in-picture',
                            onPressed: () => widget.onSetDisplayMode(widget.messageId, 'pip'),
                          ),
                        _InlineToolbarButton(
                          icon: Icons.visibility_off_outlined,
                          tooltip: 'Hide',
                          onPressed: () => widget.onSetDisplayMode(widget.messageId, 'hidden'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenToolbar(BuildContext context, bool supportsPip) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.fullscreen_exit),
            tooltip: 'Return inline',
            onPressed: () => widget.onSetDisplayMode(widget.messageId, 'inline'),
          ),
          const Spacer(),
          if (supportsPip)
            IconButton(
              icon: const Icon(Icons.picture_in_picture_alt),
              tooltip: 'Picture-in-picture',
              onPressed: () => widget.onSetDisplayMode(widget.messageId, 'pip'),
            ),
          IconButton(
            icon: const Icon(Icons.visibility_off_outlined),
            tooltip: 'Hide',
            onPressed: () => widget.onSetDisplayMode(widget.messageId, 'hidden'),
          ),
        ],
      ),
    );
  }

  Widget _buildPipHeader(BuildContext context, bool supportsFullscreen) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _pipOffset = Offset(
            _pipOffset.dx - details.delta.dx,
            _pipOffset.dy - details.delta.dy,
          );
          _clampPipOffset(MediaQuery.of(context).size);
        });
      },
      child: Container(
        height: _pipHeaderHeight,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            Icon(Icons.drag_indicator, size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                widget.toolName,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (supportsFullscreen)
              _PipHeaderButton(
                icon: Icons.fullscreen,
                tooltip: 'Fullscreen',
                onPressed: () => widget.onSetDisplayMode(widget.messageId, 'fullscreen'),
              ),
            _PipHeaderButton(
              icon: Icons.fullscreen_exit,
              tooltip: 'Return inline',
              onPressed: () => widget.onSetDisplayMode(widget.messageId, 'inline'),
            ),
            _PipHeaderButton(
              icon: Icons.visibility_off_outlined,
              tooltip: 'Hide',
              onPressed: () => widget.onSetDisplayMode(widget.messageId, 'hidden'),
            ),
          ],
        ),
      ),
    );
  }
  /// Build resize handles for PIP mode (corner + edge handles).
  List<Widget> _buildPipResizeHandles(Size screenSize, double maxW, double maxH) {
    Widget corner(Alignment alignment, SystemMouseCursor cursor,
        void Function(DragUpdateDetails) onPan) {
      return Positioned(
        left: alignment.x < 0 ? 0 : null,
        right: alignment.x > 0 ? 0 : null,
        top: alignment.y < 0 ? 0 : null,
        bottom: alignment.y > 0 ? 0 : null,
        width: _pipResizeHandleSize,
        height: _pipResizeHandleSize,
        child: GestureDetector(
          onPanUpdate: (d) => setState(() { onPan(d); _clampPipOffset(screenSize); }),
          child: MouseRegion(cursor: cursor, child: const SizedBox.expand()),
        ),
      );
    }

    Widget edge({
      double? left, double? right, double? top, double? bottom,
      double? width, double? height,
      required SystemMouseCursor cursor,
      required void Function(DragUpdateDetails) onPan,
    }) {
      return Positioned(
        left: left, right: right, top: top, bottom: bottom,
        width: width, height: height,
        child: GestureDetector(
          onPanUpdate: (d) => setState(() { onPan(d); _clampPipOffset(screenSize); }),
          child: MouseRegion(cursor: cursor, child: const SizedBox.expand()),
        ),
      );
    }

    return [
      // Corners
      corner(Alignment.topLeft, SystemMouseCursors.resizeUpLeft, (d) {
        _pipWidth = (_pipWidth - d.delta.dx).clamp(_pipMinWidth, maxW);
        _pipHeight = (_pipHeight - d.delta.dy).clamp(_pipMinHeight, maxH);
      }),
      corner(Alignment.bottomLeft, SystemMouseCursors.resizeDownLeft, (d) {
        _pipWidth = (_pipWidth - d.delta.dx).clamp(_pipMinWidth, maxW);
        final nh = (_pipHeight + d.delta.dy).clamp(_pipMinHeight, maxH);
        _pipOffset = Offset(_pipOffset.dx, _pipOffset.dy - (nh - _pipHeight));
        _pipHeight = nh;
      }),
      corner(Alignment.topRight, SystemMouseCursors.resizeUpRight, (d) {
        final nw = (_pipWidth + d.delta.dx).clamp(_pipMinWidth, maxW);
        _pipOffset = Offset(_pipOffset.dx - (nw - _pipWidth), _pipOffset.dy);
        _pipWidth = nw;
        _pipHeight = (_pipHeight - d.delta.dy).clamp(_pipMinHeight, maxH);
      }),
      corner(Alignment.bottomRight, SystemMouseCursors.resizeDownRight, (d) {
        final nw = (_pipWidth + d.delta.dx).clamp(_pipMinWidth, maxW);
        _pipOffset = Offset(_pipOffset.dx - (nw - _pipWidth), _pipOffset.dy);
        _pipWidth = nw;
        final nh = (_pipHeight + d.delta.dy).clamp(_pipMinHeight, maxH);
        _pipOffset = Offset(_pipOffset.dx, _pipOffset.dy - (nh - _pipHeight));
        _pipHeight = nh;
      }),
      // Edges
      edge(left: 0, top: _pipResizeHandleSize, width: _pipResizeHandleSize / 2,
          bottom: _pipResizeHandleSize, cursor: SystemMouseCursors.resizeLeft,
          onPan: (d) { _pipWidth = (_pipWidth - d.delta.dx).clamp(_pipMinWidth, maxW); }),
      edge(top: 0, left: _pipResizeHandleSize, right: _pipResizeHandleSize,
          height: _pipResizeHandleSize / 2, cursor: SystemMouseCursors.resizeUp,
          onPan: (d) { _pipHeight = (_pipHeight - d.delta.dy).clamp(_pipMinHeight, maxH); }),
      edge(right: 0, top: _pipResizeHandleSize, width: _pipResizeHandleSize / 2,
          bottom: _pipResizeHandleSize, cursor: SystemMouseCursors.resizeRight,
          onPan: (d) {
            final nw = (_pipWidth + d.delta.dx).clamp(_pipMinWidth, maxW);
            _pipOffset = Offset(_pipOffset.dx - (nw - _pipWidth), _pipOffset.dy);
            _pipWidth = nw;
          }),
      edge(bottom: 0, left: _pipResizeHandleSize, right: _pipResizeHandleSize,
          height: _pipResizeHandleSize / 2, cursor: SystemMouseCursors.resizeDown,
          onPan: (d) {
            final nh = (_pipHeight + d.delta.dy).clamp(_pipMinHeight, maxH);
            _pipOffset = Offset(_pipOffset.dx, _pipOffset.dy - (nh - _pipHeight));
            _pipHeight = nh;
          }),
    ];
  }
}

/// Compact icon button used in the PIP header bar.
class _PipHeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _PipHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Icon button used in the bottom-anchored floating toolbar on inline WebViews.
/// Note: no Tooltip wrapper — Tooltip internally uses OverlayPortal which
/// triggers a debug assertion when nested inside CompositedTransformFollower.
class _InlineToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _InlineToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
            child: Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
