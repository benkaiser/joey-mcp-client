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

/// Widget that renders the message list for a conversation, including
/// message filtering, index mapping, and per-type rendering logic.
class MessageList extends StatelessWidget {
  // Data
  final String conversationId;
  final bool showThinking;
  final String streamingContent;
  final String streamingReasoning;
  final bool isLoading;
  final bool authenticationRequired;
  final ScrollController scrollController;

  // Callbacks
  final Widget Function() buildCommandPalette;
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

  const MessageList({
    super.key,
    required this.conversationId,
    required this.showThinking,
    required this.streamingContent,
    required this.streamingReasoning,
    required this.isLoading,
    required this.authenticationRequired,
    required this.scrollController,
    required this.buildCommandPalette,
    required this.buildAuthRequiredCard,
    this.buildLoadingIndicator,
    required this.onDeleteMessage,
    required this.onEditMessage,
    required this.onRegenerateLastResponse,
    required this.onUrlElicitationResponse,
    required this.onFormElicitationResponse,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationProvider>(
      builder: (context, provider, child) {
        final messages = provider.getMessages(conversationId);

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
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                child: buildCommandPalette(),
              ),
            ],
          );
        }

        // Filter messages based on thinking mode and role
        final displayMessages = messages.where((msg) {
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
        if (!isLoading) {
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
            streamingContent.isNotEmpty ||
            streamingReasoning.isNotEmpty;
        final hasLoadingIndicator = buildLoadingIndicator != null;
        final itemCount =
            displayMessages.length +
            1 + // command palette
            (hasLoadingIndicator ? 1 : 0) +
            (hasStreaming ? 1 : 0) +
            (authenticationRequired ? 1 : 0);

        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          reverse: true, // Anchor to bottom, grow upward
          itemCount: itemCount,
          itemBuilder: (context, index) {
            // Since list is reversed, index 0 is the bottom (newest)
            // We need to map reversed index to actual items:
            // - Index 0: command palette
            // - Index 1: loading indicator (if present)
            // - Next: auth card (if present)
            // - Next: streaming (if present)
            // - Higher indices: older messages

            // Show command palette at index 0 (bottom)
            if (index == 0) {
              return buildCommandPalette();
            }

            // Shift by 1 for command palette
            var currentIndex = index - 1;

            // Show loading indicator right above command palette
            if (hasLoadingIndicator && currentIndex == 0) {
              return buildLoadingIndicator!();
            }
            if (hasLoadingIndicator) currentIndex--;

            // Show auth required card
            if (authenticationRequired && currentIndex == 0) {
              return buildAuthRequiredCard();
            }
            if (authenticationRequired) currentIndex--;

            // Show streaming content
            if (hasStreaming && currentIndex == 0) {
              final streamingMessage = Message(
                id: 'streaming',
                conversationId: conversationId,
                role: MessageRole.assistant,
                content: streamingContent,
                timestamp: DateTime.now(),
                reasoning: streamingReasoning.isNotEmpty
                    ? streamingReasoning
                    : null,
              );
              return MessageBubble(
                message: streamingMessage,
                isStreaming: true,
                showThinking: showThinking,
                onDelete: null, // Can't delete while streaming
                onEdit: null,
              );
            }

            // Calculate message index (reversed: higher index = older message)
            final messageIndex = hasStreaming
                ? currentIndex - 1
                : currentIndex;
            // Map to actual message (from end of list for reversed display)
            final actualMessageIndex =
                displayMessages.length - 1 - messageIndex;

            if (actualMessageIndex < 0 ||
                actualMessageIndex >= displayMessages.length) {
              return const SizedBox.shrink();
            }

            final message = displayMessages[actualMessageIndex];

            // Render model change indicator
            if (message.role == MessageRole.modelChange) {
              return MessageBubble(
                message: message,
                showThinking: showThinking,
                onDelete: () =>
                    onDeleteMessage(message.id, provider),
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
                  request: request,
                  responseState: responseState,
                  onRespond: responseState == null
                      ? (action) => onUrlElicitationResponse(
                          message.id,
                          request,
                          action,
                        )
                      : null,
                );
              } else {
                return ElicitationFormCard(
                  request: request,
                  responseState: responseState,
                  submittedContent: submittedContent,
                  onRespond: responseState == null
                      ? (action, content) =>
                            onFormElicitationResponse(
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
              // Show minimal indicator when thinking is disabled
              if (!showThinking) {
                // Still show images/audio even when thinking is hidden
                if (message.imageData != null ||
                    message.audioData != null) {
                  return Column(
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
                return ThinkingIndicator(message: message);
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
                message: formattedMessage,
                showThinking: showThinking,
                onDelete: () =>
                    onDeleteMessage(formattedMessage.id, provider),
                onEdit: null, // Tool messages can't be edited
              );
            }

            // Format MCP notification messages
            if (message.role == MessageRole.mcpNotification) {
              // Show minimal indicator when thinking is disabled
              if (!showThinking) {
                return ThinkingIndicator(message: message);
              }
              // Full notification display is handled by MessageBubble
              return MessageBubble(
                message: message,
                showThinking: showThinking,
                onDelete: () =>
                    onDeleteMessage(message.id, provider),
                onEdit:
                    null, // Notification messages can't be edited
              );
            }

            // Format assistant messages with tool calls
            if (message.role == MessageRole.assistant &&
                message.toolCallData != null) {
              // Show minimal indicator when thinking is disabled
              if (!showThinking) {
                return ThinkingIndicator(message: message);
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
              );
              return MessageBubble(
                message: formattedMessage,
                showThinking: showThinking,
                onDelete: () =>
                    onDeleteMessage(formattedMessage.id, provider),
                onEdit: null, // Tool call messages can't be edited
              );
            }

            return MessageBubble(
              message: message,
              showThinking: showThinking,
              onDelete: () => onDeleteMessage(message.id, provider),
              onEdit: message.role == MessageRole.user
                  ? () => onEditMessage(message, provider)
                  : null,
              onRegenerate:
                  message.id == lastAssistantContentMessageId
                  ? () => onRegenerateLastResponse(provider)
                  : null,
            );
          },
        );
      },
    );
  }
}
