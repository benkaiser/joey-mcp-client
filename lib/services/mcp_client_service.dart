import 'dart:async';
import 'package:mcp_dart/mcp_dart.dart';
import '../models/elicitation.dart' as app_elicitation;
import 'mcp_oauth_service.dart';

/// Exception thrown when an MCP server requires OAuth authentication
class McpAuthRequiredException implements Exception {
  final String serverUrl;
  final String message;

  McpAuthRequiredException(this.serverUrl, [this.message = 'OAuth authentication required']);

  @override
  String toString() => 'McpAuthRequiredException: $message (server: $serverUrl)';
}

/// Represents a progress notification from an MCP server
class McpProgressNotification {
  final dynamic progressToken;
  final num progress;
  final num? total;
  final String? message;
  final String serverId;

  McpProgressNotification({
    required this.progressToken,
    required this.progress,
    this.total,
    this.message,
    required this.serverId,
  });

  /// Returns progress as a percentage (0-100) if total is known
  double? get percentage => total != null ? (progress / total!) * 100 : null;
}

/// Wrapper around mcp_dart Tool for backward compatibility
class McpTool {
  final String name;
  final String? description;
  final Map<String, dynamic> inputSchema;

  McpTool({required this.name, this.description, required this.inputSchema});

  factory McpTool.fromMcpDartTool(Tool tool) {
    return McpTool(
      name: tool.name,
      description: tool.description,
      inputSchema: tool.inputSchema.toJson(),
    );
  }

  /// Convert to OpenAI's tool format (required by OpenRouter)
  Map<String, dynamic> toJson() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description ?? '',
        'parameters': inputSchema,
      },
    };
  }
}

/// Wrapper around mcp_dart CallToolResult for backward compatibility
class McpToolResult {
  final List<McpContent> content;
  final bool? isError;

  McpToolResult({required this.content, this.isError});

  factory McpToolResult.fromMcpDartResult(CallToolResult result) {
    return McpToolResult(
      content: result.content
          .map((c) => McpContent.fromMcpDartContent(c))
          .toList(),
      isError: result.isError,
    );
  }
}

/// Wrapper around mcp_dart Content for backward compatibility
class McpContent {
  final String type;
  final String? text;
  final dynamic data;

  McpContent({required this.type, this.text, this.data});

  factory McpContent.fromMcpDartContent(Content content) {
    if (content is TextContent) {
      return McpContent(type: 'text', text: content.text);
    } else if (content is ImageContent) {
      return McpContent(type: 'image', data: content.data);
    } else if (content is EmbeddedResource) {
      return McpContent(type: 'resource', data: content.resource);
    }
    return McpContent(type: 'unknown');
  }
}

/// Helper class to manage timeout state for a single request
class _RequestTimeoutState {
  final int id;
  final BasicAbortController abortController;
  Timer? _timer;
  final void Function() _onTimeout;

  _RequestTimeoutState({
    required this.id,
    required this.abortController,
    required void Function() onTimeout,
  }) : _onTimeout = onTimeout;

