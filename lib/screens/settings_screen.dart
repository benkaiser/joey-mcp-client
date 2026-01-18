import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/conversation_provider.dart';
import '../services/openrouter_service.dart';
import '../services/default_model_service.dart';
import 'model_picker_screen.dart';
import 'mcp_servers_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _defaultModel;
  Map<String, dynamic>? _defaultModelDetails;
  bool _isLoading = true;
  bool _autoTitleEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadDefaultModel();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final autoTitleEnabled = await DefaultModelService.getAutoTitleEnabled();
    if (mounted) {
      setState(() {
        _autoTitleEnabled = autoTitleEnabled;
      });
    }
  }

  Future<void> _loadDefaultModel() async {
    final defaultModel = await DefaultModelService.getDefaultModel();

    if (defaultModel != null) {
      // Fetch model details
      try {
        final openRouterService = context.read<OpenRouterService>();
        final models = await openRouterService.getModels();
        final modelDetails = models.firstWhere(
          (m) => m['id'] == defaultModel,
          orElse: () => {},
        );

        if (mounted) {
          setState(() {
            _defaultModel = defaultModel;
            _defaultModelDetails = modelDetails.isNotEmpty
                ? modelDetails
                : null;
            _isLoading = false;
          });
        }
      } on OpenRouterAuthException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication expired. Please log in again.'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _defaultModel = defaultModel;
            _isLoading = false;
          });
        }
      }
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _changeDefaultModel() async {
    final selectedModel = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const ModelPickerScreen()),
    );

    if (selectedModel != null) {
      await DefaultModelService.setDefaultModel(selectedModel);
      _loadDefaultModel();
    }
  }

  Future<void> _clearDefaultModel() async {
    await DefaultModelService.clearDefaultModel();
    setState(() {
      _defaultModel = null;
      _defaultModelDetails = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          // Default Model Section
          _buildSectionHeader('Default Model'),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_defaultModel != null)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.stars),
                title: Text(_defaultModelDetails?['name'] ?? _defaultModel!),
                subtitle: Text(
                  _defaultModel!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: _changeDefaultModel,
                      tooltip: 'Change default model',
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _clearDefaultModel,
                      tooltip: 'Clear default model',
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: _changeDefaultModel,
                icon: const Icon(Icons.add),
                label: const Text('Set Default Model'),
              ),
            ),

          const SizedBox(height: 16),

          // Behavior Section
          _buildSectionHeader('Behavior'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SwitchListTile(
              secondary: const Icon(Icons.auto_awesome),
              title: const Text('Auto-generate Titles'),
              subtitle: const Text(
                'Automatically create conversation titles after first response',
              ),
              value: _autoTitleEnabled,
              onChanged: (bool value) async {
                await DefaultModelService.setAutoTitleEnabled(value);
                setState(() {
                  _autoTitleEnabled = value;
                });
              },
            ),
          ),

          const SizedBox(height: 16),

          // MCP Servers Section
          _buildSectionHeader('MCP Servers'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.dns),
              title: const Text('Manage MCP Servers'),
              subtitle: const Text('Configure remote MCP servers'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const McpServersScreen(),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Account Section
          _buildSectionHeader('Account'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.orange),
              title: const Text('Disconnect OpenRouter'),
              subtitle: const Text('You\'ll need to reconnect to use the app'),
              onTap: () => _showLogoutDialog(),
            ),
          ),

          const SizedBox(height: 16),

          // Data Section
          _buildSectionHeader('Data'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Delete All Conversations'),
              subtitle: const Text('This action cannot be undone'),
              onTap: () => _showDeleteAllDialog(),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    final openRouterService = context.read<OpenRouterService>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect OpenRouter'),
        content: const Text(
          'Are you sure you want to disconnect? You\'ll need to reconnect to OpenRouter to continue using the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await openRouterService.logout();
              if (context.mounted) {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close settings
                Navigator.of(context).pushReplacementNamed('/auth');
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAllDialog() {
    final provider = context.read<ConversationProvider>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Conversations'),
        content: const Text(
          'Are you sure you want to delete ALL conversations? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await provider.deleteAllConversations();
              if (context.mounted) {
                Navigator.pop(context); // Close dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All conversations deleted')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }
}
