import 'package:flutter/material.dart';
import '../models/elicitation.dart';
import './elicitation_form_screen.dart';

/// Card widget for displaying form mode elicitation requests
class ElicitationFormCard extends StatelessWidget {
  final ElicitationRequest request;
  final Future<void> Function(
    ElicitationAction action,
    Map<String, dynamic>? content,
  )?
  onRespond;
  final ElicitationAction?
  responseState; // null = pending, accept = submitted, decline = declined
  final Map<String, dynamic>? submittedContent;

  const ElicitationFormCard({
    super.key,
    required this.request,
    this.onRespond,
    this.responseState,
    this.submittedContent,
  });

  bool get _isResponded => responseState != null;

  Future<void> _openForm(BuildContext context) async {
    if (onRespond == null) return;

    if (request.requestedSchema == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid form schema'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final form = ElicitationForm.fromSchema(request.requestedSchema!);

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ElicitationFormScreen(request: request, form: form),
        fullscreenDialog: true,
      ),
    );

    if (result != null) {
      final action = result['action'] as ElicitationAction;
      final content = result['content'] as Map<String, dynamic>?;
      await onRespond!(action, content);
    }
  }

  Widget _buildSubmittedValuesView(BuildContext context) {
    if (submittedContent == null || submittedContent!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'Submitted Values:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: submittedContent!.entries.map((entry) {
              final value = entry.value;
              String displayValue;
              if (value is List) {
                displayValue = value.join(', ');
              } else if (value is bool) {
                displayValue = value ? 'Yes' : 'No';
              } else {
                displayValue = value?.toString() ?? 'Not provided';
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.key}: ',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        displayValue,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSubmitted = responseState == ElicitationAction.accept;
    final isDeclined = responseState == ElicitationAction.decline;

    Color borderColor;
    Color iconColor;
    IconData icon;
    String title;

    if (isSubmitted) {
      borderColor = Colors.green.shade600;
      iconColor = Colors.green.shade500;
      icon = Icons.check_circle;
      title = 'Form Submitted';
    } else if (isDeclined) {
      borderColor = Theme.of(context).colorScheme.outline;
      iconColor = Theme.of(context).colorScheme.onSurfaceVariant;
      icon = Icons.cancel;
      title = 'Form Declined';
    } else {
      borderColor = Colors.green.shade600;
      iconColor = Colors.green.shade500;
      icon = Icons.edit_note;
      title = 'Form Required';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(request.message, style: const TextStyle(fontSize: 14)),
            if (isSubmitted) _buildSubmittedValuesView(context),
            if (!_isResponded) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onRespond != null
                        ? () => onRespond!(ElicitationAction.decline, null)
                        : null,
                    child: const Text('Decline'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: onRespond != null
                        ? () => _openForm(context)
                        : null,
                    icon: const Icon(Icons.edit),
                    label: const Text('Fill Form'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
