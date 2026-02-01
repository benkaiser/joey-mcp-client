import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message.dart';
import '../utils/date_formatter.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isStreaming;
  final bool showThinking;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.showThinking = true,
    this.onDelete,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final isLoading =
        !isUser &&
        message.content.isEmpty &&
        !isStreaming &&
        (message.reasoning == null || message.reasoning!.isEmpty);

    return Padding(
      padding: EdgeInsets.only(bottom: 12, left: isUser ? 0 : 16),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // User messages get a bubble, assistant messages blend in
                if (isUser)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: SelectableText(
                      message.content,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  )
                else
                  // Assistant messages - no bubble
                  isLoading
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Thinking...',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : SelectionArea(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Show reasoning if present (for assistant messages)
                              if (message.reasoning != null &&
                                  message.reasoning!.isNotEmpty) ...[
                                if (showThinking)
                                  // Full reasoning text when thinking is enabled
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Icon(
                                          Icons.psychology_outlined,
                                          size: 14,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          message.reasoning!,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontSize: 13,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  // Just "Thinking..." indicator when thinking is hidden
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.psychology_outlined,
                                        size: 14,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Thinking...',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontSize: 13,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 12),
                              ],
                              // Assistant content - no bubble
                              if (message.content.isNotEmpty)
                                Markdown(
                                  data: message.content,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  selectable: true,
                                  padding: EdgeInsets.zero,
                                  styleSheet: MarkdownStyleSheet(
                                    p: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    code: TextStyle(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHigh,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    codeblockDecoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    blockquoteDecoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    h1: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    h2: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    h3: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    listBullet: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    a: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              if (isStreaming) ...[
                                const SizedBox(height: 4),
                                Container(
                                  width: 8,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormatter.formatMessageTimestamp(message.timestamp),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Action buttons
                      _buildActionButton(
                        context: context,
                        icon: Icons.copy,
                        tooltip: 'Copy',
                        onPressed: () =>
                            _copyToClipboard(context, showThinking),
                      ),
                      if (onDelete != null)
                        _buildActionButton(
                          context: context,
                          icon: Icons.delete_outline,
                          tooltip: 'Delete',
                          onPressed: onDelete,
                        ),
                      if (isUser && onEdit != null)
                        _buildActionButton(
                          context: context,
                          icon: Icons.edit_outlined,
                          tooltip: 'Edit',
                          onPressed: onEdit,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, bool includeThinking) {
    String textToCopy = message.content;

    // Include reasoning if present and thinking is visible
    if (includeThinking &&
        message.reasoning != null &&
        message.reasoning!.isNotEmpty) {
      textToCopy = 'Thinking:\n${message.reasoning!}\n\n$textToCopy';
    }

    Clipboard.setData(ClipboardData(text: textToCopy));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
