import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/elicitation.dart';

/// Card widget for displaying URL mode elicitation requests
class ElicitationUrlCard extends StatelessWidget {
  final ElicitationRequest request;
  final Future<void> Function(ElicitationAction action)? onRespond;
  final ElicitationAction?
  responseState; // null = pending, accept = completed, decline = declined

  const ElicitationUrlCard({
    super.key,
    required this.request,
    this.onRespond,
    this.responseState,
  });

  bool get _isResponded => responseState != null;

  Future<void> _openUrl(BuildContext context, {bool isViewOnly = false}) async {
    if (request.url == null) return;

    final uri = Uri.tryParse(request.url!);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid URL'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // For view-only mode (already responded), just open the URL directly
    if (isViewOnly) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error opening URL: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return;
    }

    if (onRespond == null) return;

    // Show confirmation dialog with URL
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open External URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(request.message),
            const SizedBox(height: 16),
            const Text(
              'You will be redirected to:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                request.url!,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Domain: ${uri.host}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open URL'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        if (launched) {
          // User opened the URL - respond with accept
          await onRespond!(ElicitationAction.accept);
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to open URL'),
                backgroundColor: Colors.red,
              ),
            );
          }
          await onRespond!(ElicitationAction.cancel);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error opening URL: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        await onRespond!(ElicitationAction.cancel);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = responseState == ElicitationAction.accept;
    final isDeclined = responseState == ElicitationAction.decline;

    Color borderColor;
    Color iconColor;
    IconData icon;
    String title;

    if (isCompleted) {
      borderColor = Colors.green.shade400;
      iconColor = Colors.green.shade700;
      icon = Icons.check_circle;
      title = 'URL Opened';
    } else if (isDeclined) {
      borderColor = Colors.grey.shade400;
      iconColor = Colors.grey.shade600;
      icon = Icons.cancel;
      title = 'Action Declined';
    } else {
      borderColor = Colors.blue.shade300;
      iconColor = Colors.blue.shade700;
      icon = Icons.link;
      title = 'External Action Required';
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
            Text(
              request.message,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isResponded) ...[
                  TextButton(
                    onPressed: onRespond != null
                        ? () => onRespond!(ElicitationAction.decline)
                        : null,
                    child: const Text('Decline'),
                  ),
                  const SizedBox(width: 8),
                ],
                // Always show Open URL button for URL cards (even after responding)
                ElevatedButton.icon(
                  onPressed: () => _openUrl(context, isViewOnly: _isResponded),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(_isResponded ? 'Open URL Again' : 'Open URL'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isResponded
                        ? Colors.grey.shade600
                        : Colors.blue.shade700,
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
