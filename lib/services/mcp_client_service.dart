import 'dart:async';
import 'package:mcp_dart/mcp_dart.dart';
import '../models/elicitation.dart' as app_elicitation;

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
      inputSchema: tool.inputSchema?.toJson() ?? {},
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

/// MCP Client Service using the mcp_dart library
class McpClientService {
  final String serverUrl;
  final Map<String, String>? headers;

  McpClient? _client;
  StreamableHttpClientTransport? _transport;

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

  /// Completer for pending elicitation responses
  Completer<ElicitResult>? _pendingElicitationCompleter;

  McpClientService({required this.serverUrl, this.headers});

  /// Initialize connection to the MCP server
  Future<void> initialize() async {
    try {
      // Build request init options with headers if provided
      Map<String, dynamic>? requestInit;
      if (headers != null && headers!.isNotEmpty) {
        requestInit = {'headers': headers};
      }

      // Create the HTTP transport with headers
      final uri = Uri.parse(serverUrl);
      _transport = StreamableHttpClientTransport(
        uri,
        opts: StreamableHttpClientTransportOptions(requestInit: requestInit),
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

      final serverVersion = _client!.getServerVersion();
      print('MCP: Connected to server at $serverUrl');
      print(
        'MCP: Server info: ${serverVersion?.name} v${serverVersion?.version}',
      );
    } catch (e) {
      print('MCP: Failed to initialize: $e');
      throw Exception('Failed to initialize MCP server: $e');
    }
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

    // Mark sampling as active for extended timeouts
    _isSamplingActive = true;

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

    // Mark elicitation as active for extended timeouts
    _isElicitationActive = true;

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

    try {
      print('MCP: Calling tool $toolName with arguments: $arguments');

      // Always use extended timeout for tool calls since they may trigger
      // elicitation or sampling requests during execution, which require
      // user interaction and can take significant time
      final result = await _client!.callTool(
        CallToolRequest(name: toolName, arguments: arguments),
        options: RequestOptions(timeout: _extendedTimeout),
      );

      print('MCP: Tool $toolName completed, isError: ${result.isError}');

      return McpToolResult.fromMcpDartResult(result);
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
}
