import 'package:flutter/material.dart';
import '../models/mcp_server.dart';
import '../services/database_service.dart';
import '../services/local_tool_service.dart';
import '../screens/model_picker_screen.dart';

/// Result returned by [McpServerSelectionDialog] containing the selected MCP
/// servers and the (possibly overridden) model ID.
class McpServerSelectionResult {
  final List<String> serverIds;
  final List<String> localToolIds;
  final String? model;

  const McpServerSelectionResult({
    required this.serverIds,
    required this.localToolIds,
    this.model,
  });
}

class McpServerSelectionDialog extends StatefulWidget {
  /// Optional list of server IDs that should be pre-selected.
  final List<String>? initialSelectedServerIds;
  final List<String>? initialSelectedLocalToolIds;

  /// The model that will be used for this conversation.
  final String? selectedModel;

  /// When true, the dialog is editing MCP servers for an existing conversation
  /// rather than creating a new one.
  final bool isEditing;

  const McpServerSelectionDialog({
    super.key,
    this.initialSelectedServerIds,
    this.initialSelectedLocalToolIds,
    this.selectedModel,
    this.isEditing = false,
  });

  @override
  State<McpServerSelectionDialog> createState() =>
      _McpServerSelectionDialogState();
}

class _McpServerSelectionDialogState extends State<McpServerSelectionDialog> {
  List<McpServer> _servers = [];
  final Set<String> _selectedServerIds = {};
  final Set<String> _selectedLocalToolIds = {};
  bool _isLoading = true;
  late String? _selectedModel;

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.selectedModel;
    if (widget.initialSelectedServerIds != null) {
      _selectedServerIds.addAll(widget.initialSelectedServerIds!);
    }
    _selectedLocalToolIds.addAll(
      widget.initialSelectedLocalToolIds ?? LocalToolService.defaultToolIds,
    );
    _loadServers();
  }

  Future<void> _loadServers() async {
    try {
      final servers = await DatabaseService.instance.getAllMcpServers();
      // Only show enabled servers
      final enabledServers = servers.where((s) => s.isEnabled).toList();
      if (!mounted) return;
      setState(() {
        _servers = enabledServers;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading servers: $e')));
      }
    }
  }

  /// Extract a short display name from a full model ID (e.g. "openai/gpt-4o" → "gpt-4o").
  String _shortModelName(String modelId) {
    final parts = modelId.split('/');
    return parts.length > 1 ? parts.sublist(1).join('/') : modelId;
  }

  Future<void> _changeModel() async {
    final picked = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const ModelPickerScreen(showDefaultToggle: false),
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedModel = picked;
      });
    }
  }

  Future<void> _toggleLocalTool(LocalToolDefinition tool, bool selected) async {
    if (selected) {
      final granted = await LocalToolService.requestPermissionForTool(tool.id);
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Permission is required to enable ${tool.groupName}.',
              ),
            ),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      if (selected) {
        _selectedLocalToolIds.add(tool.id);
      } else {
        _selectedLocalToolIds.remove(tool.id);
      }
    });
  }

  Widget _buildLocalToolsSection(BuildContext context) {
    final supportedTools = LocalToolService.allTools
        .where((tool) => tool.isSupported())
        .toList();
    final groupedTools = <String, List<LocalToolDefinition>>{};
    for (final tool in supportedTools) {
      groupedTools.putIfAbsent(tool.groupName, () => []).add(tool);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Local Device Tools',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Run on this device only. These are separate from remote MCP servers.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        ...groupedTools.entries.map((entry) {
          final groupEnabled = entry.value.any(
            (tool) => _selectedLocalToolIds.contains(tool.id),
          );
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.phone_iphone,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    title: Text(entry.key),
                    subtitle: Text(
                      groupEnabled ? 'Enabled' : 'Disabled',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    dense: true,
                  ),
                  ...entry.value.map((tool) {
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 56, right: 8),
                      title: Text(tool.displayName),
                      subtitle: Text(
                        tool.description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      value: _selectedLocalToolIds.contains(tool.id),
                      onChanged: (selected) =>
                          _toggleLocalTool(tool, selected == true),
                    );
                  }),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEditing ? 'MCP Servers' : 'New Conversation'),
      content: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Model section
                    if (_selectedModel != null) ...[
                      Text(
                        'Model',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.smart_toy,
                            size: 18,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _shortModelName(_selectedModel!),
                              style: Theme.of(context).textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: _changeModel,
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                      const Divider(),
                    ],

                    // MCP servers section
                    Text(
                      'MCP Servers',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_servers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'No MCP servers configured.\nYou can add servers in Settings.',
                        ),
                      )
                    else
                      ..._servers.map((server) {
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(server.name),
                          subtitle: Text(
                            server.url,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          value: _selectedServerIds.contains(server.id),
                          onChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                _selectedServerIds.add(server.id);
                              } else {
                                _selectedServerIds.remove(server.id);
                              }
                            });
                          },
                        );
                      }),
                    const Divider(),

                    _buildLocalToolsSection(context),
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(
              context,
              McpServerSelectionResult(
                serverIds: _selectedServerIds.toList(),
                localToolIds: _selectedLocalToolIds.toList(),
                model: _selectedModel,
              ),
            );
          },
          child: Text(widget.isEditing ? 'Update' : 'Start Chat'),
        ),
      ],
    );
  }
}
