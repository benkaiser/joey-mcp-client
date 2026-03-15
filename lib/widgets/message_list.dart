import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  ) onUrlElicitationResponse;
  final Future<void> Function(
    String messageId,
    ElicitationRequest request,
    ElicitationAction action,
    Map<String, dynamic>? content,
  ) onFormElicitationResponse;

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
  /// We auto-scroll to bottom only when this is true.
  bool _isAtBottom = true;

  /// Whether the user is actively dragging the list. Used to avoid
  /// overriding a manual scroll with auto-scroll.
  bool _isUserScrolling = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    // Notify parent of initial at-bottom state after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.hasClients) return;
      final pos = widget.scrollController.position;
      final atBottom = pos.maxScrollExtent <= 0 ||
          pos.pixels >= pos.maxScrollExtent - 50.0;
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
    final pos = widget.scrollController.position;
    // "At bottom" if content isn't scrollable, or within 50px of maxScrollExtent
    final atBottom = pos.maxScrollExtent <= 0 ||
        pos.pixels >= pos.maxScrollExtent - 50.0;
    if (_isAtBottom != atBottom) {
      _isAtBottom = atBottom;
      widget.onAtBottomChanged(atBottom);
    }
  }

  @override
  void didUpdateWidget(MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ScrollMetricsNotification handles auto-scroll for all content changes
  }

  /// Build full context display for mcpAppContext messages when thinking is shown.
  Widget _buildFullContextDisplay(BuildContext context, Message contextMessage) {
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
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
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
  Widget _buildDisplayModePlaceholder(BuildContext context, String messageId, String currentMode) {
    final modeLabel = currentMode == 'fullscreen' ? 'fullscreen' : 'picture-in-picture';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            currentMode == 'fullscreen' ? Icons.fullscreen : Icons.picture_in_picture_alt,
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationProvider>(
      builder: (context, provider, child) {
        final messages = provider.getMessages(widget.conversationId);

        if (messages.isEmpty) {
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.message_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Start a conversation',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Type a message below to begin',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
          if (msg.role == MessageRole.assistant &&
              msg.toolCallData != null) {
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

        // Calculate total item count
        final hasStreaming =
            widget.streamingContent.isNotEmpty ||
            widget.streamingReasoning.isNotEmpty;
        final hasLoadingIndicator = widget.buildLoadingIndicator != null;
        final itemCount =
            displayMessages.length +
            (hasLoadingIndicator ? 1 : 0) +
            (hasStreaming ? 1 : 0) +
            (widget.authenticationRequired ? 1 : 0);

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification &&
                notification.dragDetails != null) {
              _isUserScrolling = true;
            } else if (notification is ScrollEndNotification) {
              _isUserScrolling = false;
            }
            return false;
          },
          child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            // When scroll metrics change (content grew/shrank), auto-scroll
            // to bottom if user was at the bottom and isn't actively scrolling.
            if (_isAtBottom && !_isUserScrolling) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || !widget.scrollController.hasClients) return;
                final max = widget.scrollController.position.maxScrollExtent;
                if (widget.scrollController.position.pixels < max) {
                  widget.scrollController.jumpTo(max);
                }
              });
            }
            // Update at-bottom state based on new metrics
            final pos = notification.metrics;
            final atBottom = pos.maxScrollExtent <= 0 ||
                pos.pixels >= pos.maxScrollExtent - 50.0;
            if (_isAtBottom != atBottom) {
              _isAtBottom = atBottom;
              widget.onAtBottomChanged(atBottom);
            }
            return false;
          },
          child: ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 56),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            // Non-reversed list: index 0 is the top (oldest)
            // Order: messages..., streaming, auth card, loading indicator

            // Indices 0..displayMessages.length-1: messages in chronological order
            if (index < displayMessages.length) {
              // Fall through to message rendering below
            } else {
              // Items after messages
              var extraIndex = index - displayMessages.length;

              // Streaming content (right after messages)
              if (hasStreaming) {
                if (extraIndex == 0) {
                  final streamingMessage = Message(
                    id: 'streaming',
                    conversationId: widget.conversationId,
                    role: MessageRole.assistant,
                    content: widget.streamingContent,
                    timestamp: DateTime.now(),
                    reasoning: widget.streamingReasoning.isNotEmpty
                        ? widget.streamingReasoning
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
                extraIndex--;
              }

              // Auth required card
              if (widget.authenticationRequired) {
                if (extraIndex == 0) {
                  return widget.buildAuthRequiredCard();
                }
                extraIndex--;
              }

              // Loading indicator (at bottom)
              if (hasLoadingIndicator) {
                if (extraIndex == 0) {
                  return widget.buildLoadingIndicator!();
                }
              }

              return const SizedBox.shrink();
            }

            final actualMessageIndex = index;

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
                onDelete: () =>
                    widget.onDeleteMessage(message.id, provider),
                onEdit: null,
              );
            }

            // Render elicitation messages as cards
            if (message.role == MessageRole.elicitation) {
              final elicitationData = jsonDecode(
                message.elicitationData!,
              );
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
                  elicitationData['submittedContent']
                      as Map<String, dynamic>?;

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
                      ? (action, content) =>
                            widget.onFormElicitationResponse(
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
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
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
                    (m) => m!.role == MessageRole.mcpAppContext && m.toolCallId == message.id,
                    orElse: () => null,
                  );

                  // Determine current display mode for this WebView
                  final currentDisplayMode = widget.webViewDisplayModes[message.id] ?? 'inline';

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
                        _buildDisplayModePlaceholder(context, message.id, currentDisplayMode),
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
                  final rawInlineHeight = widget.webViewHeights[message.id] ?? 300.0;
                  final screenHeight = MediaQuery.of(context).size.height;
                  final inlineHeight = rawInlineHeight.clamp(50.0, screenHeight * 0.4);
                  return Column(
                    key: ValueKey(message.id),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ThinkingIndicator(message: message),
                      CompositedTransformTarget(
                        link: widget.layerLinkFor(message.id),
                        child: SizedBox(
                          height: inlineHeight + 8.0, // +8 for vertical margin in the overlay
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
                if (message.imageData != null ||
                    message.audioData != null) {
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
                return ThinkingIndicator(key: ValueKey(message.id), message: message);
              }
              // Check if this is an error result
              final isError =
                  message.content.startsWith(
                    'Failed to parse tool arguments',
                  ) ||
                  message.content.startsWith(
                    'Error executing tool',
                  ) ||
                  message.content.startsWith('Tool not found') ||
                  message.content.startsWith('MCP error');
              final icon = isError ? '❌' : '✅';
              final formattedMessage = message.copyWith(
                content:
                    '$icon **Result from ${message.toolName}:**\n\n${message.content}',
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
                return ThinkingIndicator(key: ValueKey(message.id), message: message);
              }
              // Full notification display is handled by MessageBubble
              return MessageBubble(
                key: ValueKey(message.id),
                message: message,
                showThinking: widget.showThinking,
                onDelete: () =>
                    widget.onDeleteMessage(message.id, provider),
                onEdit:
                    null, // Notification messages can't be edited
              );
            }

            // Format assistant messages with tool calls
            if (message.role == MessageRole.assistant &&
                message.toolCallData != null) {
              // Show minimal indicator when thinking is disabled
              if (!widget.showThinking) {
                return ThinkingIndicator(key: ValueKey(message.id), message: message);
              }

              // Build tool call display content
              String toolCallContent = '';

              try {
                final toolCalls =
                    jsonDecode(message.toolCallData!) as List;
                for (final toolCall in toolCalls) {
                  final toolName = toolCall['function']['name'];
                  final toolArgsStr =
                      toolCall['function']['arguments'];

                  if (toolCallContent.isNotEmpty) {
                    toolCallContent += '\n\n';
                  }

                  toolCallContent +=
                      '🔧 **Calling tool:** $toolName';

                  // Add formatted arguments
                  try {
                    final Map<String, dynamic> toolArgs;
                    if (toolArgsStr is String) {
                      toolArgs = Map<String, dynamic>.from(
                        const JsonCodec().decode(toolArgsStr),
                      );
                    } else {
                      toolArgs = Map<String, dynamic>.from(
                        toolArgsStr,
                      );
                    }

                    if (toolArgs.isNotEmpty) {
                      final prettyArgs =
                          const JsonEncoder.withIndent(
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
              String displayReasoning = (message.reasoning ?? '')
                  .trim();
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
              onRegenerate:
                  message.id == lastAssistantContentMessageId
                  ? () => widget.onRegenerateLastResponse(provider)
                  : null,
            );
          },
        ),
        ),
        );
      },
    );
  }
}

/// Small icon button used in the display mode control bar above inline WebViews.
