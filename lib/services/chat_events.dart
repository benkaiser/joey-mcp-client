import '../models/message.dart';
import '../models/elicitation.dart';

/// Base class for chat events
abstract class ChatEvent {}

/// Event emitted when streaming starts for an iteration
class StreamingStarted extends ChatEvent {
  final int iteration;
  StreamingStarted({required this.iteration});
}

/// Event emitted for content chunks during streaming
class ContentChunk extends ChatEvent {
  final String content;
  ContentChunk({required this.content});
}

/// Event emitted for reasoning chunks during streaming
class ReasoningChunk extends ChatEvent {
  final String content;
  ReasoningChunk({required this.content});
}

/// Event emitted when a message is created
class MessageCreated extends ChatEvent {
  final Message message;
  MessageCreated({required this.message});
}

/// Event emitted when tool execution starts
class ToolExecutionStarted extends ChatEvent {
  final String toolId;
  final String toolName;
  ToolExecutionStarted({required this.toolId, required this.toolName});
}

/// Event emitted when tool execution completes
class ToolExecutionCompleted extends ChatEvent {
  final String toolId;
  final String toolName;
  final String result;
  ToolExecutionCompleted({
    required this.toolId,
    required this.toolName,
    required this.result,
  });
}

/// Event emitted when the conversation is complete
class ConversationComplete extends ChatEvent {}

/// Event emitted when max iterations is reached
class MaxIterationsReached extends ChatEvent {}

/// Event emitted when an error occurs
class ErrorOccurred extends ChatEvent {
  final String error;
  ErrorOccurred({required this.error});
}

/// Event emitted when authentication with OpenRouter is required
class AuthenticationRequired extends ChatEvent {}

/// Event emitted when a sampling request is received from an MCP server
class SamplingRequestReceived extends ChatEvent {
  final Map<String, dynamic> request;
  final Function(
    Map<String, dynamic> approvedRequest,
    Map<String, dynamic> response,
  )
  onApprove;
  final Function() onReject;

  SamplingRequestReceived({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });
}

/// Event emitted when an elicitation request is received from an MCP server
class ElicitationRequestReceived extends ChatEvent {
  final ElicitationRequest request;
  final Function(Map<String, dynamic> response) onRespond;

  ElicitationRequestReceived({required this.request, required this.onRespond});
}

/// Event emitted when a progress notification is received from an MCP server
class McpProgressNotificationReceived extends ChatEvent {
  final String serverId;
  final num progress;
  final num? total;
  final String? message;
  final dynamic progressToken;

  McpProgressNotificationReceived({
    required this.serverId,
    required this.progress,
    this.total,
    this.message,
    this.progressToken,
  });

  /// Returns progress as a percentage (0-100) if total is known
  double? get percentage => total != null ? (progress / total!) * 100 : null;
}

/// Event emitted when the tools list changes on an MCP server
class McpToolsListChanged extends ChatEvent {
  final String serverId;

  McpToolsListChanged({required this.serverId});
}

/// Event emitted when the resources list changes on an MCP server
class McpResourcesListChanged extends ChatEvent {
  final String serverId;

  McpResourcesListChanged({required this.serverId});
}

/// Event emitted when a generic notification is received from an MCP server
class McpGenericNotificationReceived extends ChatEvent {
  final String serverId;
  final String serverName;
  final String method;
  final Map<String, dynamic>? params;

  McpGenericNotificationReceived({
    required this.serverId,
    required this.serverName,
    required this.method,
    this.params,
  });
}

/// Event emitted when an MCP server requires OAuth authentication during a tool call
class McpAuthRequiredForServer extends ChatEvent {
  final String serverId;
  final String serverUrl;

  McpAuthRequiredForServer({required this.serverId, required this.serverUrl});
}
