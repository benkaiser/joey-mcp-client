import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/message.dart';
import '../models/elicitation.dart';
import '../providers/conversation_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/thinking_indicator.dart';
import '../widgets/tool_result_media.dart';
import '../widgets/elicitation_url_card.dart';
import '../widgets/elicitation_form_card.dart';
import '../models/mcp_app_ui.dart';

/// Widget that renders the message list for a conversation, including
/// message filtering, index mapping, and per-type rendering logic.
class MessageList extends StatefulWidget {
  // Data
  final String conversationId;
  final bool showThinking;
  final String streamingContent;
  final String streamingReasoning;
  final bool isLoading;
  final bool authenticationRequired;
  final ScrollController scrollController;

  // Callbacks
  final void Function(bool isAtBottom) onAtBottomChanged;
  final Widget Function() buildAuthRequiredCard;
  final Widget Function()? buildLoadingIndicator;
  final Future<void> Function(String messageId, ConversationProvider provider)
  onDeleteMessage;
  final Future<void> Function(Message message, ConversationProvider provider)
  onEditMessage;
  final Future<void> Function(ConversationProvider provider)
  onRegenerateLastResponse;
  final Future<void> Function(
    String messageId,
    ElicitationRequest request,
    ElicitationAction action,
  )
  onUrlElicitationResponse;
  final Future<void> Function(
    String messageId,
    ElicitationRequest request,
    ElicitationAction action,
    Map<String, dynamic>? content,
  )
  onFormElicitationResponse;

  // Display mode support
  final Map<String, String> webViewDisplayModes;
  final Map<String, List<String>> viewAvailableDisplayModes;
  final Map<String, double> webViewHeights;
  final void Function(String messageId, String mode) onSetDisplayMode;
  final LayerLink Function(String messageId) layerLinkFor;
  final List<String> hostAvailableDisplayModes;

  const MessageList({
    super.key,
    required this.conversationId,
    required this.showThinking,
    required this.streamingContent,
    required this.streamingReasoning,
    required this.isLoading,
    required this.authenticationRequired,
    required this.scrollController,
    required this.onAtBottomChanged,
    required this.buildAuthRequiredCard,
    this.buildLoadingIndicator,
    required this.onDeleteMessage,
    required this.onEditMessage,
    required this.onRegenerateLastResponse,
    required this.onUrlElicitationResponse,
    required this.onFormElicitationResponse,
    required this.webViewDisplayModes,
    required this.viewAvailableDisplayModes,
    required this.webViewHeights,
    required this.onSetDisplayMode,
    required this.layerLinkFor,
    this.hostAvailableDisplayModes = const ['inline', 'fullscreen', 'pip'],
  });

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  /// Whether the user is currently at (or near) the bottom of the list.
  /// In a reversed ListView, "at bottom" means scroll offset ≈ 0.
  bool _isAtBottom = true;

