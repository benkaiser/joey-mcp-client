import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      appBar: AppBar(title: const Text('MCP Servers')),
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
  late final TextEditingController _oauthClientIdController;
  late final TextEditingController _oauthClientSecretController;

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
    _oauthClientIdController = TextEditingController(
      text: widget.server?.oauthClientId ?? '',
    );
    _oauthClientSecretController = TextEditingController(
      text: widget.server?.oauthClientSecret ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _headersController.dispose();
    _oauthClientIdController.dispose();
    _oauthClientSecretController.dispose();
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
    final oauthClientId = _oauthClientIdController.text.trim();
    final oauthClientSecret = _oauthClientSecretController.text.trim();

    final server = McpServer(
      id: widget.server?.id ?? const Uuid().v4(),
      name: name,
      url: url,
      headers: _parseHeaders(),
      isEnabled: widget.server?.isEnabled ?? true,
      createdAt: widget.server?.createdAt ?? now,
      updatedAt: now,
      oauthClientId: oauthClientId.isNotEmpty ? oauthClientId : null,
      oauthClientSecret: oauthClientSecret.isNotEmpty
          ? oauthClientSecret
          : null,
      oauthStatus: widget.server?.oauthStatus ?? McpOAuthStatus.none,
      oauthTokens: widget.server?.oauthTokens,
    );

    Navigator.pop(context, server);
  }

  void _showOAuthInfo() {
    showDialog(
      context: context,
      builder: (context) => const _OAuthInfoDialog(),
    );
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
            const SizedBox(height: 24),
            // OAuth Configuration Section
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'OAuth Configuration (if required)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.info_outline, size: 20),
                    tooltip: 'Show OAuth setup information',
                    onPressed: _showOAuthInfo,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _oauthClientIdController,
              decoration: const InputDecoration(
                labelText: 'OAuth Client ID (optional)',
                hintText: 'your-app-client-id',
                border: OutlineInputBorder(),
                helperText: 'Leave empty to use default: joey-mcp-client',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _oauthClientSecretController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'OAuth Client Secret',
                hintText: 'your-app-client-secret',
                border: OutlineInputBorder(),
                helperText:
                    'Only required for OAuth providers that don\'t support PKCE without client secrets (like GitHub)',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: Colors.orange[700],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Warning: Storing client secrets in mobile apps is generally not advisable. Only use this if your OAuth provider requires it.',
                      style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                    ),
                  ),
                ],
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
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Dialog showing OAuth redirect URI information
class _OAuthInfoDialog extends StatelessWidget {
  static const String customSchemeUri = 'joey://mcp-oauth/callback';
  static const String httpsUri =
      'https://openrouterauth.benkaiser.dev/api/mcp-oauth';

  const _OAuthInfoDialog();

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('OAuth Setup Information'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'If the MCP server requires OAuth authentication, you\'ll need to register an OAuth application with the authorization provider (e.g., GitHub, Google).',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'Redirect URIs',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When registering your OAuth app, use one of these redirect URIs:',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            // Custom Scheme URI
            _buildUriCard(
              context,
              title: 'Custom Scheme (Preferred)',
              uri: customSchemeUri,
              description:
                  'Use this if the OAuth provider supports custom URL schemes',
              onCopy: () => _copyToClipboard(
                context,
                customSchemeUri,
                'Custom scheme URI',
              ),
            ),
            const SizedBox(height: 12),

            // HTTPS URI
            _buildUriCard(
              context,
              title: 'HTTPS Callback (Fallback)',
              uri: httpsUri,
              description: 'Use this if custom schemes are not supported',
              onCopy: () => _copyToClipboard(context, httpsUri, 'HTTPS URI'),
            ),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Setup steps:',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Register an OAuth app with your provider\n'
                    '2. Use one of the redirect URIs above\n'
                    '3. Copy the Client ID and Client Secret (if required)\n'
                    '4. Paste them in the fields above\n'
                    '\n'
                    'Note: If you don\'t provide a Client ID, the app will use the default: joey-mcp-client',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildUriCard(
    BuildContext context, {
    required String title,
    required String uri,
    required String description,
    required VoidCallback onCopy,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: onCopy,
                tooltip: 'Copy to clipboard',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(
              uri,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
