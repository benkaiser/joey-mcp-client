import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smooth_markdown/flutter_smooth_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/message.dart';
import '../utils/date_formatter.dart';
import 'tool_result_media.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isStreaming;
  final bool showThinking;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.showThinking = true,
    this.onDelete,
    this.onEdit,
    this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    // Handle model change indicators
    if (message.role == MessageRole.modelChange) {
      return _buildSystemMessage(context);
    }

    // Handle MCP notification messages
    if (message.role == MessageRole.mcpNotification) {
      return _buildNotificationMessage(context);
    }

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Show attached images as thumbnails
                        if (message.imageData != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ToolResultImages(
                              imageDataJson: message.imageData!,
                              messageId: message.id,
                            ),
                          ),
                        if (message.content.isNotEmpty)
                          SelectableText(
                            message.content,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                      ],
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
                      : Focus(
                          autofocus: false,
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
                                        padding: const EdgeInsets.only(
                                          top: 2,
                                        ),
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
                                        child: SelectionArea(
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
                                SmoothMarkdown(
                                  data: message.content,
                                  selectable: true,
                                  useEnhancedComponents: true,
                                  plugins: ParserPluginRegistry()
                                    ..register(const MermaidPlugin()),
                                  builderRegistry: BuilderRegistry()
                                    ..register(
                                      'mermaid',
                                      const MermaidBuilder(),
                                    ),
                                  styleSheet: MarkdownStyleSheet.fromTheme(
                                    Theme.of(context),
                                  ).copyWith(
                                    textStyle: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    inlineCodeStyle: TextStyle(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHigh,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    codeBlockDecoration: BoxDecoration(
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
                                    h1Style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    h2Style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    h3Style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    listBulletStyle: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    linkStyle: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                  onTapLink: (url) {
                                    launchUrl(
                                      Uri.parse(url),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                ),
                              // Render images from imageData if present
                              if (message.imageData != null)
                                ToolResultImages(
                                  imageDataJson: message.imageData!,
                                  messageId: message.id,
                                ),
                              // Render audio players from audioData if present
                              if (message.audioData != null)
                                ToolResultAudio(
                                  audioDataJson: message.audioData!,
                                  messageId: message.id,
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
                      if (onRegenerate != null)
                        _buildActionButton(
                          context: context,
                          icon: Icons.refresh,
                          tooltip: 'Regenerate',
                          onPressed: onRegenerate,
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

  /// Build a system message indicator (e.g. model change)
  Widget _buildSystemMessage(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.swap_horiz,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      message.content,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Build the notification message display
  Widget _buildNotificationMessage(BuildContext context) {
    String serverName = 'MCP Server';
    String method = 'notification';
    Map<String, dynamic>? params;

    if (message.notificationData != null) {
      try {
        final data =
            jsonDecode(message.notificationData!) as Map<String, dynamic>;
        serverName = data['serverName'] as String? ?? 'MCP Server';
        method = data['method'] as String? ?? 'notification';
        params = data['params'] as Map<String, dynamic>?;
      } catch (e) {
        // Ignore parse errors
      }
    }

    // Format the params as JSON if present
    String paramsJson = '';
    if (params != null) {
      const encoder = JsonEncoder.withIndent('  ');
      paramsJson = encoder.convert(params);
    }

    // When showThinking is disabled, show a minimal collapsed view
    if (!showThinking) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 16),
        child: Row(
          children: [
            Icon(
              Icons.notifications_outlined,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              'Notification from $serverName',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    // Full notification display when showThinking is enabled
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.notifications_outlined,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Notification from $serverName',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Notification content in a styled container
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Method
                Text(
                  'method: "$method"',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                if (paramsJson.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'params:',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    paramsJson,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
