import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/elicitation.dart';
import 'openrouter_service.dart';
import 'mcp_client_service.dart';
import 'default_model_service.dart';

/// Service that handles the chat event loop, decoupled from UI
class ChatService {
  final OpenRouterService _openRouterService;
  final Map<String, McpClientService> _mcpClients;
  final Map<String, List<McpTool>> _mcpTools;
  final Map<String, String> _serverNames; // serverId -> server name

  ChatService({
    required OpenRouterService openRouterService,
    required Map<String, McpClientService> mcpClients,
    required Map<String, List<McpTool>> mcpTools,
    Map<String, String>? serverNames,
  }) : _openRouterService = openRouterService,
       _mcpClients = mcpClients,
       _mcpTools = mcpTools,
       _serverNames = serverNames ?? {} {
    // Register handlers for all MCP clients
    for (final entry in _mcpClients.entries) {
      final serverId = entry.key;
      final client = entry.value;

      // Set server ID for notifications
      client.setServerId(serverId);

      // Register sampling handler
      client.onSamplingRequest = _handleSamplingRequest;
      client.onElicitationRequest = _handleElicitationRequest;

      // Register notification handlers
      client.onProgressNotification = (notification) {
        _eventController.add(
          McpProgressNotificationReceived(
            serverId: notification.serverId,
            progress: notification.progress,
            total: notification.total,
            message: notification.message,
            progressToken: notification.progressToken,
          ),
        );
      };

      // Register generic notification handler
      client.onGenericNotification = (method, params, serverId) {
        final serverName = _serverNames[serverId] ?? serverId;
        final event = McpGenericNotificationReceived(
          serverId: serverId,
          serverName: serverName,
          method: method,
          params: params,
        );

        // If streaming, queue the notification for later
        if (_isStreaming) {
          _pendingNotifications.add(event);
        } else {
          _eventController.add(event);
        }
      };

      client.onToolsListChanged = () {
        _eventController.add(McpToolsListChanged(serverId: serverId));
      };

      client.onResourcesListChanged = () {
        _eventController.add(McpResourcesListChanged(serverId: serverId));
      };
    }
  }

  /// Stream controller for chat events
  final _eventController = StreamController<ChatEvent>.broadcast();

  /// Stream of chat events
  Stream<ChatEvent> get events => _eventController.stream;

  /// Cancel token for aborting the current request
  CancelToken? _cancelToken;

  /// Flag to track if the current request was cancelled
  bool _wasCancelled = false;

  /// Flag to track if we're currently streaming an LLM response
  bool _isStreaming = false;

  /// Queue of notifications received during streaming
  final List<McpGenericNotificationReceived> _pendingNotifications = [];

  /// Current partial state when cancelled
  String _partialContent = '';
  String _partialReasoning = '';
  List<dynamic>? _partialToolCalls;

  void dispose() {
    _cancelToken?.cancel();
    _eventController.close();
  }

  /// Flush any pending notifications that were queued during streaming
  void _flushPendingNotifications() {
    _isStreaming = false;
    for (final notification in _pendingNotifications) {
      _eventController.add(notification);
    }
    _pendingNotifications.clear();
  }

