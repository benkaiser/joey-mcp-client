import 'package:flutter/material.dart';
import '../models/mcp_server.dart';
import '../services/database_service.dart';

class McpServerSelectionDialog extends StatefulWidget {
  const McpServerSelectionDialog({super.key});

  @override
  State<McpServerSelectionDialog> createState() =>
      _McpServerSelectionDialogState();
}

class _McpServerSelectionDialogState extends State<McpServerSelectionDialog> {
  List<McpServer> _servers = [];
  final Set<String> _selectedServerIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select MCP Servers'),
      content: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            )
          : _servers.isEmpty
          ? const Text(
              'No MCP servers configured.\nYou can add servers in Settings.',
            )
          : SizedBox(
              width: double.maxFinite,
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _selectedServerIds.toList()),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
