/// Cached UI resource fetched from an MCP server
class McpAppUiResource {
  final String resourceUri;
  final String html;
  final Map<String, dynamic>? cspMeta; // _meta.ui.csp from the resource content
  final Map<String, dynamic>? uiMeta;  // Full _meta.ui from the resource content
  final bool prefersBorder;

  McpAppUiResource({
    required this.resourceUri,
    required this.html,
    this.cspMeta,
    this.uiMeta,
    this.prefersBorder = true,
  });

  Map<String, dynamic> toJson() => {
    'resourceUri': resourceUri,
    'html': html,
    if (cspMeta != null) 'cspMeta': cspMeta,
    if (uiMeta != null) 'uiMeta': uiMeta,
    'prefersBorder': prefersBorder,
  };

  factory McpAppUiResource.fromJson(Map<String, dynamic> json) => McpAppUiResource(
    resourceUri: json['resourceUri'] as String,
    html: json['html'] as String,
    cspMeta: json['cspMeta'] as Map<String, dynamic>?,
    uiMeta: json['uiMeta'] as Map<String, dynamic>?,
    prefersBorder: json['prefersBorder'] as bool? ?? true,
  );
}

/// UI data attached to a message for rendering in WebView
class McpAppUiData {
  final String resourceUri;
  final String html;
  final Map<String, dynamic>? cspMeta;
  final Map<String, dynamic>? toolArgs;
  final String? toolResultJson;   // Serialized tool result for ui/notifications/tool-result
  final String serverId;
  final String? displayMode;      // e.g., 'inline', 'fullscreen'

  McpAppUiData({
    required this.resourceUri,
    required this.html,
    this.cspMeta,
    this.toolArgs,
    this.toolResultJson,
    required this.serverId,
    this.displayMode,
  });

  Map<String, dynamic> toJson() => {
    'resourceUri': resourceUri,
    'html': html,
    if (cspMeta != null) 'cspMeta': cspMeta,
    if (toolArgs != null) 'toolArgs': toolArgs,
    if (toolResultJson != null) 'toolResultJson': toolResultJson,
    'serverId': serverId,
    if (displayMode != null) 'displayMode': displayMode,
  };

  factory McpAppUiData.fromJson(Map<String, dynamic> json) => McpAppUiData(
    resourceUri: json['resourceUri'] as String,
    html: json['html'] as String,
    cspMeta: json['cspMeta'] as Map<String, dynamic>?,
    toolArgs: json['toolArgs'] as Map<String, dynamic>?,
    toolResultJson: json['toolResultJson'] as String?,
    serverId: json['serverId'] as String,
    displayMode: json['displayMode'] as String?,
  );
}
