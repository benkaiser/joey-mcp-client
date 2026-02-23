import 'package:mcp_dart/mcp_dart.dart';

/// Exception thrown when an MCP server requires OAuth authentication
class McpAuthRequiredException implements Exception {
  final String serverUrl;
  final String message;

  McpAuthRequiredException(
    this.serverUrl, [
    this.message = 'OAuth authentication required',
  ]);

  @override
  String toString() =>
      'McpAuthRequiredException: $message (server: $serverUrl)';
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
  final Map<String, dynamic>? meta;
  final Map<String, dynamic>? annotations;

  McpTool({required this.name, this.description, required this.inputSchema, this.meta, this.annotations});

  factory McpTool.fromMcpDartTool(Tool tool) {
    return McpTool(
      name: tool.name,
      description: tool.description,
      inputSchema: tool.inputSchema.toJson(),
      meta: tool.meta,
      annotations: tool.annotations?.toJson(),
    );
  }

  /// Returns the UI resource URI from meta, supporting both nested and deprecated flat formats
  String? get uiResourceUri =>
      meta?['ui']?['resourceUri'] as String? ?? meta?['ui/resourceUri'] as String?;

  /// Whether this tool has an associated UI resource
  bool get hasUi => uiResourceUri != null;

  /// List of visibility targets like ["app"] or ["app", "llm"]
  List<String>? get uiVisibility =>
      (meta?['ui']?['visibility'] as List?)?.cast<String>();

  /// Whether this tool is only visible in the app UI (not sent to LLM)
  bool get isAppOnly {
    final vis = uiVisibility;
    if (vis != null && vis.length == 1 && vis.first == 'app') return true;
    final audience = annotations?['audience'];
    if (audience is List && audience.length == 1 && audience.first == 'app') return true;
    return false;
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
  final Map<String, dynamic>? meta;
  final Map<String, dynamic>? structuredContent;

  McpToolResult({required this.content, this.isError, this.meta, this.structuredContent});

  factory McpToolResult.fromMcpDartResult(CallToolResult result) {
    return McpToolResult(
      content: result.content
          .map((c) => McpContent.fromMcpDartContent(c))
          .toList(),
      isError: result.isError,
      meta: result.meta,
      structuredContent: result.structuredContent,
    );
  }
}

/// Wrapper around mcp_dart Content for backward compatibility
class McpContent {
  final String type;
  final String? text;
  final dynamic data;
  final String? mimeType;

  McpContent({required this.type, this.text, this.data, this.mimeType});

  factory McpContent.fromMcpDartContent(Content content) {
    if (content is TextContent) {
      return McpContent(type: 'text', text: content.text);
    } else if (content is ImageContent) {
      return McpContent(
        type: 'image',
        data: content.data,
        mimeType: content.mimeType,
      );
    } else if (content is AudioContent) {
      return McpContent(
        type: 'audio',
        data: content.data,
        mimeType: content.mimeType,
      );
    } else if (content is EmbeddedResource) {
      return McpContent(type: 'resource', data: content.resource);
    }
    return McpContent(type: 'unknown');
  }
}