  void startTimer(Duration duration) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      abortController.abort('Request timed out');
      _onTimeout();
    });
  }

  void extendTimeout(Duration duration) {
    startTimer(duration);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// MCP Client Service using the mcp_dart library
class McpClientService {
  final String serverUrl;
  final Map<String, String>? headers;
  final McpOAuthClientProvider? oauthProvider;

  McpClient? _client;
  StreamableHttpClientTransport? _transport;

  /// Get the current MCP session ID (assigned by the server after initialization)
  String? get sessionId => _transport?.sessionId;

  /// Track active tool requests for timeout management
  final Map<int, _RequestTimeoutState> _activeRequests = {};
  int _nextRequestId = 0;

  /// Track whether a sampling request is currently active
  bool _isSamplingActive = false;

  /// Track whether an elicitation request is currently active
  bool _isElicitationActive = false;

  /// Extended timeout duration for when sampling/elicitation is active (5 minutes)
  static const Duration _extendedTimeout = Duration(minutes: 5);

  /// Normal timeout duration (60 seconds - matches mcp_dart default)
  static const Duration _normalTimeout = Duration(seconds: 60);

  /// Callback for handling sampling requests from the server
  Future<Map<String, dynamic>> Function(Map<String, dynamic> request)?
  onSamplingRequest;

  /// Callback for handling elicitation requests from the server
  Future<void> Function(
    app_elicitation.ElicitationRequest request,
    Future<void> Function(
      String elicitationId,
      app_elicitation.ElicitationAction action,
      Map<String, dynamic>? content,
    )
    sendComplete,
  )?
  onElicitationRequest;

  /// Callback for handling progress notifications from the server
  void Function(McpProgressNotification notification)? onProgressNotification;

  /// Callback for handling generic notifications from the server
  /// (method, params, serverId)
  void Function(String method, Map<String, dynamic>? params, String serverId)?
  onGenericNotification;

  /// Callback for handling tools list changed notifications
  void Function()? onToolsListChanged;

  /// Callback for handling resources list changed notifications
  void Function()? onResourcesListChanged;

  /// Callback for handling OAuth authentication required
  void Function(String serverUrl)? onAuthRequired;

  /// Completer for pending elicitation responses
  Completer<ElicitResult>? _pendingElicitationCompleter;

  /// Server ID for identifying this connection in notifications
  String? _serverId;

  McpClientService({
    required this.serverUrl,
    this.headers,
    this.oauthProvider,
  });

  /// Set the server ID for identifying this connection in notifications
  void setServerId(String serverId) {
    _serverId = serverId;
  }

  /// Initialize connection to the MCP server
  /// If [sessionId] is provided, attempts to resume a previous session.
  Future<void> initialize({String? sessionId}) async {
    try {
      // Build request init options with headers if provided
      Map<String, dynamic>? requestInit;
      if (headers != null && headers!.isNotEmpty) {
        requestInit = {'headers': headers};
      }

      // Create the HTTP transport with headers and OAuth provider
      final uri = Uri.parse(serverUrl);
      _transport = StreamableHttpClientTransport(
        uri,
        opts: StreamableHttpClientTransportOptions(
          requestInit: requestInit,
          authProvider: oauthProvider,
          sessionId: sessionId,
        ),
      );

      // Create the MCP client with our app info
      _client = McpClient(
        Implementation(name: 'joey-mcp-client-flutter', version: '1.0.0'),
        options: McpClientOptions(
          capabilities: ClientCapabilities(
            sampling: ClientCapabilitiesSampling(),
            roots: ClientCapabilitiesRoots(listChanged: true),
            elicitation: ClientElicitation(
              form: ClientElicitationForm(applyDefaults: true),
              url: ClientElicitationUrl(),
            ),
          ),
        ),
      );

      // Set up the sampling handler before connecting
      _client!.onSamplingRequest = _handleSamplingRequest;

      // Set up the elicitation handler before connecting
      _client!.onElicitRequest = _handleElicitRequest;

      // Connect to the server
      await _client!.connect(_transport!);

      // Set up notification handlers after connecting
      _setupNotificationHandlers();

      final serverVersion = _client!.getServerVersion();
      print(
        'MCP: Connected to server at $serverUrl${sessionId != null ? ' (resumed session)' : ''}',
      );
      print(
        'MCP: Server info: ${serverVersion?.name} v${serverVersion?.version}',
      );
      if (this.sessionId != null) {
        print('MCP: Session ID: ${this.sessionId}');
      }
    } on StreamableHttpError catch (e) {
      // Handle 404: session expired, retry without session ID
      if (e.code == 404 && sessionId != null) {
        print('MCP: Session expired (404), retrying with fresh session...');
        await _client?.close();
        await _transport?.close();
        _client = null;
        _transport = null;
        // Retry initialization without session ID
        return initialize();
      }
      print('MCP: HTTP error during initialization: ${e.code} ${e.message}');
      throw Exception('Failed to initialize MCP server: $e');
    } on UnauthorizedError catch (e) {
      print('MCP: Authorization required for $serverUrl: $e');
      // Signal that OAuth is needed
      onAuthRequired?.call(serverUrl);
      throw McpAuthRequiredException(serverUrl, e.message ?? 'OAuth authentication required');
    } catch (e) {
      print('MCP: Failed to initialize: $e');
      // Check if this is an auth-related error
      if (e.toString().contains('401') ||
          e.toString().toLowerCase().contains('unauthorized')) {
        onAuthRequired?.call(serverUrl);
        throw McpAuthRequiredException(serverUrl, 'OAuth authentication required');
      }
      throw Exception('Failed to initialize MCP server: $e');
    }
  }

  /// Set up notification handlers for the MCP client
  void _setupNotificationHandlers() {
    if (_client == null) return;

    // Handle tools list changed notifications
    _client!.setNotificationHandler<JsonRpcToolListChangedNotification>(
      Method.notificationsToolsListChanged,
      (notification) async {
        print('MCP: Tools list changed');
        onToolsListChanged?.call();
      },
      (params, meta) => JsonRpcToolListChangedNotification.fromJson({
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    // Handle resources list changed notifications
    _client!.setNotificationHandler<JsonRpcResourceListChangedNotification>(
      Method.notificationsResourcesListChanged,
      (notification) async {
        print('MCP: Resources list changed');
        onResourcesListChanged?.call();
      },
      (params, meta) => JsonRpcResourceListChangedNotification.fromJson({
        'params': params,
        if (meta != null) '_meta': meta,
      }),
    );

    // Use fallback notification handler to catch any other notifications
    // (including progress if it comes through a different channel)
    _client!.fallbackNotificationHandler = (notification) async {
      print('MCP: Received notification: ${notification.method}');

      // Handle progress notifications
      if (notification.method == Method.notificationsProgress) {
        final params = notification.params;
        if (params != null) {
          final progressNotification = McpProgressNotification(
            progressToken: params['progressToken'],
            progress: params['progress'] as num,
            total: params['total'] as num?,
            message: params['message'] as String?,
            serverId: _serverId ?? serverUrl,
          );
          print(
            'MCP: Progress notification: ${progressNotification.progress}/${progressNotification.total ?? '?'}',
          );
          onProgressNotification?.call(progressNotification);
        }
        return;
      }

      // For all other notifications, forward to generic handler
      // This includes any custom/unknown notification methods
      onGenericNotification?.call(
        notification.method,
        notification.params,
        _serverId ?? serverUrl,
      );
    };
  }

  /// Handle sampling request from the server
  Future<CreateMessageResult> _handleSamplingRequest(
    CreateMessageRequest request,
  ) async {
    if (onSamplingRequest == null) {
      throw McpError(
        ErrorCode.internalError.value,
        'No sampling request handler registered',
      );
    }

    // Mark sampling as active and extend all active request timeouts
    _isSamplingActive = true;
    _extendAllActiveTimeouts();

    // Convert to the format expected by our callback
    final requestMap = {
      'method': 'sampling/createMessage',
      'params': {
        'messages': request.messages
            .map(
              (m) => {'role': m.role.name, 'content': _contentToMap(m.content)},
            )
            .toList(),
        'systemPrompt': request.systemPrompt,
        'maxTokens': request.maxTokens,
        if (request.modelPreferences != null)
          'modelPreferences': {
            if (request.modelPreferences!.hints != null)
              'hints': request.modelPreferences!.hints!
                  .map((h) => {'name': h.name})
                  .toList(),
          },
      },
    };

    try {
      final response = await onSamplingRequest!(requestMap);

      // Convert response back to mcp_dart format
      final role = response['role'] as String;
      final content = response['content'];
      final model = response['model'] as String;
      final stopReason = response['stopReason'] as String?;

      Content responseContent;
      if (content is Map<String, dynamic>) {
        final type = content['type'] as String?;
        if (type == 'text') {
          responseContent = TextContent(text: content['text'] as String);
        } else {
          responseContent = TextContent(text: content.toString());
        }
      } else if (content is String) {
        responseContent = TextContent(text: content);
      } else if (content is List) {
        // Handle array of content blocks
        final textParts = content
            .whereType<Map<String, dynamic>>()
            .where((c) => c['type'] == 'text')
            .map((c) => c['text'] as String)
            .toList();
        responseContent = TextContent(text: textParts.join('\n'));
      } else {
        responseContent = TextContent(text: '');
      }

      return CreateMessageResult(
        role: role == 'assistant'
            ? SamplingMessageRole.assistant
            : SamplingMessageRole.user,
        content: SamplingTextContent(
          text: (responseContent as TextContent).text,
        ),
        model: model,
        stopReason: stopReason,
      );
    } catch (e) {
      throw McpError(
        ErrorCode.internalError.value,
        'Sampling request failed: $e',
      );
    } finally {
      // Mark sampling as complete
      _isSamplingActive = false;
    }
  }

  /// Convert Content to a map representation
  /// Handles both regular Content types and SamplingContent types
  Map<String, dynamic> _contentToMap(dynamic content) {
    // Handle SamplingContent types (used in sampling messages)
    if (content is SamplingTextContent) {
      return {'type': 'text', 'text': content.text};
    } else if (content is SamplingImageContent) {
      return {
        'type': 'image',
        'data': content.data,
        'mimeType': content.mimeType,
      };
    }
    // Handle regular Content types
    if (content is TextContent) {
      return {'type': 'text', 'text': content.text};
    } else if (content is ImageContent) {
      return {
        'type': 'image',
        'data': content.data,
        'mimeType': content.mimeType,
      };
    }
    return {'type': 'unknown'};
  }

  /// Handle elicitation request from the server
  Future<ElicitResult> _handleElicitRequest(ElicitRequest request) async {
    // Log the raw elicitation request for debugging
    print('MCP: Received elicitation request:');
    print('  mode: ${request.mode}');
    print('  isUrlMode: ${request.isUrlMode}');
    print('  isFormMode: ${request.isFormMode}');
    print('  message: ${request.message}');
    print('  url: ${request.url}');
    print('  elicitationId: ${request.elicitationId}');
    print('  requestedSchema: ${request.requestedSchema?.toJson()}');

    if (onElicitationRequest == null) {
      throw McpError(
        ErrorCode.internalError.value,
        'No elicitation request handler registered',
      );
    }

    // Mark elicitation as active and extend all active request timeouts
    _isElicitationActive = true;
    _extendAllActiveTimeouts();

    try {
      // Create a completer to wait for user response
      _pendingElicitationCompleter = Completer<ElicitResult>();

      // Convert to app's elicitation format
      final appRequest = app_elicitation.ElicitationRequest(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        mode: request.isUrlMode
            ? app_elicitation.ElicitationMode.url
            : app_elicitation.ElicitationMode.form,
        message: request.message,
        elicitationId: request.elicitationId,
        url: request.url,
        requestedSchema: request.requestedSchema?.toJson(),
      );

      // Call the handler with a callback to complete the elicitation
      await onElicitationRequest!(appRequest, (
        elicitationId,
        action,
        content,
      ) async {
        // Convert action to mcp_dart format
        String mcpAction;
        switch (action) {
          case app_elicitation.ElicitationAction.accept:
            mcpAction = 'accept';
            break;
          case app_elicitation.ElicitationAction.decline:
            mcpAction = 'decline';
            break;
          case app_elicitation.ElicitationAction.cancel:
            mcpAction = 'cancel';
            break;
        }

        _pendingElicitationCompleter?.complete(
          ElicitResult(
            action: mcpAction,
            content: content,
            elicitationId: elicitationId.isNotEmpty ? elicitationId : null,
          ),
        );
      });

      return await _pendingElicitationCompleter!.future;
    } finally {
      // Mark elicitation as complete
      _isElicitationActive = false;
    }
  }

  /// List available tools from the MCP server
  Future<List<McpTool>> listTools() async {
    if (_client == null) {
      throw Exception('MCP client not initialized');
    }

    try {
      final result = await _client!.listTools();
      return result.tools.map((t) => McpTool.fromMcpDartTool(t)).toList();
    } catch (e) {
      print('MCP: Failed to list tools: $e');
      throw Exception('Failed to list tools: $e');
    }
  }

  /// Call a tool on the MCP server
  Future<McpToolResult> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    if (_client == null) {
      throw Exception('MCP client not initialized');
    }

    // Create timeout state for this request
    final requestId = _nextRequestId++;
    final abortController = BasicAbortController();
    final timeoutState = _RequestTimeoutState(
      id: requestId,
      abortController: abortController,
      onTimeout: () {
        print('MCP: Tool $toolName timed out');
        _activeRequests.remove(requestId);
      },
    );

    // Register this request and start with normal timeout
    _activeRequests[requestId] = timeoutState;
    timeoutState.startTimer(_normalTimeout);

    try {
      print('MCP: Calling tool $toolName with arguments: $arguments');

      // Use a very long timeout in mcp_dart (we manage timeout ourselves)
      // Pass our abort signal so we can cancel if our timeout fires
      // Also set up progress callback to forward progress notifications
      final result = await _client!.callTool(
        CallToolRequest(name: toolName, arguments: arguments),
        options: RequestOptions(
          timeout: const Duration(hours: 1), // Let our timer handle it
          signal: abortController.signal,
          resetTimeoutOnProgress: true, // Let mcp_dart also reset on progress
          onprogress: (progress) {
            // Extend our custom timeout when we receive progress
            // This keeps the request alive during long-running operations
            timeoutState.extendTimeout(_extendedTimeout);

            // Forward progress notification to callback
            final progressNotification = McpProgressNotification(
              progressToken: requestId,
              progress: progress.progress,
              total: progress.total,
              message: progress.message,
              serverId: _serverId ?? serverUrl,
            );
            print(
              'MCP: Tool $toolName progress: ${progress.progress}/${progress.total ?? '?'}${progress.message != null ? ' - ${progress.message}' : ''}',
            );
            onProgressNotification?.call(progressNotification);
          },
        ),
      );

      print('MCP: Tool $toolName completed, isError: ${result.isError}');

      return McpToolResult.fromMcpDartResult(result);
    } on AbortError catch (e) {
      print('MCP: Tool $toolName aborted: ${e.reason}');
      return McpToolResult(
        content: [McpContent(type: 'text', text: 'Error: Request timed out')],
        isError: true,
      );
    } catch (e) {
      print('MCP: Failed to call tool $toolName: $e');

      // Check if this is an MCP error that we should handle specially
      if (e is McpError) {
        // Return error as a tool result
        return McpToolResult(
          content: [McpContent(type: 'text', text: 'Error: ${e.message}')],
          isError: true,
        );
      }

      throw Exception('Failed to call tool $toolName: $e');
    } finally {
      // Clean up timeout state
      timeoutState.cancel();
      _activeRequests.remove(requestId);
    }
  }

  /// Extend timeouts for all active requests (called when sampling/elicitation starts)
  void _extendAllActiveTimeouts() {
    print(
      'MCP: Extending timeouts for ${_activeRequests.length} active request(s)',
    );
    for (final state in _activeRequests.values) {
      state.extendTimeout(_extendedTimeout);
    }
  }

  /// Send elicitation complete notification to the server
  Future<void> sendElicitationComplete(
    String elicitationId,
    app_elicitation.ElicitationAction action,
    Map<String, dynamic>? content,
  ) async {
    // With mcp_dart, elicitation is handled through the request/response pattern
    // The response is sent automatically when the handler completes
    // This method is kept for backward compatibility but is a no-op
    print('MCP: Elicitation complete: $elicitationId, action: ${action.name}');
  }

  /// Check if an extended timeout operation (sampling/elicitation) is active
  bool get isExtendedTimeoutActive => _isSamplingActive || _isElicitationActive;

  /// Check if sampling is currently active
  bool get isSamplingActive => _isSamplingActive;

  /// Check if elicitation is currently active
  bool get isElicitationActive => _isElicitationActive;

  /// Close the connection
  Future<void> close() async {
    try {
      await _client?.close();
      await _transport?.close();
      print('MCP: Connection closed');
    } catch (e) {
      print('MCP: Error closing connection: $e');
    }
  }

  /// Complete OAuth flow after user authorization
  /// Call this after the user has authorized and you have the authorization code
  Future<void> finishAuth(String authorizationCode) async {
    if (_transport == null) {
      throw Exception('Transport not initialized');
    }
    await _transport!.finishAuth(authorizationCode);
  }

  /// Get the OAuth provider (for checking auth status)
  McpOAuthClientProvider? get authProvider => oauthProvider;
}
