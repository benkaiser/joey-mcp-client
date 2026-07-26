import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/conversation_provider.dart';
import '../services/openrouter_service.dart';
import '../services/default_model_service.dart';
import '../services/entitlement_service.dart';
import '../services/conversation_import_export_service.dart';
import '../utils/in_app_browser.dart';
import '../utils/privacy_constants.dart';
import 'auth_screen.dart';
import 'model_picker_screen.dart';
import 'premium_screen.dart';
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
  String _providerName = 'OpenRouter';
  bool _isOpenRouterProvider = true;

  @override
  void initState() {
    super.initState();
    _loadDefaultModel();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final openRouterService = context.read<OpenRouterService>();
    final autoTitleEnabled = await DefaultModelService.getAutoTitleEnabled();
    final systemPrompt = await DefaultModelService.getSystemPrompt();
    final maxToolCalls = await DefaultModelService.getMaxToolCalls();
    final providerName = await openRouterService.getProviderDisplayName();
    final isByo = await openRouterService.isUsingOpenAICompatibleProvider();
    if (mounted) {
      setState(() {
        _autoTitleEnabled = autoTitleEnabled;
        _maxToolCalls = maxToolCalls;
        _systemPrompt = systemPrompt;
        _providerName = providerName;
        _isOpenRouterProvider = !isByo;
      });
    }
  }

  Future<void> _loadDefaultModel() async {
    // Capture context-dependent service before any async gaps
    final openRouterService = context.read<OpenRouterService>();
    final defaultModel = await DefaultModelService.getDefaultModel();

    if (defaultModel != null) {
      // Fetch model details
      try {
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
      MaterialPageRoute(
        builder: (context) => const ModelPickerScreen(showDefaultToggle: false),
      ),
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
          // Premium Section (freemium build only)
          if (context.watch<EntitlementService>().isFreemiumBuild) ...[
            _buildSectionHeader('Premium'),
            Builder(
              builder: (context) {
                final isPremium = context.watch<EntitlementService>().isPremium;
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    leading: Icon(
                      isPremium ? Icons.verified : Icons.workspace_premium,
                      color: isPremium ? Colors.green : Colors.amber,
                    ),
                    title: Text(
                      isPremium ? 'Premium unlocked' : 'Upgrade to Premium',
                    ),
                    subtitle: Text(
                      isPremium
                          ? 'All premium features are enabled'
                          : 'Unlimited history, MCP servers, and on-device tools',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PremiumScreen(),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],

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
          _buildSectionHeader('AI Provider'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.settings_applications),
              title: Text('Provider: $_providerName'),
              subtitle: const Text(
                'Change OpenRouter or BYO OpenAI-compatible API details',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AuthScreen()),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.orange),
              title: Text('Forget $_providerName Credentials'),
              subtitle: const Text(
                'Removes saved login/API details from this device',
              ),
              onTap: () => _showLogoutDialog(),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              enabled: _isOpenRouterProvider,
              leading: Icon(
                Icons.delete_forever,
                color: _isOpenRouterProvider
                    ? Colors.red
                    : Theme.of(context).disabledColor,
              ),
              title: const Text('Delete OpenRouter Account'),
              subtitle: Text(
                _isOpenRouterProvider
                    ? 'How to delete your account on OpenRouter'
                    : 'Only available when connected to OpenRouter',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isOpenRouterProvider
                  ? () => _showDeleteOpenRouterAccountDialog()
                  : null,
            ),
          ),

          const SizedBox(height: 16),

          // Data Section
          _buildSectionHeader('Data'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.blue),
              title: const Text('Export All Conversations'),
              subtitle: const Text('Save all conversations as a JSON backup'),
              onTap: () => _exportAllConversations(),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.download, color: Colors.green),
              title: const Text('Import Conversations'),
              subtitle: const Text('Restore conversations from a JSON backup'),
              onTap: () => _importConversations(),
            ),
          ),
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

  Future<void> _exportAllConversations() async {
    final provider = context.read<ConversationProvider>();

    if (provider.conversations.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No conversations to export')),
        );
      }
      return;
    }

    try {
      // Load blob data (images/audio) for all conversations before export
      for (final conversation in provider.conversations) {
        await provider.loadAllBlobsForConversation(conversation.id);
      }

      final jsonString =
          await ConversationImportExportService.exportAllConversations(
            provider,
          );

      final isDesktop =
          !kIsWeb &&
          (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

      if (isDesktop) {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Export All Conversations',
          fileName: 'joey-conversations-export.json',
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (result != null) {
          await File(result).writeAsString(jsonString);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Exported ${provider.conversations.length} conversations',
                ),
              ),
            );
          }
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/joey-conversations-export.json');
        await tempFile.writeAsString(jsonString);
        await SharePlus.instance.share(
          ShareParams(files: [XFile(tempFile.path)]),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importConversations() async {
    // Capture provider before async gap
    final provider = context.read<ConversationProvider>();

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) return;

      final jsonString = await File(file.path!).readAsString();

      final importResult =
          await ConversationImportExportService.importConversations(
            jsonString,
            provider,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${importResult.imported} conversation${importResult.imported == 1 ? '' : 's'}'
              '${importResult.skipped > 0 ? ', ${importResult.skipped} skipped' : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDeleteOpenRouterAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete OpenRouter Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Joey is a client for OpenRouter and cannot delete your OpenRouter '
              'account for you. You can delete it directly on OpenRouter:',
            ),
            const SizedBox(height: 12),
            const Text('1. Open OpenRouter Settings (link below).'),
            const Text('2. Click "Manage Account".'),
            const Text(
              '3. In the modal that opens, select the "Security" tab.',
            ),
            const Text('4. Choose the option to delete your account.'),
            const SizedBox(height: 12),
            const Text(
              'To remove OpenRouter credentials from this device only, use '
              '"Forget OpenRouter Credentials" above.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              launchInAppBrowser(
                Uri.parse('https://openrouter.ai/settings/preferences'),
                context: context,
              );
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open OpenRouter Settings'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    final openRouterService = context.read<OpenRouterService>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget $_providerName Credentials'),
        content: Text(
          'Are you sure you want to remove saved provider credentials from this device? This does not delete any third-party account; it only disconnects Joey locally.',
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
            child: const Text('Forget Credentials'),
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
