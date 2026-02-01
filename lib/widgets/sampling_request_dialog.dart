import 'package:flutter/material.dart';

/// Dialog for displaying and approving MCP sampling requests
class SamplingRequestDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  final Future<void> Function(Map<String, dynamic> approvedRequest) onApprove;
  final Future<void> Function() onReject;

  const SamplingRequestDialog({
    super.key,
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<SamplingRequestDialog> createState() => _SamplingRequestDialogState();
}

class _SamplingRequestDialogState extends State<SamplingRequestDialog> {
  late TextEditingController _promptController;
  late TextEditingController _systemPromptController;
  late TextEditingController _maxTokensController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();

    final params = widget.request['params'] as Map<String, dynamic>? ?? {};
    final messages = params['messages'] as List? ?? [];

    // Extract the user message content
    String promptText = '';
    if (messages.isNotEmpty) {
      final firstMessage = messages.first as Map<String, dynamic>;
      final content = firstMessage['content'];
      if (content is Map && content['type'] == 'text') {
        promptText = content['text'] ?? '';
      } else if (content is String) {
        promptText = content;
      }
    }

    _promptController = TextEditingController(text: promptText);
    _systemPromptController = TextEditingController(
      text: params['systemPrompt']?.toString() ?? '',
    );
    _maxTokensController = TextEditingController(
      text: params['maxTokens']?.toString() ?? '1000',
    );
  }

  @override
  void dispose() {
    _promptController.dispose();
    _systemPromptController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  Future<void> _handleApprove() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // Build the approved request with potentially edited content
      final approvedRequest = Map<String, dynamic>.from(widget.request);
      final params = Map<String, dynamic>.from(
        approvedRequest['params'] as Map<String, dynamic>? ?? {},
      );

      // Update the message content
      final messages = [
        {
          'role': 'user',
          'content': {'type': 'text', 'text': _promptController.text},
        },
      ];

      params['messages'] = messages;

      if (_systemPromptController.text.isNotEmpty) {
        params['systemPrompt'] = _systemPromptController.text;
      }

      final maxTokens = int.tryParse(_maxTokensController.text);
      if (maxTokens != null) {
        params['maxTokens'] = maxTokens;
      }

      approvedRequest['params'] = params;

      await widget.onApprove(approvedRequest);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        // Always close the dialog after approval attempt
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handleReject() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await widget.onReject();

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final params = widget.request['params'] as Map<String, dynamic>? ?? {};
    final modelPreferences =
        params['modelPreferences'] as Map<String, dynamic>?;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.psychology, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text('MCP Sampling Request'),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'An MCP server is requesting LLM completion. Review and edit the request before approving:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),

              // Model preferences
              if (modelPreferences != null) ...[
                Text(
                  'Model Preferences:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _buildPreferencesCard(modelPreferences),
                const SizedBox(height: 16),
              ],

              // System prompt
              TextField(
                controller: _systemPromptController,
                decoration: const InputDecoration(
                  labelText: 'System Prompt (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // User prompt
              TextField(
                controller: _promptController,
                decoration: const InputDecoration(
                  labelText: 'Prompt',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
              ),
              const SizedBox(height: 16),

              // Max tokens
              TextField(
                controller: _maxTokensController,
                decoration: const InputDecoration(
                  labelText: 'Max Tokens',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : _handleReject,
          child: const Text('Reject'),
        ),
        FilledButton(
          onPressed: _isProcessing ? null : _handleApprove,
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Approve'),
        ),
      ],
    );
  }

  Widget _buildPreferencesCard(Map<String, dynamic> preferences) {
    final hints = preferences['hints'] as List?;
    final costPriority = preferences['costPriority'];
    final speedPriority = preferences['speedPriority'];
    final intelligencePriority = preferences['intelligencePriority'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hints != null && hints.isNotEmpty) ...[
              Text(
                'Preferred models: ${hints.map((h) => h['name']).join(', ')}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
            ],
            if (costPriority != null)
              Text(
                'Cost priority: ${_formatPriority(costPriority)}',
                style: const TextStyle(fontSize: 12),
              ),
            if (speedPriority != null)
              Text(
                'Speed priority: ${_formatPriority(speedPriority)}',
                style: const TextStyle(fontSize: 12),
              ),
            if (intelligencePriority != null)
              Text(
                'Intelligence priority: ${_formatPriority(intelligencePriority)}',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  String _formatPriority(dynamic priority) {
    if (priority is num) {
      return '${(priority * 100).toStringAsFixed(0)}%';
    }
    return priority.toString();
  }
}
