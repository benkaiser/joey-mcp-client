import 'package:flutter/material.dart';
import '../models/elicitation.dart';
import './elicitation_form_screen.dart';

/// Card widget for displaying form mode elicitation requests
class ElicitationFormCard extends StatelessWidget {
  final ElicitationRequest request;
  final Future<void> Function(ElicitationAction action, Map<String, dynamic>? content) onRespond;

  const ElicitationFormCard({
    super.key,
    required this.request,
    required this.onRespond,
  });

  Future<void> _openForm(BuildContext context) async {
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
        builder: (context) => ElicitationFormScreen(
          request: request,
          form: form,
        ),
        fullscreenDialog: true,
      ),
    );

    if (result != null) {
      final action = result['action'] as ElicitationAction;
      final content = result['content'] as Map<String, dynamic>?;
      await onRespond(action, content);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.shade300, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note, color: Colors.green.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Form Required',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              request.message,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => onRespond(ElicitationAction.decline, null),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _openForm(context),
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
        ),
      ),
    );
  }
}
