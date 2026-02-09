import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/mcp_server.dart';
import '../services/mcp_client_service.dart';

/// Screen showing detailed debug information about connected MCP servers
/// and their tools with expandable parameter details.
class McpDebugScreen extends StatelessWidget {
  final List<McpServer> servers;
  final Map<String, McpClientService> clients;
  final Map<String, List<McpTool>> tools;

  const McpDebugScreen({
    super.key,
    required this.servers,
    required this.clients,
    required this.tools,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP Debug'),
      ),
      body: servers.isEmpty
          ? Center(
              child: Text(
                'No MCP servers connected',
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
                return _ServerSection(
                  server: server,
                  client: clients[server.id],
                  tools: tools[server.id] ?? [],
                );
              },
            ),
    );
  }
}

class _ServerSection extends StatelessWidget {
  final McpServer server;
  final McpClientService? client;
  final List<McpTool> tools;

  const _ServerSection({
    required this.server,
    required this.client,
    required this.tools,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = client != null;
    final sessionId = client?.sessionId;

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
                Icon(
                  isConnected ? Icons.check_circle : Icons.error,
                  color: isConnected ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    server.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Server details table
            _DetailRow(label: 'URL', value: server.url),
            _DetailRow(
              label: 'Status',
              value: isConnected ? 'Connected' : 'Disconnected',
              valueColor: isConnected ? Colors.green : Colors.red,
            ),
            if (sessionId != null)
              _DetailRow(label: 'Session ID', value: sessionId, mono: true),
            _DetailRow(label: 'OAuth', value: server.oauthStatus.name),
            if (server.headers != null && server.headers!.isNotEmpty)
              _DetailRow(
                label: 'Headers',
                value: '${server.headers!.length} configured',
              ),

            const SizedBox(height: 16),

            // Tools section
            Text(
              'Tools (${tools.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            if (tools.isEmpty)
              Text(
                'No tools available',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...tools.map(
                (tool) => _ToolTile(tool: tool),
              ),
          ],
        ),
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
