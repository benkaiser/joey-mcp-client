import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:mcp_dart/mcp_dart.dart' show TextContent;
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
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
import '../services/mcp_oauth_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/sampling_request_dialog.dart';
import '../widgets/elicitation_url_card.dart';
import '../widgets/elicitation_form_card.dart';
import '../widgets/thinking_indicator.dart';
import '../widgets/mcp_oauth_card.dart';
import '../widgets/tool_result_media.dart';
import '../widgets/mcp_server_selection_dialog.dart';
import 'mcp_debug_screen.dart';
import 'mcp_prompts_screen.dart';
import 'model_picker_screen.dart';

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
  // Track MCP progress notifications
  McpProgressNotificationReceived? _currentProgress;

  // Image attachments pending send
  final List<_PendingImage> _pendingImages = [];
  final ImagePicker _imagePicker = ImagePicker();

  // MCP OAuth support
  final McpOAuthService _mcpOAuthService = McpOAuthService();
  final AppLinks _appLinks = AppLinks();
  StreamSubscription? _deepLinkSubscription;

  /// Servers that need OAuth authentication
  final List<McpServer> _serversNeedingOAuth = [];

  /// OAuth provider instances for each server
  final Map<String, McpOAuthClientProvider> _oauthProviders = {};

  /// Track OAuth status for each server
  final Map<String, McpOAuthCardStatus> _serverOAuthStatus = {};

  @override
  void initState() {
    super.initState();
    _loadModelDetails();
    _loadMcpServers();
    _loadShowThinking();
    _initMcpOAuthDeepLinkListener();
    _focusNode.onKeyEvent = _handleKeyEvent;
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
    if (_isDesktop &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)) {
      _handleDesktopPaste();
      // Don't consume the event — let the text field also handle normal text paste
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  /// Whether we're running on a desktop platform
  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  /// Handle paste on desktop: check clipboard for image data
  Future<void> _handleDesktopPaste() async {
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        setState(() {
          _pendingImages.add(
            _PendingImage(bytes: imageBytes, mimeType: 'image/png'),
          );
        });
        _showModelImageWarningIfNeeded();
      }
    } catch (e) {
      // Silently fail — clipboard may just contain text
    }
  }

  /// Initialize deep link listener for MCP OAuth callbacks
  void _initMcpOAuthDeepLinkListener() {
    _deepLinkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        // Listen for MCP OAuth callback
        final isCustomScheme = uri.scheme == 'joey' && uri.host == 'mcp-oauth';
        final isHttpsCallback =
            uri.scheme == 'https' &&
            uri.host == 'openrouterauth.benkaiser.dev' &&
            uri.path == '/api/mcp-oauth';

        if (isCustomScheme || isHttpsCallback) {
          _handleMcpOAuthCallback(uri);
        }
      },
      onError: (err) {
        debugPrint('MCP OAuth deep link error: $err');
      },
    );
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
        await _initializeMcpServer(server);
      }
    } catch (e) {
      debugPrint('Failed to load MCP servers: $e');
    }
  }

  /// Initialize a single MCP server, handling OAuth if needed
  Future<void> _initializeMcpServer(McpServer server) async {
    try {
      // Create OAuth provider if server has OAuth tokens
      McpOAuthClientProvider? oauthProvider;

      if (server.oauthStatus != McpOAuthStatus.none ||
          server.oauthTokens != null) {
        oauthProvider = _createOAuthProvider(server);
        _oauthProviders[server.id] = oauthProvider;
      }

      final client = McpClientService(
        serverUrl: server.url,
        headers: server.headers,
        oauthProvider: oauthProvider,
      );

      // Set up auth required callback
      client.onAuthRequired = (serverUrl) {
        _handleServerNeedsOAuth(server);
      };

      // Set up session re-established callback for when server restarts
      client.onSessionReestablished = (newSessionId) {
        debugPrint(
          'MCP: Session re-established for ${server.name}: $newSessionId',
        );
        DatabaseService.instance.updateMcpSessionId(
          widget.conversation.id,
          server.id,
          newSessionId,
        );
        // Refresh tools since the server may have changed
        _refreshToolsForServer(server.id);
      };

      // Look up stored session ID for resumption
      final storedSessionId = await DatabaseService.instance.getMcpSessionId(
        widget.conversation.id,
        server.id,
      );
      if (storedSessionId != null) {
        debugPrint('MCP: Attempting to resume session for ${server.name}');
      }

      await client.initialize(sessionId: storedSessionId);

      List<McpTool> tools;
      try {
        tools = await client.listTools();
      } catch (e) {
        // If listing tools fails with an invalid session error, retry with a fresh session
        if (e.toString().toLowerCase().contains('no valid session') ||
            (e.toString().contains('400') &&
                e.toString().toLowerCase().contains('session'))) {
          debugPrint(
            'MCP: Session invalid after initialize for ${server.name}, retrying fresh...',
          );
          await client.close();
          final freshClient = McpClientService(
            serverUrl: server.url,
            headers: server.headers,
            oauthProvider: oauthProvider,
          );
          freshClient.onAuthRequired = client.onAuthRequired;
          freshClient.onSessionReestablished = client.onSessionReestablished;
          await freshClient.initialize(); // No session ID
          tools = await freshClient.listTools();
          // Replace client reference for the rest of setup
          _mcpClients[server.id] = freshClient;
          _mcpTools[server.id] = tools;
          // Update stored session ID
          await DatabaseService.instance.updateMcpSessionId(
            widget.conversation.id,
            server.id,
            freshClient.sessionId,
          );
          debugPrint(
            'MCP: Fresh session established for ${server.name}: ${freshClient.sessionId}',
          );

          // Update server OAuth status if it was previously pending
          if (server.oauthStatus == McpOAuthStatus.required ||
              server.oauthStatus == McpOAuthStatus.pending) {
            final updatedServer = server.copyWith(
              oauthStatus: McpOAuthStatus.authenticated,
              updatedAt: DateTime.now(),
            );
            await DatabaseService.instance.updateMcpServer(updatedServer);
            final index = _mcpServers.indexWhere((s) => s.id == server.id);
            if (index >= 0) {
              setState(() {
                _mcpServers[index] = updatedServer;
                _serverOAuthStatus.remove(server.id);
              });
            }
          }
          return; // Skip the rest of setup since we've handled it
        }
        rethrow;
      }

      _mcpClients[server.id] = client;
      _mcpTools[server.id] = tools;

      // Persist the session ID (may be new or same as stored)
      final newSessionId = client.sessionId;
      if (newSessionId != storedSessionId) {
        await DatabaseService.instance.updateMcpSessionId(
          widget.conversation.id,
          server.id,
          newSessionId,
        );
        debugPrint('MCP: Stored session ID for ${server.name}: $newSessionId');
      }

      // Update server OAuth status if it was previously pending
      if (server.oauthStatus == McpOAuthStatus.required ||
          server.oauthStatus == McpOAuthStatus.pending) {
        final updatedServer = server.copyWith(
          oauthStatus: McpOAuthStatus.authenticated,
          updatedAt: DateTime.now(),
        );
        await DatabaseService.instance.updateMcpServer(updatedServer);

        // Update local state
        final index = _mcpServers.indexWhere((s) => s.id == server.id);
        if (index >= 0) {
          setState(() {
            _mcpServers[index] = updatedServer;
            _serverOAuthStatus.remove(server.id);
          });
        }
      }
    } on McpAuthRequiredException catch (e) {
      debugPrint('MCP server ${server.name} requires OAuth: $e');
      _handleServerNeedsOAuth(server);
    } catch (e) {
      debugPrint('Failed to initialize MCP server ${server.name}: $e');

      // Check if this looks like an auth error
      if (e.toString().contains('401') ||
          e.toString().toLowerCase().contains('unauthorized') ||
          e.toString().toLowerCase().contains('authentication')) {
        _handleServerNeedsOAuth(server);
      }
    }
  }

  /// Create an OAuth provider for a server
  McpOAuthClientProvider _createOAuthProvider(McpServer server) {
    // Convert stored tokens if available
    McpOAuthTokens? initialTokens;
    if (server.oauthTokens != null) {
      initialTokens = McpOAuthTokens(
        accessToken: server.oauthTokens!.accessToken,
        refreshToken: server.oauthTokens!.refreshToken,
        expiresAt: server.oauthTokens!.expiresAt,
        tokenType: server.oauthTokens!.tokenType,
        scope: server.oauthTokens!.scope,
      );
    }

    return McpOAuthClientProvider(
      serverUrl: server.url,
      clientId: server.oauthClientId,
      clientSecret: server.oauthClientSecret,
      oauthService: _mcpOAuthService,
      initialTokens: initialTokens,
      onAuthRequired: (authUrl) async {
        // Don't auto-launch - let user click the button in the banner
        debugPrint('MCP OAuth required for ${server.name}: $authUrl');
      },
      loadTokens: (serverUrl) async {
        // Reload server from database to get latest tokens
        final servers = await DatabaseService.instance.getAllMcpServers();
        final currentServer = servers.firstWhere(
          (s) => s.url == serverUrl,
          orElse: () => server,
        );

        if (currentServer.oauthTokens != null) {
          return McpOAuthTokens(
            accessToken: currentServer.oauthTokens!.accessToken,
            refreshToken: currentServer.oauthTokens!.refreshToken,
            expiresAt: currentServer.oauthTokens!.expiresAt,
            tokenType: currentServer.oauthTokens!.tokenType,
            scope: currentServer.oauthTokens!.scope,
          );
        }
        return null;
      },
      saveTokens: (serverUrl, tokens) async {
        // Find and update the server with new tokens
        final servers = await DatabaseService.instance.getAllMcpServers();
        final currentServer = servers.firstWhere(
          (s) => s.url == serverUrl,
          orElse: () => server,
        );

        McpServerOAuthTokens? storedTokens;
        if (tokens != null) {
          storedTokens = McpServerOAuthTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt,
            tokenType: tokens.tokenType,
            scope: tokens.scope,
          );
        }

        final updatedServer = currentServer.copyWith(
          oauthStatus: tokens != null
              ? McpOAuthStatus.authenticated
              : McpOAuthStatus.none,
          oauthTokens: storedTokens,
          clearOAuthTokens: tokens == null,
          updatedAt: DateTime.now(),
        );

        await DatabaseService.instance.updateMcpServer(updatedServer);
      },
    );
  }

  /// Handle when a server indicates it needs OAuth
  void _handleServerNeedsOAuth(McpServer server) {
    // Update local server status
    final index = _mcpServers.indexWhere((s) => s.id == server.id);
    if (index >= 0 && !_serversNeedingOAuth.any((s) => s.id == server.id)) {
      setState(() {
        _serversNeedingOAuth.add(_mcpServers[index]);
        _serverOAuthStatus[server.id] = McpOAuthCardStatus.pending;
      });

      // Update server in database
      final updatedServer = server.copyWith(
        oauthStatus: McpOAuthStatus.required,
        updatedAt: DateTime.now(),
      );
      DatabaseService.instance.updateMcpServer(updatedServer);
    }
  }

  /// Handle MCP OAuth callback from deep link
  Future<void> _handleMcpOAuthCallback(Uri uri) async {
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    final error = uri.queryParameters['error'];

    if (error != null) {
      debugPrint('MCP OAuth error: $error');
      // Find the server that was authenticating and mark as failed
      for (final entry in _serverOAuthStatus.entries) {
        if (entry.value == McpOAuthCardStatus.inProgress) {
          setState(() {
            _serverOAuthStatus[entry.key] = McpOAuthCardStatus.failed;
          });
          break;
        }
      }
      return;
    }

    if (code == null || state == null) {
      debugPrint('MCP OAuth callback missing code or state');
      return;
    }

    try {
      // Find which server this is for to get client secret
      final pendingState = _mcpOAuthService.getPendingState(state);
      McpServer? server;

      if (pendingState != null) {
        server = _mcpServers.firstWhere(
          (s) => s.url == pendingState.resourceUrl,
          orElse: () => _serversNeedingOAuth.firstWhere(
            (s) => s.url == pendingState.resourceUrl,
          ),
        );
      }

      // Exchange code for tokens
      final tokens = await _mcpOAuthService.exchangeCodeForTokens(
        authorizationCode: code,
        state: state,
        clientId: server?.oauthClientId,
        clientSecret: server?.oauthClientSecret,
      );

      // Use the server we found, or try to find it again
      if (pendingState == null) {
        // Try to find by URL in our servers
        for (final s in _serversNeedingOAuth) {
          if (_serverOAuthStatus[s.id] == McpOAuthCardStatus.inProgress) {
            await _completeServerOAuth(s, tokens);
            return;
          }
        }
        return;
      }

      if (server == null) {
        server = _mcpServers.firstWhere(
          (s) => s.url == pendingState.resourceUrl,
          orElse: () => _serversNeedingOAuth.firstWhere(
            (s) => s.url == pendingState.resourceUrl,
          ),
        );
      }

      await _completeServerOAuth(server, tokens);
    } catch (e) {
      debugPrint('MCP OAuth token exchange failed: $e');

      // Mark the in-progress server as failed
      for (final entry in _serverOAuthStatus.entries) {
        if (entry.value == McpOAuthCardStatus.inProgress) {
          setState(() {
            _serverOAuthStatus[entry.key] = McpOAuthCardStatus.failed;
          });
          break;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OAuth failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Complete OAuth for a server after successful token exchange
  Future<void> _completeServerOAuth(
    McpServer server,
    McpOAuthTokens tokens,
  ) async {
    // Update OAuth provider with new tokens
    final provider = _oauthProviders[server.id];
    if (provider != null) {
      await provider.updateTokens(tokens);
    }

    // Save tokens to server
    final storedTokens = McpServerOAuthTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAt,
      tokenType: tokens.tokenType,
      scope: tokens.scope,
    );

    final updatedServer = server.copyWith(
      oauthStatus: McpOAuthStatus.authenticated,
      oauthTokens: storedTokens,
      updatedAt: DateTime.now(),
    );

    await DatabaseService.instance.updateMcpServer(updatedServer);

    // Update local state
    final index = _mcpServers.indexWhere((s) => s.id == server.id);
    if (index >= 0) {
      setState(() {
        _mcpServers[index] = updatedServer;
        _serverOAuthStatus[server.id] = McpOAuthCardStatus.completed;
        _serversNeedingOAuth.removeWhere((s) => s.id == server.id);
      });
    }

    // Re-initialize the server with the new tokens
    if (_mcpClients.containsKey(server.id)) {
      await _mcpClients[server.id]!.close();
      _mcpClients.remove(server.id);
      _mcpTools.remove(server.id);
    }

    // Clear stored session ID so we don't try to resume a stale session
    await DatabaseService.instance.updateMcpSessionId(
      widget.conversation.id,
      server.id,
      null,
    );

    await _initializeMcpServer(updatedServer);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${server.name}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Start OAuth flow for a specific server
  Future<void> _startServerOAuth(McpServer server) async {
    try {
      // Create provider if not exists
      if (!_oauthProviders.containsKey(server.id)) {
        _oauthProviders[server.id] = _createOAuthProvider(server);
      }

      setState(() {
        _serverOAuthStatus[server.id] = McpOAuthCardStatus.inProgress;
      });

      // Build and launch auth URL
      final authUrl = await _mcpOAuthService.buildAuthorizationUrl(
        serverUrl: server.url,
        clientId: server.oauthClientId,
        clientSecret: server.oauthClientSecret,
      );

      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch browser');
      }
    } catch (e) {
      debugPrint('Failed to start OAuth for ${server.name}: $e');
      setState(() {
        _serverOAuthStatus[server.id] = McpOAuthCardStatus.failed;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start sign in: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Skip OAuth for a server (remove from pending list)
  void _skipServerOAuth(McpServer server) {
    setState(() {
      _serversNeedingOAuth.removeWhere((s) => s.id == server.id);
      _serverOAuthStatus.remove(server.id);
    });
  }

  /// Start OAuth for all servers that need it
  Future<void> _startAllServersOAuth() async {
    for (final server in _serversNeedingOAuth) {
      if (_serverOAuthStatus[server.id] != McpOAuthCardStatus.inProgress) {
        await _startServerOAuth(server);
        // Only start one at a time to avoid confusion
        break;
      }
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
    _deepLinkSubscription?.cancel();
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
      if (text.isEmpty && _pendingImages.isEmpty) return;

      final provider = context.read<ConversationProvider>();
      final openRouterService = context.read<OpenRouterService>();

      // Encode pending images as base64 JSON
      String? imageDataJson;
      if (_pendingImages.isNotEmpty) {
        final imageList = _pendingImages
            .map(
              (img) => {
                'data': base64Encode(img.bytes),
                'mimeType': img.mimeType,
              },
            )
            .toList();
        imageDataJson = jsonEncode(imageList);
      }

      // Add user message
      final userMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: MessageRole.user,
        content: text,
        timestamp: DateTime.now(),
        imageData: imageDataJson,
      );

      await provider.addMessage(userMessage);
      _messageController.text = '';
      setState(() {
        _pendingImages.clear();
      });
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
          // Build server names map
          final serverNames = <String, String>{};
          for (final server in _mcpServers) {
            serverNames[server.id] = server.name;
          }

          _chatService = ChatService(
            openRouterService: openRouterService,
            mcpClients: _mcpClients,
            mcpTools: _mcpTools,
            serverNames: serverNames,
          );

          // Listen to chat events
          _chatService!.events.listen((event) {
            _handleChatEvent(event, provider);
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
    } else if (event is ReasoningChunk) {
      setState(() {
        _streamingReasoning = event.content;
      });
    } else if (event is MessageCreated) {
      // Clear streaming state when message is persisted
      setState(() {
        _streamingContent = '';
        _streamingReasoning = '';
      });
      // Add message to provider
      provider.addMessage(event.message);
    } else if (event is ToolExecutionStarted) {
      setState(() {
        _currentToolName = event.toolName;
        _isToolExecuting = true; // Now calling the tool
        _currentProgress = null; // Clear any previous progress
      });
    } else if (event is ToolExecutionCompleted) {
      setState(() {
        // Keep the tool name but mark as completed
        _isToolExecuting = false;
        _currentProgress = null; // Clear progress when tool completes
      });
    } else if (event is ConversationComplete) {
      setState(() {
        _streamingContent = '';
        _streamingReasoning = '';
        _currentToolName = null;
        _isToolExecuting = false;
        _isLoading = false;
        _currentProgress = null; // Clear progress when conversation completes
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
    } else if (event is McpProgressNotificationReceived) {
      // Update progress state
      setState(() {
        _currentProgress = event;
      });
    } else if (event is McpToolsListChanged) {
      // Refresh tools list for the server
      _refreshToolsForServer(event.serverId);
    } else if (event is McpResourcesListChanged) {
      // Could refresh resources here if we had a resources UI
      print('Resources list changed for server: ${event.serverId}');
    } else if (event is McpGenericNotificationReceived) {
      // Create a notification message to display in the chat
      final notificationMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: MessageRole.mcpNotification,
        content: '', // Content is in notificationData
        timestamp: DateTime.now(),
        notificationData: jsonEncode({
          'serverName': event.serverName,
          'serverId': event.serverId,
          'method': event.method,
          'params': event.params,
        }),
      );

      // Add message to provider
      provider.addMessage(notificationMessage);
    } else if (event is McpAuthRequiredForServer) {
      // Find the server that needs OAuth and show the dialog
      final server = _mcpServers.firstWhere(
        (s) => s.id == event.serverId || s.url == event.serverUrl,
        orElse: () => _mcpServers.first,
      );
      _handleServerNeedsOAuth(server);
    }
  }

  /// Refresh the tools list for a specific MCP server
  Future<void> _refreshToolsForServer(String serverId) async {
    final client = _mcpClients[serverId];
    if (client == null) return;

    try {
      final tools = await client.listTools();
      setState(() {
        _mcpTools[serverId] = tools;
      });
      print('Refreshed tools for server $serverId: ${tools.length} tools');
    } catch (e) {
      print('Failed to refresh tools for server $serverId: $e');
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
              preferredModel: _getCurrentModel(),
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
        final serverNames = <String, String>{};
        for (final server in _mcpServers) {
          serverNames[server.id] = server.name;
        }

        _chatService = ChatService(
          openRouterService: openRouterService,
          mcpClients: _mcpClients,
          mcpTools: _mcpTools,
          serverNames: serverNames,
        );

        _chatService!.events.listen((event) {
          _handleChatEvent(event, provider);
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
                          child: GestureDetector(
                            onTap: _changeModel,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    conversation.model,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context).colorScheme.primary,
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
                            _getPricingText(),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.6),
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
              // Show OAuth banner if servers need authentication
              if (_serversNeedingOAuth.isNotEmpty)
                McpOAuthBanner(
                  serversNeedingAuth: _serversNeedingOAuth,
                  onAuthenticateAll: _startAllServersOAuth,
                  onDismiss: () {
                    setState(() {
                      _serversNeedingOAuth.clear();
                      _serverOAuthStatus.clear();
                    });
                  },
                ),
              Expanded(
                child: Consumer<ConversationProvider>(
                  builder: (context, provider, child) {
                    final messages = provider.getMessages(
                      widget.conversation.id,
                    );

                    if (messages.isEmpty) {
                      return Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.message_outlined,
                                    size: 64,
                                    color: Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Start a conversation',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Type a message below to begin',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 4.0,
                            ),
                            child: _buildCommandPalette(),
                          ),
                        ],
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

                    // Find the last assistant message with actual content
                    // (for the regenerate button). We only show regenerate on
                    // the final visible assistant bubble, and only when not loading.
                    String? lastAssistantContentMessageId;
                    if (!_isLoading) {
                      for (int i = displayMessages.length - 1; i >= 0; i--) {
                        final m = displayMessages[i];
                        if (m.role == MessageRole.assistant &&
                            m.content.isNotEmpty &&
                            m.toolCallData == null) {
                          lastAssistantContentMessageId = m.id;
                          break;
                        }
                      }
                    }

                    // Calculate total item count
                    final hasStreaming =
                        _streamingContent.isNotEmpty ||
                        _streamingReasoning.isNotEmpty;
                    final itemCount =
                        displayMessages.length +
                        1 + // command palette
                        (hasStreaming ? 1 : 0) +
                        (_authenticationRequired ? 1 : 0);

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      reverse: true, // Anchor to bottom, grow upward
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        // Since list is reversed, index 0 is the bottom (newest)
                        // We need to map reversed index to actual items:
                        // - Index 0: command palette
                        // - Index 1: auth card (if present) or streaming (if present) or last message
                        // - Index 2: streaming (if auth present) or messages
                        // - Higher indices: older messages

                        // Show command palette at index 0 (bottom)
                        if (index == 0) {
                          return _buildCommandPalette();
                        }

                        // Shift by 1 for command palette
                        final paletteAdjustedIndex = index - 1;

                        // Show auth required card
                        if (_authenticationRequired &&
                            paletteAdjustedIndex == 0) {
                          return _buildAuthRequiredCard();
                        }

                        // Adjust index if auth card is present
                        final adjustedIndex = _authenticationRequired
                            ? paletteAdjustedIndex - 1
                            : paletteAdjustedIndex;

                        // Show streaming content at adjusted index 0
                        if (hasStreaming && adjustedIndex == 0) {
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

                        // Calculate message index (reversed: higher index = older message)
                        final messageIndex = hasStreaming
                            ? adjustedIndex - 1
                            : adjustedIndex;
                        // Map to actual message (from end of list for reversed display)
                        final actualMessageIndex =
                            displayMessages.length - 1 - messageIndex;

                        if (actualMessageIndex < 0 ||
                            actualMessageIndex >= displayMessages.length) {
                          return const SizedBox.shrink();
                        }

                        final message = displayMessages[actualMessageIndex];

                        // Render model change indicator
                        if (message.role == MessageRole.modelChange) {
                          return MessageBubble(
                            message: message,
                            showThinking: _showThinking,
                            onDelete: () =>
                                _deleteMessage(message.id, provider),
                            onEdit: null,
                          );
                        }

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
                            // Still show images/audio even when thinking is hidden
                            if (message.imageData != null ||
                                message.audioData != null) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ThinkingIndicator(message: message),
                                  if (message.imageData != null)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 16),
                                      child: ToolResultImages(
                                        imageDataJson: message.imageData!,
                                        messageId: message.id,
                                      ),
                                    ),
                                  if (message.audioData != null)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 16),
                                      child: ToolResultAudio(
                                        audioDataJson: message.audioData!,
                                        messageId: message.id,
                                      ),
                                    ),
                                ],
                              );
                            }
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

                        // Format MCP notification messages
                        if (message.role == MessageRole.mcpNotification) {
                          // Show minimal indicator when thinking is disabled
                          if (!_showThinking) {
                            return ThinkingIndicator(message: message);
                          }
                          // Full notification display is handled by MessageBubble
                          return MessageBubble(
                            message: message,
                            showThinking: _showThinking,
                            onDelete: () =>
                                _deleteMessage(message.id, provider),
                            onEdit:
                                null, // Notification messages can't be edited
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
                          onRegenerate: message.id == lastAssistantContentMessageId
                              ? () => _regenerateLastResponse(provider)
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
                        child:
                            _currentProgress != null &&
                                _currentProgress!.percentage != null
                            ? CircularProgressIndicator(
                                strokeWidth: 2,
                                value: _currentProgress!.percentage! / 100,
                              )
                            : CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _getLoadingStatusText(),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                          overflow: TextOverflow.ellipsis,
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

  /// Get the status text for the loading indicator
  String _getLoadingStatusText() {
    if (_currentToolName != null) {
      final toolText = _isToolExecuting
          ? 'Calling tool $_currentToolName'
          : 'Called tool $_currentToolName';

      // Add progress info if available
      if (_currentProgress != null) {
        final progress = _currentProgress!;
        if (progress.message != null) {
          return '$toolText - ${progress.message}';
        } else if (progress.percentage != null) {
          return '$toolText - ${progress.percentage!.toStringAsFixed(0)}%';
        } else {
          return '$toolText - ${progress.progress}${progress.total != null ? '/${progress.total}' : ''}';
        }
      }

      return _isToolExecuting ? '$toolText...' : toolText;
    }
    return 'Thinking...';
  }

  Widget _buildCommandPalette() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_mcpServers.isNotEmpty)
            ActionChip(
              avatar: Icon(
                Icons.auto_awesome,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              label: const Text('Prompts'),
              onPressed: _openMcpPromptsScreen,
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
          ActionChip(
            avatar: Icon(
              Icons.dns,
              size: 18,
              color: _mcpServers.isNotEmpty
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: Text(
              _mcpServers.isNotEmpty
                  ? 'MCP Servers (${_mcpServers.length})'
                  : 'MCP Servers',
            ),
            onPressed: _showMcpServerSelector,
            side: BorderSide(
              color: _mcpServers.isNotEmpty
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          if (_mcpServers.isNotEmpty)
            ActionChip(
              avatar: Icon(
                Icons.bug_report_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              label: const Text('Debug'),
              onPressed: _openMcpDebugScreen,
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showMcpServerSelector() async {
    final currentServerIds = _mcpServers.map((s) => s.id).toList();

    final selectedServerIds = await showDialog<List<String>>(
      context: context,
      builder: (context) =>
          McpServerSelectionDialog(initialSelectedServerIds: currentServerIds),
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
      final client = _mcpClients.remove(id);
      _mcpTools.remove(id);
      _oauthProviders.remove(id);
      _serverOAuthStatus.remove(id);
      _serversNeedingOAuth.removeWhere((s) => s.id == id);
      await client?.close();
      // Clear stored session ID
      await DatabaseService.instance.updateMcpSessionId(
        widget.conversation.id,
        id,
        null,
      );
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

    setState(() {
      _mcpServers = newMcpServers;
    });

    // Initialize newly added servers
    for (final id in addedIds) {
      final server = newMcpServers.firstWhere((s) => s.id == id);
      await _initializeMcpServer(server);
    }

    // Update ChatService with the new server names
    if (_chatService != null) {
      final serverNames = <String, String>{};
      for (final server in _mcpServers) {
        serverNames[server.id] = server.name;
      }
      _chatService!.updateServers(
        mcpClients: _mcpClients,
        mcpTools: _mcpTools,
        serverNames: serverNames,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('MCP servers updated (${_mcpServers.length} active)'),
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
            McpPromptsScreen(servers: _mcpServers, clients: _mcpClients),
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
          servers: _mcpServers,
          clients: _mcpClients,
          tools: _mcpTools,
        ),
      ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pending image thumbnails
            if (_pendingImages.isNotEmpty)
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pendingImages.length,
                  itemBuilder: (context, index) {
                    final img = _pendingImages[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0, bottom: 4.0),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              img.bytes,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _pendingImages.removeAt(index);
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(2),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Row(
              children: [
                // Attachment button — popup on mobile, simple button on desktop
                if (!kIsWeb && (Platform.isIOS || Platform.isAndroid))
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.add_photo_alternate_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    tooltip: 'Attach image',
                    onSelected: (value) {
                      switch (value) {
                        case 'gallery':
                          _pickImageFromGallery();
                          break;
                        case 'camera':
                          _pickImageFromCamera();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'gallery',
                        child: ListTile(
                          leading: Icon(Icons.photo_library_outlined),
                          title: Text('Photo Library'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'camera',
                        child: ListTile(
                          leading: Icon(Icons.camera_alt_outlined),
                          title: Text('Camera'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  )
                else
                  IconButton(
                    icon: Icon(
                      Icons.add_photo_alternate_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    tooltip: 'Attach image',
                    onPressed: _pickImageFromGallery,
                  ),
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
                    textInputAction: TextInputAction.newline,
                    contentInsertionConfiguration:
                        ContentInsertionConfiguration(
                          onContentInserted: _onContentInserted,
                          allowedMimeTypes: const [
                            'image/png',
                            'image/jpeg',
                            'image/gif',
                            'image/webp',
                            'image/bmp',
                          ],
                        ),
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
          ],
        ),
      ),
    );
  }

  /// Pick images from the device gallery (supports multi-select)
  Future<void> _pickImageFromGallery() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      for (final image in images) {
        await _addImageFile(image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Take a photo from the device camera
  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (image != null) {
        await _addImageFile(image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Handle content inserted via the soft keyboard (Android image paste/insert)
  void _onContentInserted(KeyboardInsertedContent content) async {
    if (content.hasData) {
      final bytes = content.data;
      if (bytes != null && bytes.isNotEmpty) {
        final mimeType = content.mimeType;
        setState(() {
          _pendingImages.add(_PendingImage(bytes: bytes, mimeType: mimeType));
        });
        _showModelImageWarningIfNeeded();
      }
    } else {
      // Some keyboards provide a URI instead of raw data
      try {
        final file = XFile(content.uri);
        await _addImageFile(file);
      } catch (e) {
        debugPrint('Failed to load inserted content from URI: $e');
      }
    }
  }

  /// Add an XFile image to the pending list
  Future<void> _addImageFile(XFile file) async {
    final bytes = await file.readAsBytes();
    final mimeType = _mimeTypeFromPath(file.path);
    setState(() {
      _pendingImages.add(
        _PendingImage(bytes: Uint8List.fromList(bytes), mimeType: mimeType),
      );
    });
    _showModelImageWarningIfNeeded();
  }

  /// Determine MIME type from file extension
  String _mimeTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'image/png'; // Default
  }

  /// Show a warning if the current model doesn't support image input
  void _showModelImageWarningIfNeeded() {
    final supportsImages =
        _modelDetails != null &&
        _modelDetails!['architecture'] != null &&
        (_modelDetails!['architecture']['input_modalities'] as List?)?.contains(
              'image',
            ) ==
            true;

    if (!supportsImages && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Warning: ${_getCurrentModel()} may not support image input',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
        model: _getCurrentModel(),
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
      model: _getCurrentModel(),
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

  /// Get the current model from the provider (live data)
  String _getCurrentModel() {
    final provider = context.read<ConversationProvider>();
    final conversation = provider.conversations.firstWhere(
      (c) => c.id == widget.conversation.id,
      orElse: () => widget.conversation,
    );
    return conversation.model;
  }

  /// Open the model picker and switch the conversation's model
  Future<void> _changeModel() async {
    final currentModel = _getCurrentModel();
    final selectedModel = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => ModelPickerScreen(
          defaultModel: currentModel,
          showDefaultToggle: false,
        ),
      ),
    );

    if (selectedModel == null || selectedModel == currentModel || !mounted) {
      return;
    }

    final provider = context.read<ConversationProvider>();

    // Update the conversation model in the database
    await provider.updateConversationModel(
      widget.conversation.id,
      selectedModel,
    );

    // Add a visual indicator for the model change
    final modelChangeMessage = Message(
      id: const Uuid().v4(),
      conversationId: widget.conversation.id,
      role: MessageRole.modelChange,
      content: 'Model changed from $currentModel to $selectedModel',
      timestamp: DateTime.now(),
    );
    await provider.addMessage(modelChangeMessage);

    // Refresh model details for the new model
    _loadModelDetails();
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

/// Holds a pending image attachment before it is sent
class _PendingImage {
  final Uint8List bytes;
  final String mimeType;

  _PendingImage({required this.bytes, required this.mimeType});
}
