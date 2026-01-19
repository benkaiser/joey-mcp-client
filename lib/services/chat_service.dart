import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import 'openrouter_service.dart';
import 'mcp_client_service.dart';

/// Service that handles the chat event loop, decoupled from UI
class ChatService {
  final OpenRouterService _openRouterService;
  final Map<String, McpClientService> _mcpClients;
  final Map<String, List<McpTool>> _mcpTools;

  ChatService({
    required OpenRouterService openRouterService,
    required Map<String, McpClientService> mcpClients,
    required Map<String, List<McpTool>> mcpTools,
  }) : _openRouterService = openRouterService,
       _mcpClients = mcpClients,
       _mcpTools = mcpTools;

  /// Stream controller for chat events
  final _eventController = StreamController<ChatEvent>.broadcast();

  /// Stream of chat events
  Stream<ChatEvent> get events => _eventController.stream;

  void dispose() {
    _eventController.close();
  }

  /// Run the agentic loop for a conversation
  Future<void> runAgenticLoop({
    required String conversationId,
    required String model,
    required List<Message> messages,
    int maxIterations = 10,
  }) async {
    int iterationCount = 0;

    while (iterationCount < maxIterations) {
      iterationCount++;

      // Build API messages from current message list
      final apiMessages = messages
          .map<Map<String, dynamic>>((msg) => msg.toApiMessage())
          .toList();

      print(
        'ChatService: Iteration $iterationCount with ${apiMessages.length} messages',
      );

      // Aggregate all tools from MCP servers
      final allTools = <Map<String, dynamic>>[];
      for (final tools in _mcpTools.values) {
        allTools.addAll(tools.map((t) => t.toJson()));
      }

      // Stream the API response
      String streamedContent = '';
      String streamedReasoning = '';
      List<dynamic>? detectedToolCalls;

      // Start streaming
      _eventController.add(StreamingStarted(iteration: iterationCount));

      try {
        await for (final chunk in _openRouterService.chatCompletionStream(
          model: model,
          messages: apiMessages,
          tools: allTools.isNotEmpty ? allTools : null,
        )) {
          // Check if this chunk contains tool call information
          if (chunk.startsWith('TOOL_CALLS:')) {
            final toolCallsJson = chunk.substring('TOOL_CALLS:'.length);
            try {
              detectedToolCalls = jsonDecode(toolCallsJson) as List;
              print(
                'ChatService: Detected ${detectedToolCalls.length} tool calls',
              );
            } catch (e) {
              print('ChatService: Failed to parse tool calls: $e');
            }
          } else if (chunk.startsWith('REASONING:')) {
            streamedReasoning += chunk.substring('REASONING:'.length);
            _eventController.add(ReasoningChunk(content: streamedReasoning));
          } else {
            streamedContent += chunk;
            _eventController.add(ContentChunk(content: streamedContent));
          }
        }
      } catch (e) {
        _eventController.add(ErrorOccurred(error: e.toString()));
        rethrow;
      }

      print(
        'ChatService: Stream complete. Content: ${streamedContent.length} chars, Tool calls: ${detectedToolCalls?.length ?? 0}',
      );

      if (detectedToolCalls != null && detectedToolCalls.isNotEmpty) {
        print(
          'ChatService: Processing ${detectedToolCalls.length} tool call(s)',
        );

        // Create assistant message with thinking content and tool calls
        final assistantMessage = Message(
          id: const Uuid().v4(),
          conversationId: conversationId,
          role: MessageRole.assistant,
          content: streamedContent.trim(),
          timestamp: DateTime.now(),
          reasoning: streamedReasoning.trim().isNotEmpty
              ? streamedReasoning.trim()
              : null,
          toolCallData: jsonEncode(detectedToolCalls),
        );

        _eventController.add(MessageCreated(message: assistantMessage));
        messages.add(assistantMessage);

        // Execute tool calls
        final toolResults = await _executeToolCalls(detectedToolCalls);

        // Create tool result messages
        for (final result in toolResults) {
          final toolMessage = Message(
            id: const Uuid().v4(),
            conversationId: conversationId,
            role: MessageRole.tool,
            content: result['result'] as String,
            timestamp: DateTime.now(),
            toolCallId: result['toolId'] as String,
            toolName: result['toolName'] as String,
          );

          _eventController.add(MessageCreated(message: toolMessage));
          messages.add(toolMessage);
        }

        // Continue loop for next iteration
      } else {
        // No tool calls - this is the final response
        print('ChatService: Final response received');

        final finalMessage = Message(
          id: const Uuid().v4(),
          conversationId: conversationId,
          role: MessageRole.assistant,
          content: streamedContent,
          timestamp: DateTime.now(),
          reasoning: streamedReasoning.trim().isNotEmpty
              ? streamedReasoning.trim()
              : null,
        );

        _eventController.add(MessageCreated(message: finalMessage));
        messages.add(finalMessage);

        // Dump final message state to console
        print('\n===== FINAL MESSAGE DUMP =====');
        for (int i = 0; i < messages.length; i++) {
          final msg = messages[i];
          print('Message $i:');
          print('  Role: ${msg.role.toString()}');
          print('  Content: ${msg.content}');
          if (msg.reasoning != null) {
            print('  Reasoning: ${msg.reasoning}');
          }
          if (msg.toolCallData != null) {
            print('  Tool Call Data: ${msg.toolCallData}');
          }
          if (msg.toolName != null) {
            print('  Tool Name: ${msg.toolName}');
          }
          if (msg.toolCallId != null) {
            print('  Tool Call ID: ${msg.toolCallId}');
          }
          print('');
        }
        print('==============================\n');

        _eventController.add(ConversationComplete());
        break;
      }
    }

    if (iterationCount >= maxIterations) {
      print('ChatService: Warning - Maximum iterations reached');
      _eventController.add(MaxIterationsReached());
    }
  }

  /// Execute multiple tool calls in parallel
  Future<List<Map<String, dynamic>>> _executeToolCalls(List toolCalls) async {
    final toolResultFutures = toolCalls.map((toolCall) async {
      final toolId = toolCall['id'];
      final toolName = toolCall['function']['name'];
      final toolArgsStr = toolCall['function']['arguments'];

      // Emit event for tool execution start
      _eventController.add(
        ToolExecutionStarted(toolId: toolId, toolName: toolName),
      );

      // Parse arguments
      final Map<String, dynamic> toolArgs;
      if (toolArgsStr is String) {
        toolArgs = Map<String, dynamic>.from(
          const JsonCodec().decode(toolArgsStr),
        );
      } else {
        toolArgs = Map<String, dynamic>.from(toolArgsStr);
      }

      // Find which MCP server has this tool and execute it
      String? result;
      for (final entry in _mcpTools.entries) {
        final serverId = entry.key;
        final tools = entry.value;

        if (tools.any((t) => t.name == toolName)) {
          try {
            final mcpClient = _mcpClients[serverId];
            if (mcpClient != null) {
              final toolResult = await mcpClient.callTool(toolName, toolArgs);
              result = toolResult.content.map((c) => c.text ?? '').join('\n');
            }
          } catch (e) {
            result = 'Error executing tool: $e';
          }
          break;
        }
      }

      final finalResult = result ?? 'Tool not found';

      // Emit event for tool execution complete
      _eventController.add(
        ToolExecutionCompleted(
          toolId: toolId,
          toolName: toolName,
          result: finalResult,
        ),
      );

      return {'toolId': toolId, 'toolName': toolName, 'result': finalResult};
    }).toList();

    return await Future.wait(toolResultFutures);
  }
}

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
