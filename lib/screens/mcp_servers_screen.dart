import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/mcp_server.dart';
import '../services/database_service.dart';

class McpServersScreen extends StatefulWidget {
  const McpServersScreen({super.key});

  @override
  State<McpServersScreen> createState() => _McpServersScreenState();
}

class _McpServersScreenState extends State<McpServersScreen> {
  List<McpServer> _servers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  Future<void> _loadServers() async {
    setState(() => _isLoading = true);
    try {
      final servers = await DatabaseService.instance.getAllMcpServers();
      setState(() {
        _servers = servers;
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

  Future<void> _deleteServer(McpServer server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Server'),
        content: Text('Are you sure you want to delete "${server.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DatabaseService.instance.deleteMcpServer(server.id);
        await _loadServers();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Server deleted')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error deleting server: $e')));
        }
      }
    }
  }

  Future<void> _toggleServerEnabled(McpServer server) async {
    try {
      final updated = server.copyWith(
        isEnabled: !server.isEnabled,
        updatedAt: DateTime.now(),
      );
      await DatabaseService.instance.updateMcpServer(updated);
      await _loadServers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating server: $e')));
      }
    }
  }

  Future<void> _showAddEditDialog([McpServer? server]) async {
    final result = await showDialog<McpServer>(
      context: context,
      builder: (context) => _McpServerDialog(server: server),
    );

    if (result != null) {
      try {
        if (server == null) {
          await DatabaseService.instance.insertMcpServer(result);
        } else {
          await DatabaseService.instance.updateMcpServer(result);
        }
        await _loadServers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(server == null ? 'Server added' : 'Server updated'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error saving server: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP Servers'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _servers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.dns_outlined,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No MCP servers configured',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add a server to get started',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _servers.length,
              itemBuilder: (context, index) {
                final server = _servers[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    title: Text(server.name),
                    subtitle: Text(
                      server.url,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    leading: Switch(
                      value: server.isEnabled,
                      onChanged: (_) => _toggleServerEnabled(server),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showAddEditDialog(server),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          color: Colors.red,
                          onPressed: () => _deleteServer(server),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _McpServerDialog extends StatefulWidget {
  final McpServer? server;

  const _McpServerDialog({this.server});

  @override
  State<_McpServerDialog> createState() => _McpServerDialogState();
}

class _McpServerDialogState extends State<_McpServerDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _headersController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.server?.name ?? '');
    _urlController = TextEditingController(text: widget.server?.url ?? '');
    _headersController = TextEditingController(
      text:
          widget.server?.headers?.entries
              .map((e) => '${e.key}: ${e.value}')
              .join('\n') ??
          '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _headersController.dispose();
    super.dispose();
  }

  Map<String, String>? _parseHeaders() {
    final text = _headersController.text.trim();
    if (text.isEmpty) return null;

    final headers = <String, String>{};
    for (final line in text.split('\n')) {
      final parts = line.split(':');
      if (parts.length >= 2) {
        headers[parts[0].trim()] = parts.sublist(1).join(':').trim();
      }
    }
    return headers.isEmpty ? null : headers;
  }

  void _save() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();

    if (name.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and URL are required')),
      );
      return;
    }

    final now = DateTime.now();
    final server = McpServer(
      id: widget.server?.id ?? const Uuid().v4(),
      name: name,
      url: url,
      headers: _parseHeaders(),
      isEnabled: widget.server?.isEnabled ?? true,
      createdAt: widget.server?.createdAt ?? now,
      updatedAt: now,
    );

    Navigator.pop(context, server);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.server == null ? 'Add MCP Server' : 'Edit MCP Server'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://example.com/mcp',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _headersController,
              decoration: const InputDecoration(
                labelText: 'Headers (optional)',
                hintText: 'Authorization: Bearer token\nX-Custom: value',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
