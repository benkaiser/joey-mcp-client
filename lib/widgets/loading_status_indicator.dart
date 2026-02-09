import 'package:flutter/material.dart';
import '../services/chat_service.dart';

/// A loading status indicator shown at the bottom of the chat while
/// the assistant is thinking or executing tools.
class LoadingStatusIndicator extends StatelessWidget {
  final String? currentToolName;
  final bool isToolExecuting;
  final McpProgressNotificationReceived? currentProgress;

  const LoadingStatusIndicator({
    super.key,
    required this.currentToolName,
    required this.isToolExecuting,
    required this.currentProgress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          const SizedBox(width: 16),
          SizedBox(
            width: 16,
            height: 16,
            child: currentProgress != null && currentProgress!.percentage != null
                ? CircularProgressIndicator(
                    strokeWidth: 2,
                    value: currentProgress!.percentage! / 100,
                  )
                : const CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _getLoadingStatusText(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Get the status text for the loading indicator
  String _getLoadingStatusText() {
    if (currentToolName != null) {
      final toolText = isToolExecuting
          ? 'Calling tool $currentToolName'
          : 'Called tool $currentToolName';

      // Add progress info if available
      if (currentProgress != null) {
        final progress = currentProgress!;
        if (progress.message != null) {
          return '$toolText - ${progress.message}';
        } else if (progress.percentage != null) {
          return '$toolText - ${progress.percentage!.toStringAsFixed(0)}%';
        } else {
          return '$toolText - ${progress.progress}${progress.total != null ? '/${progress.total}' : ''}';
        }
      }

      return isToolExecuting ? '$toolText...' : toolText;
    }
    return 'Thinking...';
  }
}