  /// Frozen snapshot of streaming content shown when user scrolls up.
  /// This prevents the streaming bubble at index 0 from growing and
  /// shifting the user's scroll position.
  String? _frozenStreamingContent;
  String? _frozenStreamingReasoning;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    // Notify parent of initial at-bottom state after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      if (widget.scrollController.positions.length != 1) return;
      final pos = widget.scrollController.position;
      final atBottom = pos.maxScrollExtent <= 0 || pos.pixels <= 50.0;
      if (_isAtBottom != atBottom) {
        _isAtBottom = atBottom;
      }
      widget.onAtBottomChanged(atBottom);
    });
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    if (widget.scrollController.positions.length != 1) return;
    final pos = widget.scrollController.position;
    // In reversed list, position 0 = bottom. "At bottom" = within 50px of 0.
    final atBottom = pos.maxScrollExtent <= 0 || pos.pixels <= 50.0;
    if (_isAtBottom != atBottom) {
      _isAtBottom = atBottom;
      if (atBottom) {
        // User returned to bottom — unfreeze streaming content
        _frozenStreamingContent = null;
        _frozenStreamingReasoning = null;
      } else {
        // User scrolled up — freeze current streaming content
        _frozenStreamingContent = widget.streamingContent;
        _frozenStreamingReasoning = widget.streamingReasoning;
      }
      widget.onAtBottomChanged(atBottom);
    }
  }

  @override
  void didUpdateWidget(MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If streaming stopped, clear frozen state
    final isStreaming =
        widget.streamingContent.isNotEmpty ||
        widget.streamingReasoning.isNotEmpty;
    final wasStreaming =
        oldWidget.streamingContent.isNotEmpty ||
        oldWidget.streamingReasoning.isNotEmpty;
    if (!isStreaming) {
      _frozenStreamingContent = null;
      _frozenStreamingReasoning = null;
    }

    // If streaming just started fresh, clear frozen state and reset to bottom
    // This handles edit+resend where a new stream begins after messages are deleted.
    if (isStreaming && !wasStreaming) {
      _frozenStreamingContent = null;
      _frozenStreamingReasoning = null;
      if (!_isAtBottom) {
        _isAtBottom = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onAtBottomChanged(true);
        });
      }
    }

    // If the list is not scrollable, ensure we're "at bottom" and unfrozen
    if (widget.scrollController.hasClients &&
        widget.scrollController.positions.length == 1 &&
        widget.scrollController.position.maxScrollExtent <= 0) {
      _frozenStreamingContent = null;
      _frozenStreamingReasoning = null;
      if (!_isAtBottom) {
        _isAtBottom = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onAtBottomChanged(true);
        });
      }
    }
  }

  /// Build full context display for mcpAppContext messages when thinking is shown.
  Widget _buildFullContextDisplay(
    BuildContext context,
    Message contextMessage,
  ) {
    // Parse content blocks into widgets
    List<Widget> contentWidgets = [];
    try {
      final contentBlocks = jsonDecode(contextMessage.content) as List;
      for (int i = 0; i < contentBlocks.length; i++) {
        final block = contentBlocks[i];
        if (block is Map<String, dynamic>) {
          if (block['type'] == 'text') {
            contentWidgets.add(
              Text(
                block['text'] as String,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                ),
              ),
            );
          } else if (block['type'] == 'image') {
            final data = block['data'] as String?;
            final mimeType = block['mimeType'] as String? ?? 'image/png';
            if (data != null) {
              contentWidgets.add(
                CachedImageWidget(
                  key: ValueKey('${contextMessage.id}_ctx_img_$i'),
                  base64Data: data,
                  mimeType: mimeType,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      contentWidgets.add(
        Text(
          contextMessage.content,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 13,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Additional context from MCP App',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: contentWidgets,
            ),
          ),
        ],
      ),
    );
  }

  /// Build control bar above an inline WebView with display mode buttons.

  /// Build a placeholder for a WebView that is in fullscreen or PIP mode.
  Widget _buildDisplayModePlaceholder(
    BuildContext context,
    String messageId,
    String currentMode,
  ) {
    final modeLabel = currentMode == 'fullscreen'
        ? 'fullscreen'
        : 'picture-in-picture';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            currentMode == 'fullscreen'
                ? Icons.fullscreen
                : Icons.picture_in_picture_alt,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'View is in $modeLabel mode',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => widget.onSetDisplayMode(messageId, 'inline'),
            icon: const Icon(Icons.fullscreen_exit, size: 14),
            label: const Text('Return inline'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Build a placeholder for a hidden WebView.
  Widget _buildHiddenPlaceholder(BuildContext context, String messageId) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'View is hidden',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => widget.onSetDisplayMode(messageId, 'inline'),
            icon: const Icon(Icons.visibility, size: 14),
            label: const Text('Show'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalActionToolResult(BuildContext context, Message message) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(message.content) as Map<String, dynamic>;
    } catch (_) {
      data = const {};
    }
    final action =
        data['action'] as String? ?? _actionFromToolName(message.toolName);
    final url =
        data['url'] as String? ??
        _extractFirstUri(message.content) ??
        message.content;
    final displayUrl = data['displayUrl'] as String? ?? url;
    final title = data['title'] as String? ?? _titleForLocalAction(action);
    final label =
        data['label'] as String? ?? _buttonLabelForLocalAction(action);
    final uri = Uri.tryParse(url);
    final detailRows = _localActionDetailRows(context, data);
    final showRawUri = action == 'open_url';

    return Padding(
      key: ValueKey(message.id),
      padding: const EdgeInsets.only(left: 16, bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _iconForLocalAction(action),
                    size: 18,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...detailRows,
              if (detailRows.isNotEmpty) const SizedBox(height: 8),
              if (showRawUri) ...[
                SelectableText(
                  displayUrl,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: uri == null || !uri.hasScheme
                    ? null
                    : () =>
                          launchUrl(uri, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _actionFromToolName(String? toolName) {
    return switch (toolName) {
      'local_compose_sms' => 'sms',
      'local_call_phone_number' => 'call',
      'local_compose_email' => 'email',
      'local_open_url' => 'open_url',
      _ => 'open_url',
    };
  }

  bool _isLocalActionTool(String? toolName) {
    return const {
      'local_compose_sms',
      'local_call_phone_number',
      'local_compose_email',
      'local_open_url',
    }.contains(toolName);
  }

  String? _extractFirstUri(String content) {
    final match = RegExp(
      r'((?:https?|sms|tel|mailto):[^\s\)]+)',
      caseSensitive: false,
    ).firstMatch(content);
    return match?.group(1);
  }

  String _titleForLocalAction(String action) {
    return switch (action) {
      'sms' => 'SMS draft',
      'call' => 'Phone call',
      'email' => 'Email draft',
      _ => 'Open URL',
    };
  }

  String _buttonLabelForLocalAction(String action) {
    return switch (action) {
      'sms' => 'Open SMS app',
      'call' => 'Open dialer',
      'email' => 'Open email app',
      _ => 'Open URL',
    };
  }

  IconData _iconForLocalAction(String action) {
    return switch (action) {
      'sms' => Icons.sms_outlined,
      'call' => Icons.call_outlined,
      'email' => Icons.email_outlined,
      _ => Icons.open_in_new,
    };
  }

  List<Widget> _localActionDetailRows(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final rows = <Widget>[];
    void addRow(String label, String? value) {
      if (value == null || value.isEmpty) return;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  value,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final action = data['action'] as String?;
    addRow(action == 'sms' ? 'To' : 'Phone', data['phoneNumber'] as String?);
    addRow('To', data['to'] as String?);
    addRow('Subject', data['subject'] as String?);
    addRow('Body', data['body'] as String?);
    addRow('CC', data['cc'] as String?);
    addRow('BCC', data['bcc'] as String?);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationProvider>(
      builder: (context, provider, child) {
        final messages = provider.getMessages(widget.conversationId);

        final bool showEmptyState =
            messages.isEmpty &&
            widget.streamingContent.isEmpty &&
            widget.streamingReasoning.isEmpty &&
            !widget.isLoading;

        if (showEmptyState) {
          // Render empty state inside the same ListView.builder so the
          // ScrollController is never attached to a different scroll view.
          return ListView.builder(
            controller: widget.scrollController,
            itemCount: 1,
            itemBuilder: (context, index) {
              return SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.message_outlined,
                        size: 64,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Start a conversation',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Type a message below to begin',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }

        // Filter messages based on thinking mode and role
        final displayMessages = messages.where((msg) {
          // Hide mcpAppContext messages — rendered inline with parent WebView
          if (msg.role == MessageRole.mcpAppContext) return false;

          // Always show user messages
          if (msg.role == MessageRole.user) return true;

          // Always show elicitation messages
          if (msg.role == MessageRole.elicitation) return true;

          // Show tool role messages (as indicators when thinking disabled)
          if (msg.role == MessageRole.tool) {
            return true;
          }

          // Hide empty assistant messages without tool calls or reasoning
          if (msg.role == MessageRole.assistant &&
              msg.content.isEmpty &&
              msg.reasoning == null &&
              msg.toolCallData == null) {
            return false;
          }

          // Show assistant messages with tool calls (as indicators when thinking disabled)
          if (msg.role == MessageRole.assistant && msg.toolCallData != null) {
            return true;
          }

          return true;
        }).toList();

        // Find the last assistant message with actual content
        // (for the regenerate button). We only show regenerate on
        // the final visible assistant bubble, and only when not loading.
        String? lastAssistantContentMessageId;
        if (!widget.isLoading) {
          for (int i = displayMessages.length - 1; i >= 0; i--) {
            final m = displayMessages[i];
            if (m.role == MessageRole.assistant &&
                m.content.isNotEmpty &&
                m.toolCallData == null) {
              lastAssistantContentMessageId = m.id;
              break;
            }
          }
        }

        // Use frozen content when user has scrolled up to prevent
        // the streaming bubble from growing and shifting their position.
        final displayStreamingContent =
            _frozenStreamingContent ?? widget.streamingContent;
        final displayStreamingReasoning =
            _frozenStreamingReasoning ?? widget.streamingReasoning;

        // Calculate total item count
        final hasStreaming =
            displayStreamingContent.isNotEmpty ||
            displayStreamingReasoning.isNotEmpty;
        final hasLoadingIndicator = widget.buildLoadingIndicator != null;
        final itemCount =
            displayMessages.length +
            (hasLoadingIndicator ? 1 : 0) +
            (hasStreaming ? 1 : 0) +
            (widget.authenticationRequired ? 1 : 0);

        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 56,
          ),
          reverse: true,
          itemCount: itemCount,
          itemBuilder: (context, index) {
            // Reversed list: index 0 is the bottom (newest)
            // Order from bottom: loading indicator, auth card, streaming, messages...
            var currentIndex = index;

            // Loading indicator at the very bottom
            if (hasLoadingIndicator) {
              if (currentIndex == 0) {
                return widget.buildLoadingIndicator!();
              }
              currentIndex--;
            }

            // Auth required card
            if (widget.authenticationRequired) {
              if (currentIndex == 0) {
                return widget.buildAuthRequiredCard();
              }
              currentIndex--;
            }

            // Streaming content
            if (hasStreaming && currentIndex == 0) {
              final streamingMessage = Message(
                id: 'streaming',
                conversationId: widget.conversationId,
                role: MessageRole.assistant,
                content: displayStreamingContent,
                timestamp: DateTime.now(),
                reasoning: displayStreamingReasoning.isNotEmpty
                    ? displayStreamingReasoning
                    : null,
              );
              return MessageBubble(
                message: streamingMessage,
                isStreaming: true,
                showThinking: widget.showThinking,
                onDelete: null,
                onEdit: null,
              );
            }
            if (hasStreaming) currentIndex--;

            // Messages (reversed: higher index = older message)
            final actualMessageIndex =
                displayMessages.length - 1 - currentIndex;

            if (actualMessageIndex < 0 ||
                actualMessageIndex >= displayMessages.length) {
              return const SizedBox.shrink();
            }

            final message = displayMessages[actualMessageIndex];

            // Render model change indicator
            if (message.role == MessageRole.modelChange) {
              return MessageBubble(
                key: ValueKey(message.id),
                message: message,
                showThinking: widget.showThinking,
                onDelete: () => widget.onDeleteMessage(message.id, provider),
                onEdit: null,
              );
            }

            // Render elicitation messages as cards
            if (message.role == MessageRole.elicitation) {
              final elicitationData = jsonDecode(message.elicitationData!);
              final request = ElicitationRequest(
                id: elicitationData['id'] ?? message.id,
                mode: ElicitationMode.fromString(
                  elicitationData['mode'] ?? 'form',
                ),
                message: elicitationData['message'] ?? '',
                elicitationId: elicitationData['elicitationId'],
                url: elicitationData['url'],
                requestedSchema: elicitationData['requestedSchema'],
              );

              // Check if already responded
              final responseStateStr =
                  elicitationData['responseState'] as String?;
              final responseState = responseStateStr != null
                  ? ElicitationAction.fromString(responseStateStr)
                  : null;
              final submittedContent =
                  elicitationData['submittedContent'] as Map<String, dynamic>?;

              if (request.mode == ElicitationMode.url) {
                return ElicitationUrlCard(
                  key: ValueKey(message.id),
                  request: request,
                  responseState: responseState,
                  onRespond: responseState == null
                      ? (action) => widget.onUrlElicitationResponse(
                          message.id,
                          request,
                          action,
                        )
                      : null,
                );
              } else {
                return ElicitationFormCard(
                  key: ValueKey(message.id),
                  request: request,
                  responseState: responseState,
                  submittedContent: submittedContent,
                  onRespond: responseState == null
                      ? (action, content) => widget.onFormElicitationResponse(
                          message.id,
                          request,
                          action,
                          content,
                        )
                      : null,
                );
              }
            }

            // Format tool result messages
            if (message.role == MessageRole.tool) {
              if (_isLocalActionTool(message.toolName)) {
                return _buildLocalActionToolResult(context, message);
              }

              // Check for MCP App UI data (hasUiData is set even when uiData blob isn't loaded)
              if (message.hasUiData) {
                // If uiData blob hasn't been loaded yet, show a loading placeholder
                if (message.uiData == null) {
                  return Column(
                    key: ValueKey(message.id),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ThinkingIndicator(message: message),
                      SizedBox(
                        height: 300.0,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  );
                }

                try {
                  // Validate uiData can be parsed
                  McpAppUiData.fromJson(
                    jsonDecode(message.uiData!) as Map<String, dynamic>,
                  );

                  // Look up associated mcpAppContext message
                  final contextMessage = messages.cast<Message?>().firstWhere(
                    (m) =>
                        m!.role == MessageRole.mcpAppContext &&
                        m.toolCallId == message.id,
                    orElse: () => null,
                  );

                  // Determine current display mode for this WebView
                  final currentDisplayMode =
                      widget.webViewDisplayModes[message.id] ?? 'inline';

                  // If hidden, render a compact "show" placeholder — no WebView mounted
                  if (currentDisplayMode == 'hidden') {
                    return Column(
                      key: ValueKey(message.id),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ThinkingIndicator(message: message),
                        _buildHiddenPlaceholder(context, message.id),
                        if (contextMessage != null) ...[
                          if (!widget.showThinking)
                            ThinkingIndicator(message: contextMessage)
                          else
                            _buildFullContextDisplay(context, contextMessage),
                        ],
                      ],
                    );
                  }

                  // If not inline (fullscreen or pip), render a placeholder
                  if (currentDisplayMode != 'inline') {
                    return Column(
                      key: ValueKey(message.id),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ThinkingIndicator(message: message),
                        _buildDisplayModePlaceholder(
                          context,
                          message.id,
                          currentDisplayMode,
                        ),
                        if (contextMessage != null) ...[
                          if (!widget.showThinking)
                            ThinkingIndicator(message: contextMessage)
                          else
                            _buildFullContextDisplay(context, contextMessage),
                        ],
                      ],
                    );
                  }

                  // Inline mode: render anchor placeholder (WebView is in ChatScreen Stack)
                  final rawInlineHeight =
                      widget.webViewHeights[message.id] ?? 300.0;
                  final screenHeight = MediaQuery.of(context).size.height;
                  final inlineHeight = rawInlineHeight.clamp(
                    50.0,
                    screenHeight * 0.4,
                  );
                  return Column(
                    key: ValueKey(message.id),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ThinkingIndicator(message: message),
                      CompositedTransformTarget(
                        link: widget.layerLinkFor(message.id),
                        child: SizedBox(
                          height:
                              inlineHeight +
                              8.0, // +8 for vertical margin in the overlay
                        ),
                      ),
                      if (contextMessage != null) ...[
                        if (!widget.showThinking)
                          ThinkingIndicator(message: contextMessage)
                        else
                          _buildFullContextDisplay(context, contextMessage),
                      ],
                    ],
                  );
                } catch (e) {
                  // Fall through to normal tool result rendering
                  debugPrint('MCP UI: Failed to parse uiData: $e');
                }
              }

              // Show minimal indicator when thinking is disabled
              if (!widget.showThinking) {
                // Still show images/audio even when thinking is hidden
                if (message.imageData != null || message.audioData != null) {
                  return Column(
                    key: ValueKey(message.id),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ThinkingIndicator(message: message),
                      if (message.imageData != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: ToolResultImages(
                            imageDataJson: message.imageData!,
                            messageId: message.id,
                          ),
                        ),
                      if (message.audioData != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: ToolResultAudio(
                            audioDataJson: message.audioData!,
                            messageId: message.id,
                          ),
                        ),
                    ],
                  );
                }
                return ThinkingIndicator(
                  key: ValueKey(message.id),
                  message: message,
                );
              }
              // Check if this is an error result
              final isError =
                  message.content.startsWith(
                    'Failed to parse tool arguments',
                  ) ||
                  message.content.startsWith('Error executing tool') ||
                  message.content.startsWith('Error executing local tool') ||
                  message.content.startsWith('Tool not found') ||
                  message.content.startsWith('MCP error');
              final icon = isError ? '❌' : '✅';
              final sourceLabel = message.toolName?.startsWith('local_') == true
                  ? 'Local result from'
                  : 'Result from';
              final formattedMessage = message.copyWith(
                content:
                    '$icon **$sourceLabel ${message.toolName}:**\n\n${message.content}',
              );
              return MessageBubble(
                key: ValueKey(message.id),
                message: formattedMessage,
                showThinking: widget.showThinking,
                onDelete: () =>
                    widget.onDeleteMessage(formattedMessage.id, provider),
                onEdit: null, // Tool messages can't be edited
              );
            }

            // Format MCP notification messages
            if (message.role == MessageRole.mcpNotification) {
              // Show minimal indicator when thinking is disabled
              if (!widget.showThinking) {
                return ThinkingIndicator(
                  key: ValueKey(message.id),
                  message: message,
                );
              }
              // Full notification display is handled by MessageBubble
              return MessageBubble(
                key: ValueKey(message.id),
                message: message,
                showThinking: widget.showThinking,
                onDelete: () => widget.onDeleteMessage(message.id, provider),
                onEdit: null, // Notification messages can't be edited
              );
            }

            // Format assistant messages with tool calls
            if (message.role == MessageRole.assistant &&
                message.toolCallData != null) {
              // Show minimal indicator when thinking is disabled
              if (!widget.showThinking) {
                return ThinkingIndicator(
                  key: ValueKey(message.id),
                  message: message,
                );
              }

              // Build tool call display content
              String toolCallContent = '';

              try {
                final toolCalls = jsonDecode(message.toolCallData!) as List;
                for (final toolCall in toolCalls) {
                  final toolName = toolCall['function']['name'];
                  final toolArgsStr = toolCall['function']['arguments'];

                  if (toolCallContent.isNotEmpty) {
                    toolCallContent += '\n\n';
                  }

                  final isLocalTool =
                      toolName is String && toolName.startsWith('local_');
                  toolCallContent += isLocalTool
                      ? '📱 **Calling local device tool:** $toolName'
                      : '🔧 **Calling tool:** $toolName';

                  // Add formatted arguments
                  try {
                    final Map<String, dynamic> toolArgs;
                    if (toolArgsStr is String) {
                      toolArgs = Map<String, dynamic>.from(
                        const JsonCodec().decode(toolArgsStr),
                      );
                    } else {
                      toolArgs = Map<String, dynamic>.from(toolArgsStr);
                    }

                    if (toolArgs.isNotEmpty) {
                      final prettyArgs = const JsonEncoder.withIndent(
                        '  ',
                      ).convert(toolArgs);
                      toolCallContent +=
                          '\n\nArguments:\n```json\n$prettyArgs\n```';
                    }
                  } catch (e) {
                    // Show the raw arguments when parsing fails
                    toolCallContent +=
                        '\n\nArguments (failed to parse):\n```\n$toolArgsStr\n```';
                  }
                }
              } catch (e) {
                // Failed to parse tool calls
              }

              // Move original content to reasoning field (thinking bubble)
              // and show tool calls as the main content
              String displayReasoning = (message.reasoning ?? '').trim();
              final trimmedContent = message.content.trim();

              if (trimmedContent.isNotEmpty) {
                if (displayReasoning.isNotEmpty) {
                  displayReasoning += '\n\n';
                }
                displayReasoning += trimmedContent;
              }

              final formattedMessage = Message(
                id: message.id,
                conversationId: message.conversationId,
                role: message.role,
                content: toolCallContent,
                timestamp: message.timestamp,
                reasoning: displayReasoning.isNotEmpty
                    ? displayReasoning
                    : null,
                toolCallData: message.toolCallData,
                toolCallId: message.toolCallId,
                toolName: message.toolName,
                usageData: message.usageData,
              );
              return MessageBubble(
                key: ValueKey(message.id),
                message: formattedMessage,
                showThinking: widget.showThinking,
                onDelete: () =>
                    widget.onDeleteMessage(formattedMessage.id, provider),
                onEdit: null, // Tool call messages can't be edited
              );
            }

            return MessageBubble(
              key: ValueKey(message.id),
              message: message,
              showThinking: widget.showThinking,
              onDelete: () => widget.onDeleteMessage(message.id, provider),
              onEdit: message.role == MessageRole.user
                  ? () => widget.onEditMessage(message, provider)
                  : null,
              onRegenerate: message.id == lastAssistantContentMessageId
                  ? () => widget.onRegenerateLastResponse(provider)
                  : null,
            );
          },
        );
      },
    );
  }
}

/// Small icon button used in the display mode control bar above inline WebViews.
