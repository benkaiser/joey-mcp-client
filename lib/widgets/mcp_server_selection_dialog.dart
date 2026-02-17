import 'package:flutter/material.dart';
import '../models/mcp_server.dart';
import '../services/database_service.dart';
import '../screens/model_picker_screen.dart';

/// Result returned by [McpServerSelectionDialog] containing the selected MCP
/// servers and the (possibly overridden) model ID.
class McpServerSelectionResult {
  final List<String> serverIds;
  final String model;

  const McpServerSelectionResult({
    required this.serverIds,
    required this.model,
  });
}

class McpServerSelectionDialog extends StatefulWidget {
  /// Optional list of server IDs that should be pre-selected.
  final List<String>? initialSelectedServerIds;

  /// The model that will be used for this conversation.
  final String? selectedModel;

  /// When true, the dialog is editing MCP servers for an existing conversation
  /// rather than creating a new one.
  final bool isEditing;

  const McpServerSelectionDialog({
    super.key,
    this.initialSelectedServerIds,
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
  bool _isLoading = true;
  late String? _selectedModel;

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.selectedModel;
    if (widget.initialSelectedServerIds != null) {
      _selectedServerIds.addAll(widget.initialSelectedServerIds!);
    }
    _loadServers();
  }

  Future<void> _loadServers() async {
    try {
      final servers = await DatabaseService.instance.getAllMcpServers();
      // Only show enabled servers
      final enabledServers = servers.where((s) => s.isEnabled).toList();
      setState(() {
        _servers = enabledServers;
        _isLoading = false;
      });
    } catch (e) {
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
          : SizedBox(
              width: double.maxFinite,
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _servers.length,
                        itemBuilder: (context, index) {
                          final server = _servers[index];
                          return CheckboxListTile(
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
                        },
                      ),
                    ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_selectedModel != null) {
              Navigator.pop(
                context,
                McpServerSelectionResult(
                  serverIds: _selectedServerIds.toList(),
                  model: _selectedModel!,
                ),
              );
            } else {
              Navigator.pop(context, _selectedServerIds.toList());
            }
          },
          child: Text(widget.isEditing ? 'Update' : 'Start Chat'),
        ),
      ],
    );
  }
}
