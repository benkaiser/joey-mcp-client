import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/conversation_provider.dart';
import '../services/openrouter_service.dart';
import '../services/default_model_service.dart';
import '../utils/in_app_browser.dart';
import '../utils/privacy_constants.dart';
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
  String _systemPrompt = '';
  int _maxToolCalls = 10;

  @override
  void initState() {
    super.initState();
    _loadDefaultModel();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final autoTitleEnabled = await DefaultModelService.getAutoTitleEnabled();
    final systemPrompt = await DefaultModelService.getSystemPrompt();
    final maxToolCalls = await DefaultModelService.getMaxToolCalls();
    if (mounted) {
      setState(() {
        _autoTitleEnabled = autoTitleEnabled;
        _maxToolCalls = maxToolCalls;
        _systemPrompt = systemPrompt;
      });
    }
  }

  Future<void> _loadDefaultModel() async {
    final defaultModel = await DefaultModelService.getDefaultModel();

    if (defaultModel != null) {
      // Fetch model details
      try {
        if (!context.mounted) return;
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
          // Navigate to auth screen - replace entire navigation stack
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/auth', (route) => false);
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
      MaterialPageRoute(builder: (context) => const ModelPickerScreen(showDefaultToggle: false)),
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
      appBar: AppBar(title: const Text('Settings')),
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
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('Max Tool Calls'),
              subtitle: Text(
                _maxToolCalls == 0 ? 'Unlimited' : '$_maxToolCalls per message',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showMaxToolCallsDialog,
            ),
          ),

          const SizedBox(height: 16),
          _buildSectionHeader('System Prompt'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.chat),
              title: const Text('Customize System Prompt'),
              subtitle: Text(
                _systemPrompt.length > 50
                    ? '${_systemPrompt.substring(0, 50)}...'
                    : _systemPrompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.edit),
              onTap: () => _showSystemPromptDialog(),
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

          const SizedBox(height: 16),

          // Legal Section
          _buildSectionHeader('Legal'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => launchInAppBrowser(
                Uri.parse(PrivacyConstants.privacyPolicyUrl),
                context: context,
              ),
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

  void _showMaxToolCallsDialog() {
    // Preset options: common values + unlimited
    final options = [5, 10, 20, 50, 100, 0]; // 0 = unlimited
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Max Tool Calls'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Maximum number of tool calls the AI can make per message. '
                  'Set to Unlimited for complex agentic tasks.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                RadioGroup<int>(
                  groupValue: _maxToolCalls,
                  onChanged: (int? newValue) async {
                    if (newValue != null) {
                      await DefaultModelService.setMaxToolCalls(newValue);
                      setState(() {
                        _maxToolCalls = newValue;
                      });
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  child: Column(
                    children: options.map((value) {
                      final label = value == 0 ? 'Unlimited' : '$value';
                      final isSelected = _maxToolCalls == value;
                      return RadioListTile<int>(
                        title: Text(label),
                        value: value,
                        dense: true,
                        selected: isSelected,
                      );
                    }).toList(),
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
          ],
        );
      },
    );
  }

  void _showSystemPromptDialog() {
    final controller = TextEditingController(text: _systemPrompt);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('System Prompt'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This prompt is sent to the AI with every conversation:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Enter system prompt',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
                autofocus: true,
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
            onPressed: () async {
              await DefaultModelService.resetSystemPrompt();
              final defaultPrompt = await DefaultModelService.getSystemPrompt();
              setState(() {
                _systemPrompt = defaultPrompt;
              });
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('System prompt reset to default'),
                  ),
                );
              }
            },
            child: const Text('Reset to Default'),
          ),
          TextButton(
            onPressed: () async {
              final newPrompt = controller.text.trim();
              if (newPrompt.isNotEmpty) {
                await DefaultModelService.setSystemPrompt(newPrompt);
                setState(() {
                  _systemPrompt = newPrompt;
                });
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