  /// Cancel the current ongoing request and persist partial state
  Future<void> cancelCurrentRequest({
    required String conversationId,
    required List<Message> messages,
  }) async {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _wasCancelled = true;
      _cancelToken!.cancel('User cancelled');

      // Persist partial content if any exists
      if (_partialContent.isNotEmpty || _partialReasoning.isNotEmpty) {
        final partialMessage = Message(
          id: const Uuid().v4(),
          conversationId: conversationId,
          role: MessageRole.assistant,
          content: _partialContent,
          timestamp: DateTime.now(),
          reasoning: _partialReasoning.isNotEmpty ? _partialReasoning : null,
        );

        _eventController.add(MessageCreated(message: partialMessage));
        messages.add(partialMessage);
      }

      // Clear partial state
      _partialContent = '';
      _partialReasoning = '';
      _partialToolCalls = null;

      // Emit conversation complete event
      _eventController.add(ConversationComplete());
    }
  }

  /// Handle sampling request from an MCP server
  Future<Map<String, dynamic>> _handleSamplingRequest(
    Map<String, dynamic> request,
  ) async {
    // Emit event to notify UI about the sampling request
    final completer = Completer<Map<String, dynamic>>();

    _eventController.add(
      SamplingRequestReceived(
        request: request,
        onApprove: (approvedRequest, response) {
          completer.complete(response);
        },
        onReject: () {
          completer.completeError(
            Exception('Sampling request rejected by user'),
          );
        },
      ),
    );

    return completer.future;
  }

  /// Handle elicitation request from an MCP server
  Future<void> _handleElicitationRequest(
    ElicitationRequest request,
    Future<void> Function(
      String elicitationId,
      ElicitationAction action,
      Map<String, dynamic>? content,
    )
    sendComplete,
  ) async {
    // Emit event to notify UI about the elicitation request
    _eventController.add(
      ElicitationRequestReceived(
        request: request,
        onRespond: (response) async {
          // Extract action and content from response
          final result = response['result'] as Map<String, dynamic>;
          final actionStr = result['action'] as String;
          final action = ElicitationAction.fromString(actionStr);
          final content = result['content'] as Map<String, dynamic>?;
          final elicitationId = request.elicitationId ?? '';

          // Send notification to server
          await sendComplete(elicitationId, action, content);
        },
      ),
    );
  }

  /// Process a sampling request and return the LLM response
  Future<Map<String, dynamic>> processSamplingRequest({
    required Map<String, dynamic> request,
    String? preferredModel,
  }) async {
    final params = request['params'] as Map<String, dynamic>;
    final messages = params['messages'] as List;
    final systemPrompt = params['systemPrompt'] as String?;
    final maxTokens = params['maxTokens'] as int?;
    final modelPreferences =
        params['modelPreferences'] as Map<String, dynamic>?;
    final tools = params['tools'] as List?;
    final toolChoice = params['toolChoice'] as Map<String, dynamic>?;

    // Convert MCP toolChoice to OpenRouter format
    dynamic openRouterToolChoice;
    if (toolChoice != null) {
      final type = (toolChoice['type'] ?? toolChoice['mode']) as String?;
      if (type == 'none' || type == 'auto' || type == 'required') {
        openRouterToolChoice = type;
      } else if (type == 'tool' ||
          (type != null && toolChoice.containsKey('name'))) {
        openRouterToolChoice = {
          'type': 'function',
          'function': {'name': toolChoice['name']},
        };
      }
    }

    // Convert MCP messages to OpenRouter format
    final apiMessages = <Map<String, dynamic>>[];

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      apiMessages.add({'role': 'system', 'content': systemPrompt});
    }

    for (final message in messages) {
      final role = message['role'] as String;
      final content = message['content'];

      // Handle different content types
      if (content is List) {
        // Array of content blocks (tool_use, tool_result, or mixed)
        final convertedContent = <Map<String, dynamic>>[];
        bool hasToolResults = false;
        bool hasToolUse = false;

        for (final block in content) {
          if (block is! Map<String, dynamic>) continue;

          final type = block['type'] as String?;

          if (type == 'text') {
            convertedContent.add({'type': 'text', 'text': block['text']});
          } else if (type == 'tool_use') {
            hasToolUse = true;
            // For OpenRouter, we need to convert to tool_calls format
            // This will be handled differently - we'll create a tool_calls array
          } else if (type == 'tool_result') {
            hasToolResults = true;
            // Convert MCP tool_result to OpenRouter format
            final toolResultContent = block['content'] as List;
            final textContent = toolResultContent
                .where((c) => c['type'] == 'text')
                .map((c) => c['text'])
                .join('\n');

            convertedContent.add({
              'type': 'tool_result',
              'tool_use_id': block['toolUseId'],
              'content': textContent,
            });
          }
        }

        // For assistant messages with tool_use, we need to format as tool_calls
        if (role == 'assistant' && hasToolUse) {
          final toolCalls = <Map<String, dynamic>>[];
          for (final block in content) {
            if (block is Map<String, dynamic> && block['type'] == 'tool_use') {
              toolCalls.add({
                'id': block['id'],
                'type': 'function',
                'function': {
                  'name': block['name'],
                  'arguments': jsonEncode(block['input']),
                },
              });
            }
          }
          apiMessages.add({'role': 'assistant', 'tool_calls': toolCalls});
        } else if (role == 'user' && hasToolResults) {
          // For OpenRouter, tool results go in user messages
          // We need to convert to the format OpenRouter expects
          for (final block in content) {
            if (block is Map<String, dynamic> &&
                block['type'] == 'tool_result') {
              final toolResultContent = block['content'] as List;
              final textContent = toolResultContent
                  .where((c) => c['type'] == 'text')
                  .map((c) => c['text'])
                  .join('\n');

              apiMessages.add({
                'role': 'tool',
                'tool_call_id': block['toolUseId'],
                'content': textContent,
              });
            }
          }
        } else {
          // Regular content array (e.g., just text blocks)
          final textContent = convertedContent
              .where((c) => c['type'] == 'text')
              .map((c) => c['text'])
              .join('\n');
          if (textContent.isNotEmpty) {
            apiMessages.add({'role': role, 'content': textContent});
          }
        }
      } else if (content is Map) {
        // Single content block
        final type = content['type'] as String?;
        if (type == 'text') {
          apiMessages.add({'role': role, 'content': content['text']});
        }
        // Skip image, audio, etc. for now
      } else if (content is String) {
        // Plain string content
        apiMessages.add({'role': role, 'content': content});
      }
    }

    // Select model based on preferences or use default
    String model = preferredModel ?? 'deepseek/deepseek-v3.2';

    if (modelPreferences != null) {
      final hints = modelPreferences['hints'] as List?;
      if (hints != null && hints.isNotEmpty) {
        final firstHint = hints.first['name'] as String?;
        if (firstHint != null) {
          if (firstHint.contains('/')) {
            model = firstHint;
          }
        }
      }
    }

    // Convert MCP tools to OpenRouter format if provided
    List<Map<String, dynamic>>? openRouterTools;
    if (tools != null && tools.isNotEmpty) {
      openRouterTools = tools.map((tool) {
        return {
          'type': 'function',
          'function': {
            'name': tool['name'],
            'description': tool['description'] ?? '',
            'parameters': tool['inputSchema'] ?? {},
          },
        };
      }).toList();
      print(
        'ChatService: Converted ${openRouterTools.length} tools for sampling request',
      );
      print('ChatService: Tools: ${jsonEncode(openRouterTools)}');
    } else {
      print(
        'ChatService: No tools in sampling request (tools param is ${tools == null ? "null" : "empty"})',
      );
    }

    int iterations = 0;
    const maxSamplingIterations = 10;

    while (iterations < maxSamplingIterations) {
      iterations++;
      print(
        'ChatService: Calling OpenRouter with ${apiMessages.length} messages (iteration $iterations), model: $model, tools: ${openRouterTools != null ? openRouterTools.length : 0}',
      );

      // Call OpenRouter with tools if provided
      final response = await _openRouterService.chatCompletion(
        model: model,
        messages: apiMessages,
        tools: openRouterTools,
        toolChoice: openRouterToolChoice,
        maxTokens: maxTokens,
      );

      // Convert OpenRouter response to MCP sampling response format
      final choice = response['choices'][0];
      final assistantMessage = choice['message'];
      final finishReason = choice['finish_reason'];

      print(
        'ChatService: OpenRouter response - finish_reason: $finishReason, has tool_calls: ${assistantMessage['tool_calls'] != null}',
      );

      // Check if response contains tool calls
      final toolCalls = assistantMessage['tool_calls'] as List?;
      if (toolCalls != null && toolCalls.isNotEmpty) {
        if (iterations < maxSamplingIterations) {
          print(
            'ChatService: Iteration $iterations: Executing ${toolCalls.length} tool calls and continuing loop',
          );
          // Execute tool calls
          try {
            final toolResults = await _executeToolCalls(toolCalls);

            // Add assistant message with tool calls to apiMessages
            apiMessages.add({'role': 'assistant', 'tool_calls': toolCalls});

            // Add tool results to apiMessages
            for (final toolResult in toolResults) {
              apiMessages.add({
                'role': 'tool',
                'tool_call_id': toolResult['toolId'],
                'content': toolResult['result'],
              });
            }

            // Continue to next iteration
            continue;
          } catch (e) {
            // Handle any errors during tool execution
            print('ChatService: Error during tool execution: $e');
            return {
              'role': 'assistant',
              'content': {
                'type': 'text',
                'text': 'Error during tool execution: $e',
              },
              'model': model,
              'stopReason': 'endTurn',
            };
          }
        } else {
          print(
            'ChatService: Max iterations reached, returning tool calls to server',
          );
          // Convert OpenRouter tool_calls to MCP tool_use format
          final mcpContent = toolCalls.map((toolCall) {
            final function = toolCall['function'];
            final argumentsStr = function['arguments'] as String;
            final arguments = jsonDecode(argumentsStr);

            return {
              'type': 'tool_use',
              'id': toolCall['id'],
              'name': function['name'],
              'input': arguments,
            };
          }).toList();

          return {
            'role': 'assistant',
            'content': mcpContent,
            'model': model,
            'stopReason': 'toolUse',
          };
        }
      }

      // Regular text response
      return {
        'role': 'assistant',
        'content': {'type': 'text', 'text': assistantMessage['content'] ?? ''},
        'model': model,
        'stopReason': _convertFinishReason(finishReason),
      };
    }

    // Fallback (should not be reached due to returns inside loop)
    return {
      'role': 'assistant',
      'content': {
        'type': 'text',
        'text': 'Error: Maximum sampling iterations exceeded',
      },
      'model': model,
      'stopReason': 'endTurn',
    };
  }

  String _convertFinishReason(String? openRouterReason) {
    switch (openRouterReason) {
      case 'stop':
        return 'endTurn';
      case 'length':
        return 'maxTokens';
      case 'tool_calls':
        return 'toolUse';
      default:
        return 'endTurn';
    }
  }

  /// Run the agentic loop for a conversation
  Future<void> runAgenticLoop({
    required String conversationId,
    required String model,
    required List<Message> messages,
    int maxIterations = 10,
  }) async {
    int iterationCount = 0;

    // Get system prompt
    final systemPrompt = await DefaultModelService.getSystemPrompt();

    // Create a new cancel token for this request
    _cancelToken = CancelToken();

    // Reset partial state and cancellation flag
    _partialContent = '';
    _partialReasoning = '';
    _partialToolCalls = null;
    _wasCancelled = false;

    while (iterationCount < maxIterations) {
      iterationCount++;

      // Build API messages from current message list, prepending system prompt
      // Filter out elicitation messages (they return null from toApiMessage)
      final apiMessages = [
        {'role': 'system', 'content': systemPrompt},
        ...messages
            .map<Map<String, dynamic>?>((msg) => msg.toApiMessage())
            .where((msg) => msg != null)
            .cast<Map<String, dynamic>>(),
      ];

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

      // Start streaming - mark as streaming to queue notifications
      _isStreaming = true;
      _eventController.add(StreamingStarted(iteration: iterationCount));

      try {
        await for (final chunk in _openRouterService.chatCompletionStream(
          model: model,
          messages: apiMessages,
          tools: allTools.isNotEmpty ? allTools : null,
          cancelToken: _cancelToken,
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
            _partialReasoning = streamedReasoning;
            _eventController.add(ReasoningChunk(content: streamedReasoning));
          } else {
            streamedContent += chunk;
            _partialContent = streamedContent;
            _eventController.add(ContentChunk(content: streamedContent));
          }
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          // Request was cancelled - this is expected, don't emit error
          print('ChatService: Request cancelled by user');
          return;
        } else {
          _eventController.add(ErrorOccurred(error: e.toString()));
          rethrow;
        }
      } on OpenRouterAuthException {
        _eventController.add(AuthenticationRequired());
        rethrow;
      } catch (e) {
        _eventController.add(ErrorOccurred(error: e.toString()));
        rethrow;
      }

      print(
        'ChatService: Stream complete. Content: ${streamedContent.length} chars, Tool calls: ${detectedToolCalls?.length ?? 0}',
      );

      // If request was cancelled, don't process the response (partial message already created)
      if (_wasCancelled) {
        print('ChatService: Request was cancelled, skipping message creation');
        return;
      }

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

        // Flush any notifications that were queued during streaming
        // They will appear after the assistant response but before the next LLM call
        _flushPendingNotifications();

        // Continue loop for next iteration
      } else {
        // No tool calls - this is the final response
        print('ChatService: Final response received');

        // If content is empty but we have reasoning, move reasoning to content
        // This ensures the message is visible even when thinking is hidden
        final hasContent = streamedContent.trim().isNotEmpty;
        final hasReasoning = streamedReasoning.trim().isNotEmpty;

        final String finalContent;
        final String? finalReasoning;

        if (!hasContent && hasReasoning) {
          // Move reasoning to content so it's always visible
          finalContent = streamedReasoning.trim();
          finalReasoning = null;
        } else {
          finalContent = streamedContent;
          finalReasoning = hasReasoning ? streamedReasoning.trim() : null;
        }

        final finalMessage = Message(
          id: const Uuid().v4(),
          conversationId: conversationId,
          role: MessageRole.assistant,
          content: finalContent,
          timestamp: DateTime.now(),
          reasoning: finalReasoning,
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

        // Flush any pending notifications before completing
        _flushPendingNotifications();

        _eventController.add(ConversationComplete());
        break;
      }
    }

    if (iterationCount >= maxIterations) {
      print('ChatService: Warning - Maximum iterations reached');
      _flushPendingNotifications();
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
      Map<String, dynamic> toolArgs;
      try {
        if (toolArgsStr is String) {
          toolArgs = Map<String, dynamic>.from(
            const JsonCodec().decode(toolArgsStr),
          );
        } else {
          toolArgs = Map<String, dynamic>.from(toolArgsStr);
        }
      } catch (e) {
        // Failed to parse tool arguments - return error result with the bad arguments
        final errorResult =
            'Failed to parse tool arguments: $e\n\nRaw arguments received:\n$toolArgsStr';

        _eventController.add(
          ToolExecutionCompleted(
            toolId: toolId,
            toolName: toolName,
            result: errorResult,
          ),
        );

        return {'toolId': toolId, 'toolName': toolName, 'result': errorResult};
      }

      // Find which MCP server has this tool and execute it
      String? result;
      for (final entry in _mcpTools.entries) {
        final serverId = entry.key;
        final tools = entry.value;

        if (tools.any((t) => t.name == toolName)) {
          final mcpClient = _mcpClients[serverId];
          try {
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
