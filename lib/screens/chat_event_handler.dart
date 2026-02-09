import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../providers/conversation_provider.dart';
import '../services/chat_service.dart';
import '../widgets/sampling_request_dialog.dart';
import 'chat_screen.dart';

/// Mixin that handles ChatService events in the chat screen.
mixin ChatEventHandlerMixin on State<ChatScreen> {
  // These must be provided by the host class
  bool get isLoading;
  set isLoadingValue(bool value);
  String get streamingContent;
  set streamingContentValue(String value);
  String get streamingReasoning;
  set streamingReasoningValue(String value);
  String? get currentToolName;
  set currentToolNameValue(String? value);
  bool get isToolExecuting;
  set isToolExecutingValue(bool value);
  bool get authenticationRequired;
  set authenticationRequiredValue(bool value);
  McpProgressNotificationReceived? get currentProgress;
  set currentProgressValue(McpProgressNotificationReceived? value);
  Map<String, Function(Map<String, dynamic>)> get elicitationResponders;
  Set<String> get respondedElicitationIds;
  ChatService? get chatService;
  String getCurrentModel();
  void refreshToolsForServer(String serverId);
  void handleServerNeedsOAuth(String serverId, String serverUrl);

  /// Handle events from the ChatService
  void handleChatEvent(ChatEvent event, ConversationProvider provider) {
    if (!mounted) return;

    if (event is StreamingStarted) {
      // New iteration starting - clear tool execution state
      setState(() {
        currentToolNameValue = null;
        isToolExecutingValue = false;
      });
    } else if (event is ContentChunk) {
      setState(() {
        streamingContentValue = event.content;
        currentToolNameValue = null; // Clear tool name when content is streaming
        isToolExecutingValue = false;
      });
    } else if (event is ReasoningChunk) {
      setState(() {
        streamingReasoningValue = event.content;
      });
    } else if (event is MessageCreated) {
      // Clear streaming state when message is persisted
      setState(() {
        streamingContentValue = '';
        streamingReasoningValue = '';
      });
      // Add message to provider
      provider.addMessage(event.message);
    } else if (event is ToolExecutionStarted) {
      setState(() {
        currentToolNameValue = event.toolName;
        isToolExecutingValue = true; // Now calling the tool
        currentProgressValue = null; // Clear any previous progress
      });
    } else if (event is ToolExecutionCompleted) {
      setState(() {
        // Keep the tool name but mark as completed
        isToolExecutingValue = false;
        currentProgressValue = null; // Clear progress when tool completes
      });
    } else if (event is ConversationComplete) {
      setState(() {
        streamingContentValue = '';
        streamingReasoningValue = '';
        currentToolNameValue = null;
        isToolExecutingValue = false;
        isLoadingValue = false;
        currentProgressValue = null; // Clear progress when conversation completes
      });
    } else if (event is MaxIterationsReached) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum tool call iterations reached'),
          backgroundColor: Colors.orange,
        ),
      );
    } else if (event is SamplingRequestReceived) {
      _showSamplingRequestDialog(event);
    } else if (event is ElicitationRequestReceived) {
      // Create an elicitation message that will be displayed inline
      final elicitationMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: MessageRole.elicitation,
        content: event.request.message,
        timestamp: DateTime.now(),
        elicitationData: jsonEncode({
          'id': event.request.id,
          'mode': event.request.mode.toJson(),
          'message': event.request.message,
          'elicitationId': event.request.elicitationId,
          'url': event.request.url,
          'requestedSchema': event.request.requestedSchema,
        }),
      );

      // Store the responder callback keyed by message ID
      elicitationResponders[elicitationMessage.id] = event.onRespond;

      // Add message to provider
      provider.addMessage(elicitationMessage);
    } else if (event is AuthenticationRequired) {
      // Handle auth error by showing a message in the chat
      setState(() {
        isLoadingValue = false;
        streamingContentValue = '';
        streamingReasoningValue = '';
        currentToolNameValue = null;
        isToolExecutingValue = false;
        authenticationRequiredValue = true;
      });
    } else if (event is ErrorOccurred) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${event.error}'),
          backgroundColor: Colors.red,
        ),
      );
    } else if (event is McpProgressNotificationReceived) {
      // Update progress state
      setState(() {
        currentProgressValue = event;
      });
    } else if (event is McpToolsListChanged) {
      // Refresh tools list for the server
      refreshToolsForServer(event.serverId);
    } else if (event is McpResourcesListChanged) {
      // Could refresh resources here if we had a resources UI
      print('Resources list changed for server: ${event.serverId}');
    } else if (event is McpGenericNotificationReceived) {
      // Create a notification message to display in the chat
      final notificationMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: MessageRole.mcpNotification,
        content: '', // Content is in notificationData
        timestamp: DateTime.now(),
        notificationData: jsonEncode({
          'serverName': event.serverName,
          'serverId': event.serverId,
          'method': event.method,
          'params': event.params,
        }),
      );

      // Add message to provider
      provider.addMessage(notificationMessage);
    } else if (event is McpAuthRequiredForServer) {
      handleServerNeedsOAuth(event.serverId, event.serverUrl);
    }
  }

  /// Show the sampling request dialog for user approval
  void _showSamplingRequestDialog(SamplingRequestReceived event) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SamplingRequestDialog(
        request: event.request,
        onApprove: (approvedRequest) async {
          try {
            // Process the approved sampling request
            final response = await chatService!.processSamplingRequest(
              request: approvedRequest,
              preferredModel: getCurrentModel(),
            );

            // Return the response to the MCP server
            event.onApprove(approvedRequest, response);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Sampling error: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            event.onReject();
          }
        },
        onReject: () async {
          event.onReject();
        },
      ),
    );
  }
}
