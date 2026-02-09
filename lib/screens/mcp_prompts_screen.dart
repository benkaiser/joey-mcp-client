import 'package:flutter/material.dart';
import 'package:mcp_dart/mcp_dart.dart' hide McpServer;
import '../models/mcp_server.dart';
import '../services/mcp_client_service.dart';

/// Result returned when a user selects and fills in a prompt.
/// Contains the resolved prompt messages to inject into the chat.
class PromptSelectionResult {
  final List<PromptMessage> messages;
  final String promptName;
  final String? description;

  PromptSelectionResult({
    required this.messages,
    required this.promptName,
    this.description,
  });
}

/// Screen showing available MCP prompts from all connected servers.
/// Users can select a prompt, fill in arguments, and inject messages into the chat.
class McpPromptsScreen extends StatefulWidget {
  final List<McpServer> servers;
  final Map<String, McpClientService> clients;

  const McpPromptsScreen({
    super.key,
    required this.servers,
    required this.clients,
  });

  @override
  State<McpPromptsScreen> createState() => _McpPromptsScreenState();
}

class _McpPromptsScreenState extends State<McpPromptsScreen> {
  /// Map of server ID -> list of prompts
  final Map<String, List<Prompt>> _prompts = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPrompts();
  }

  Future<void> _loadPrompts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      for (final server in widget.servers) {
        final client = widget.clients[server.id];
        if (client == null) continue;

        try {
          final prompts = await client.listPrompts();
          _prompts[server.id] = prompts;
        } catch (e) {
          debugPrint('Failed to list prompts for ${server.name}: $e');
          _prompts[server.id] = [];
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  int get _totalPrompts =>
      _prompts.values.fold(0, (sum, list) => sum + list.length);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MCP Prompts')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load prompts',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadPrompts,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_totalPrompts == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No prompts available',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connected MCP servers have no prompts defined.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.servers.length,
      itemBuilder: (context, index) {
        final server = widget.servers[index];
        final prompts = _prompts[server.id] ?? [];
        if (prompts.isEmpty) return const SizedBox.shrink();

        return _ServerPromptsSection(
          server: server,
          client: widget.clients[server.id],
          prompts: prompts,
        );
      },
    );
  }
}

class _ServerPromptsSection extends StatelessWidget {
  final McpServer server;
  final McpClientService? client;
  final List<Prompt> prompts;

  const _ServerPromptsSection({
    required this.server,
    required this.client,
    required this.prompts,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                Icon(Icons.dns, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    server.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${prompts.length} prompt${prompts.length == 1 ? '' : 's'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Prompts list
            ...prompts.map(
              (prompt) => _PromptTile(prompt: prompt, client: client),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptTile extends StatelessWidget {
  final Prompt prompt;
  final McpClientService? client;

  const _PromptTile({required this.prompt, required this.client});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasArgs = prompt.arguments != null && prompt.arguments!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _onTap(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prompt.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (prompt.description != null &&
                        prompt.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          prompt.description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (hasArgs)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: prompt.arguments!.map((arg) {
                            final isRequired = arg.required == true;
                            return Chip(
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                arg.name,
                                style: theme.textTheme.labelSmall,
                              ),
                              side: BorderSide(
                                color: isRequired
                                    ? theme.colorScheme.primary.withValues(
                                        alpha: 0.5,
                                      )
                                    : theme.colorScheme.outlineVariant,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context) {
    if (client == null) return;

    final hasArgs = prompt.arguments != null && prompt.arguments!.isNotEmpty;

    if (hasArgs) {
      // Show argument dialog
      _showArgumentDialog(context);
    } else {
      // No arguments needed, get the prompt directly
      _getAndReturnPrompt(context, {});
    }
  }

  void _showArgumentDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => _PromptArgumentDialog(
        prompt: prompt,
        onSubmit: (arguments) {
          _getAndReturnPrompt(context, arguments);
        },
      ),
    );
  }

  Future<void> _getAndReturnPrompt(
    BuildContext context,
    Map<String, String> arguments,
  ) async {
    if (client == null) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await client!.getPrompt(
        prompt.name,
        arguments: arguments.isNotEmpty ? arguments : null,
      );

      if (context.mounted) {
        // Dismiss loading dialog
        Navigator.of(context).pop();

        // Return the result to the chat screen
        Navigator.of(context).pop(
          PromptSelectionResult(
            messages: result.messages,
            promptName: prompt.name,
            description: result.description,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        // Dismiss loading dialog
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get prompt: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _PromptArgumentDialog extends StatefulWidget {
  final Prompt prompt;
  final void Function(Map<String, String>) onSubmit;

  const _PromptArgumentDialog({required this.prompt, required this.onSubmit});

  @override
  State<_PromptArgumentDialog> createState() => _PromptArgumentDialogState();
}

class _PromptArgumentDialogState extends State<_PromptArgumentDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    for (final arg in widget.prompt.arguments ?? []) {
      _controllers[arg.name] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arguments = widget.prompt.arguments ?? [];

    return AlertDialog(
      title: Text(widget.prompt.name),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.prompt.description != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      widget.prompt.description!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ...arguments.map((arg) {
                  final isRequired = arg.required == true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: _controllers[arg.name],
                      decoration: InputDecoration(
                        labelText: arg.name + (isRequired ? ' *' : ''),
                        helperText: arg.description,
                        helperMaxLines: 3,
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: null,
                      validator: isRequired
                          ? (value) {
                              if (value == null || value.trim().isEmpty) {
                                return '${arg.name} is required';
                              }
                              return null;
                            }
                          : null,
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              final arguments = <String, String>{};
              for (final entry in _controllers.entries) {
                final value = entry.value.text.trim();
                if (value.isNotEmpty) {
                  arguments[entry.key] = value;
                }
              }
              Navigator.pop(context);
              widget.onSubmit(arguments);
            }
          },
          child: const Text('Use Prompt'),
        ),
      ],
    );
  }
}
