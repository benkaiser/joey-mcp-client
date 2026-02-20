import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/mcp_server.dart';
import '../services/mcp_client_service.dart';
import '../services/mcp_server_manager.dart';
import '../services/mcp_oauth_manager.dart';

/// Screen showing detailed debug information about connected MCP servers
/// and their tools with expandable parameter details.
///
/// Directly references the live [McpServerManager] and [McpOAuthManager]
/// so it always reflects the current state — including changes triggered
/// externally (e.g. OAuth deep-link callbacks).
class McpDebugScreen extends StatefulWidget {
  final McpServerManager serverManager;
  final McpOAuthManager oauthManager;
  final String conversationId;

  const McpDebugScreen({
    super.key,
    required this.serverManager,
    required this.oauthManager,
    required this.conversationId,
  });

  @override
  State<McpDebugScreen> createState() => _McpDebugScreenState();
}

class _McpDebugScreenState extends State<McpDebugScreen> {
  final Map<String, String> _serverActionInProgress = {};

  McpServerManager get _sm => widget.serverManager;
  McpOAuthManager get _om => widget.oauthManager;

  @override
  void initState() {
    super.initState();
    _sm.addListener(_rebuild);
    _om.addListener(_rebuild);
  }

  @override
  void dispose() {
    _sm.removeListener(_rebuild);
    _om.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // --------------- Actions ---------------

  Future<void> _runAction(
    McpServer server,
    String actionType,
    Future<void> Function() action,
  ) async {
    setState(() => _serverActionInProgress[server.id] = actionType);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _serverActionInProgress.remove(server.id));
      }
    }
  }

  Future<void> _connectServer(McpServer server) =>
      _runAction(server, 'connecting', () async {
        await _sm.initializeMcpServer(server);
      });

  Future<void> _disconnectServer(McpServer server) =>
      _runAction(server, 'disconnecting', () async {
        await _sm.disconnectServer(server.id, widget.conversationId);
      });

  Future<void> _oauthLogout(McpServer server) =>
      _runAction(server, 'logging_out', () async {
        // Disconnect if connected
        await _sm.disconnectServer(server.id, widget.conversationId);

        // Clear OAuth tokens and status
        await _om.oauthLogout(server);

        // Update in-memory server
        final updatedServer = server.copyWith(
          oauthStatus: McpOAuthStatus.none,
          clearOAuthTokens: true,
          updatedAt: DateTime.now(),
        );
        _sm.updateServer(updatedServer);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logged out of ${server.name}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      });

  Future<void> _oauthLogin(McpServer server) =>
      _runAction(server, 'oauth_login', () async {
        if (!_om.serversNeedingOAuth.any((s) => s.id == server.id)) {
          _om.handleServerNeedsOAuth(server, _sm.mcpServers);
        }
        await _om.startServerOAuth(server, mcpServers: _sm.mcpServers);
      });

  // --------------- Build ---------------

  @override
  Widget build(BuildContext context) {
    final servers = _sm.mcpServers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP Debug'),
      ),
      body: servers.isEmpty
          ? Center(
              child: Text(
                'No MCP servers configured',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: servers.length,
              itemBuilder: (context, index) {
                final server = servers[index];
                final actionInProgress = _serverActionInProgress[server.id];
                return _ServerSection(
                  server: server,
                  isConnected: _sm.mcpClients.containsKey(server.id),
                  sessionId: _sm.mcpClients[server.id]?.sessionId,
                  tools: _sm.mcpTools[server.id] ?? [],
                  actionInProgress: actionInProgress,
                  onConnect: () => _connectServer(server),
                  onDisconnect: () => _disconnectServer(server),
                  onOAuthLogout: () => _oauthLogout(server),
                  onOAuthLogin: () => _oauthLogin(server),
                );
              },
            ),
    );
  }
}

class _ServerSection extends StatefulWidget {
  final McpServer server;
  final bool isConnected;
  final String? sessionId;
  final List<McpTool> tools;
  /// null = no action, "connecting" / "disconnecting" / "logging_out" / "oauth_login"
  final String? actionInProgress;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onOAuthLogout;
  final VoidCallback onOAuthLogin;

  const _ServerSection({
    required this.server,
    required this.isConnected,
    required this.sessionId,
    required this.tools,
    required this.actionInProgress,
    required this.onConnect,
    required this.onDisconnect,
    required this.onOAuthLogout,
    required this.onOAuthLogin,
  });

  @override
  State<_ServerSection> createState() => _ServerSectionState();
}

class _ServerSectionState extends State<_ServerSection> {
  bool _toolsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActionRunning = widget.actionInProgress != null;

    // Determine the display status
    String statusText;
    Color statusColor;
    IconData headerIcon;
    Color headerIconColor;

