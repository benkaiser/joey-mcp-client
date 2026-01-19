import 'dart:convert';
import 'package:dio/dio.dart';

/// MCP Tool definition
class McpTool {
  final String name;
  final String? description;
  final Map<String, dynamic> inputSchema;

  McpTool({required this.name, this.description, required this.inputSchema});

  factory McpTool.fromJson(Map<String, dynamic> json) {
    return McpTool(
      name: json['name'],
      description: json['description'],
      inputSchema: json['inputSchema'] ?? {},
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

/// MCP Tool call result
class McpToolResult {
  final List<McpContent> content;
  final bool? isError;

  McpToolResult({required this.content, this.isError});

  factory McpToolResult.fromJson(Map<String, dynamic> json) {
    return McpToolResult(
      content: (json['content'] as List)
          .map((c) => McpContent.fromJson(c))
          .toList(),
      isError: json['isError'],
    );
  }
}

/// MCP Content
class McpContent {
  final String type;
  final String? text;
  final dynamic data; // For other content types

  McpContent({required this.type, this.text, this.data});

  factory McpContent.fromJson(Map<String, dynamic> json) {
    return McpContent(
      type: json['type'],
      text: json['text'],
      data: json['data'],
    );
  }
}

/// MCP Client for Streamable HTTP transport
class McpClientService {
  final Dio _dio;
  final String serverUrl;
  final Map<String, String>? headers;
  String? _protocolVersion;
  String? _sessionId;

  /// Callback for handling sampling requests from the server
  Future<Map<String, dynamic>> Function(Map<String, dynamic> request)?
  onSamplingRequest;

  McpClientService({required this.serverUrl, this.headers})
    : _dio = Dio(
        BaseOptions(
          headers: headers?.map(
            (key, value) => MapEntry(key, value as dynamic),
          ),
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

  /// Initialize connection to the MCP server
  Future<void> initialize() async {
    try {
      final response = await _dio.post(
        serverUrl,
        data: {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2024-11-05',
            'capabilities': {'tools': {}, 'sampling': {}},
            'clientInfo': {
              'name': 'joey-mcp-client-flutter',
              'version': '1.0.0',
            },
          },
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
          },
        ),
      );

      print('MCP initialize response: ${response.data}');

      // Parse SSE response
      final data = _parseSSEResponse(response.data);

      if (data['error'] != null) {
        throw Exception('MCP initialization error: ${data['error']}');
      }

      // Store the negotiated protocol version
      _protocolVersion = data['result']?['protocolVersion'];

      // Extract session ID from response headers if present
      _sessionId = response.headers.value('mcp-session-id');

      print(
        'MCP initialize parsed successfully: ${data['result']?['serverInfo']?['name']}',
      );
      print('MCP protocol version: $_protocolVersion');
      print('MCP session ID: $_sessionId');

      // Send initialized notification (required by MCP protocol)
      // Must include MCP-Protocol-Version and MCP-Session-Id headers for HTTP transport
      try {
        final notificationResponse = await _dio.post(
          serverUrl,
          data: {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
          options: Options(headers: _buildRequestHeaders()),
        );
        print('MCP initialized notification sent successfully');
        print(
          'MCP initialized notification response: ${notificationResponse.data}',
        );
      } catch (notificationError) {
        if (notificationError is DioException &&
            notificationError.response != null) {
          print(
            'MCP initialized notification error response: ${notificationError.response?.data}',
          );
          print(
            'MCP initialized notification error status: ${notificationError.response?.statusCode}',
          );
        }
        throw Exception(
          'Failed to send initialized notification: $notificationError',
        );
      }
    } catch (e) {
      if (e is DioException && e.response != null) {
        print('MCP initialize error response body: ${e.response?.data}');
      }
      print('MCP initialize exception: $e');
      throw Exception('Failed to initialize MCP server: $e');
    }
  }

  /// Build headers for subsequent requests (after initialization)
  Map<String, dynamic> _buildRequestHeaders() {
    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
    };

    if (_protocolVersion != null) {
      headers['MCP-Protocol-Version'] = _protocolVersion!;
    }

    if (_sessionId != null) {
      headers['MCP-Session-Id'] = _sessionId!;
    }

    return headers;
  }

  /// Parse Server-Sent Events (SSE) response format
  Map<String, dynamic> _parseSSEResponse(dynamic responseData) {
    if (responseData is Map) {
      return responseData as Map<String, dynamic>;
    }

    // Parse SSE format: extract JSON from "data: {json}" line
    final String text = responseData.toString();
    final lines = text.split('\n');

    for (final line in lines) {
      if (line.startsWith('data: ')) {
        final jsonStr = line.substring(6); // Remove "data: " prefix
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      }
    }

    throw Exception('Could not parse SSE response: $text');
  }

  /// List available tools from the MCP server
  Future<List<McpTool>> listTools() async {
    try {
      final response = await _dio.post(
        serverUrl,
        data: {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list', 'params': {}},
        options: Options(headers: _buildRequestHeaders()),
      );

      final data = _parseSSEResponse(response.data);

      if (data['error'] != null) {
        throw Exception('MCP tools/list error: ${data['error']}');
      }

      final tools = data['result']['tools'] as List;
      return tools.map((t) => McpTool.fromJson(t)).toList();
    } catch (e) {
      if (e is DioException && e.response != null) {
        print('MCP listTools error response body: ${e.response?.data}');
      }
      throw Exception('Failed to list tools: $e');
    }
  }

  /// Call a tool on the MCP server
  Future<McpToolResult> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    try {
      final response = await _dio.post(
        serverUrl,
        data: {
          'jsonrpc': '2.0',
          'id': DateTime.now().millisecondsSinceEpoch,
          'method': 'tools/call',
          'params': {'name': toolName, 'arguments': arguments},
        },
        options: Options(headers: _buildRequestHeaders()),
      );

      final data = _parseSSEResponse(response.data);

      if (data['error'] != null) {
        throw Exception('MCP tools/call error: ${data['error']}');
      }

      return McpToolResult.fromJson(data['result']);
    } catch (e) {
      if (e is DioException && e.response != null) {
        print('MCP callTool error response body: ${e.response?.data}');
      }
      throw Exception('Failed to call tool $toolName: $e');
    }
  }

  /// Handle incoming sampling request from server
  Future<Map<String, dynamic>> handleSamplingRequest(
    Map<String, dynamic> request,
  ) async {
    if (onSamplingRequest == null) {
      throw Exception('No sampling request handler registered');
    }

    return await onSamplingRequest!(request);
  }

  /// Close the connection (for cleanup)
  void close() {
    _dio.close();
  }
}