    if (widget.actionInProgress == 'connecting') {
      statusText = 'Connecting...';
      statusColor = Colors.orange;
      headerIcon = Icons.hourglass_top;
      headerIconColor = Colors.orange;
    } else if (widget.actionInProgress == 'disconnecting') {
      statusText = 'Disconnecting...';
      statusColor = Colors.orange;
      headerIcon = Icons.hourglass_top;
      headerIconColor = Colors.orange;
    } else if (widget.actionInProgress == 'logging_out') {
      statusText = 'Logging out...';
      statusColor = Colors.orange;
      headerIcon = Icons.hourglass_top;
      headerIconColor = Colors.orange;
    } else if (widget.actionInProgress == 'oauth_login') {
      statusText = 'Signing in...';
      statusColor = Colors.orange;
      headerIcon = Icons.hourglass_top;
      headerIconColor = Colors.orange;
    } else if (widget.isConnected) {
      statusText = 'Connected';
      statusColor = Colors.green;
      headerIcon = Icons.check_circle;
      headerIconColor = Colors.green;
    } else {
      statusText = 'Disconnected';
      statusColor = Colors.red;
      headerIcon = Icons.error;
      headerIconColor = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Server header
            Row(
              children: [
                if (isActionRunning)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: headerIconColor,
                    ),
                  )
                else
                  Icon(
                    headerIcon,
                    color: headerIconColor,
                    size: 20,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.server.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Server details table
            _DetailRow(label: 'URL', value: widget.server.url),
            _DetailRow(
              label: 'Status',
              value: statusText,
              valueColor: statusColor,
            ),
            if (widget.sessionId != null)
              _DetailRow(label: 'Session ID', value: widget.sessionId!, mono: true),
            _DetailRow(label: 'OAuth', value: widget.server.oauthStatus.name),
            if (widget.server.headers != null && widget.server.headers!.isNotEmpty)
              _DetailRow(
                label: 'Headers',
                value: '${widget.server.headers!.length} configured',
              ),

            // Action buttons
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!isActionRunning && widget.isConnected)
                  _ActionButton(
                    icon: Icons.link_off,
                    label: 'Disconnect',
                    color: Colors.orange,
                    onPressed: widget.onDisconnect,
                  ),
                if (!isActionRunning && !widget.isConnected)
                  _ActionButton(
                    icon: Icons.link,
                    label: 'Connect',
                    color: Colors.green,
                    onPressed: widget.onConnect,
                  ),
                if (!isActionRunning && widget.server.oauthStatus == McpOAuthStatus.authenticated)
                  _ActionButton(
                    icon: Icons.logout,
                    label: 'OAuth Logout',
                    color: Colors.red,
                    onPressed: widget.onOAuthLogout,
                  ),
                if (!isActionRunning && widget.server.needsOAuth)
                  _ActionButton(
                    icon: Icons.login,
                    label: 'OAuth Login',
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: widget.onOAuthLogin,
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Collapsible tools section
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => setState(() => _toolsExpanded = !_toolsExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                children: [
                  Text(
                    'Tools (${widget.tools.length})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _toolsExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
                ),
              ),
            ),

            if (_toolsExpanded) ...[
              const SizedBox(height: 8),
              if (widget.tools.isEmpty)
                Text(
                  'No tools available',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...widget.tools.map(
                  (tool) => _ToolTile(tool: tool),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: valueColor,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatefulWidget {
  final McpTool tool;

  const _ToolTile({required this.tool});

  @override
  State<_ToolTile> createState() => _ToolTileState();
}

class _ToolTileState extends State<_ToolTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tool = widget.tool;
    final properties =
        (tool.inputSchema['properties'] as Map<String, dynamic>?) ?? {};
    final required_ =
        (tool.inputSchema['required'] as List<dynamic>?)
            ?.cast<String>()
            .toSet() ??
        <String>{};

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tool header (tappable)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.build_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tool.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (tool.description != null &&
                            tool.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              tool.description!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: _expanded ? null : 1,
                              overflow: _expanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${properties.length}p',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Expanded parameters
          if (_expanded && properties.isNotEmpty) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Parameters header row
                  Row(
                    children: [
                      _headerCell('Name', flex: 3),
                      _headerCell('Type', flex: 2),
                      _headerCell('Required', flex: 1),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 4),
                  // Parameter rows
                  ...properties.entries.map((entry) {
                    final paramName = entry.key;
                    final paramSchema =
                        entry.value as Map<String, dynamic>? ?? {};
                    final isRequired = required_.contains(paramName);
                    return _ParameterRow(
                      name: paramName,
                      schema: paramSchema,
                      isRequired: isRequired,
                    );
                  }),
                ],
              ),
            ),
          ],

          // Show raw schema button when expanded
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _RawSchemaSection(inputSchema: tool.inputSchema),
            ),
        ],
      ),
    );
  }

  Widget _headerCell(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _ParameterRow extends StatelessWidget {
  final String name;
  final Map<String, dynamic> schema;
  final bool isRequired;

  const _ParameterRow({
    required this.name,
    required this.schema,
    required this.isRequired,
  });

  String _resolveType(Map<String, dynamic> s) {
    if (s.containsKey('type')) {
      final type = s['type'];
      if (type == 'array' && s.containsKey('items')) {
        final items = s['items'] as Map<String, dynamic>? ?? {};
        return 'array<${_resolveType(items)}>';
      }
      return type.toString();
    }
    if (s.containsKey('anyOf')) return 'anyOf';
    if (s.containsKey('oneOf')) return 'oneOf';
    if (s.containsKey('enum')) return 'enum';
    return 'unknown';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = _resolveType(schema);
    final description = schema['description'] as String?;
    final enumValues = schema['enum'] as List<dynamic>?;
    final defaultValue = schema['default'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  type,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  isRequired ? 'yes' : 'no',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isRequired ? Colors.orange : theme.colorScheme.onSurfaceVariant,
                    fontWeight: isRequired ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          ),
          if (description != null && description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4),
              child: Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
          if (enumValues != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4),
              child: Text(
                'enum: ${enumValues.join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          if (defaultValue != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4),
              child: Text(
                'default: $defaultValue',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RawSchemaSection extends StatefulWidget {
  final Map<String, dynamic> inputSchema;

  const _RawSchemaSection({required this.inputSchema});

  @override
  State<_RawSchemaSection> createState() => _RawSchemaSectionState();
}

class _RawSchemaSectionState extends State<_RawSchemaSection> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _showRaw = !_showRaw),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _showRaw ? Icons.code_off : Icons.code,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                _showRaw ? 'Hide raw schema' : 'Show raw schema',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_showRaw) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(widget.inputSchema),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
