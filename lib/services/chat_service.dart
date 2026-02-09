import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/elicitation.dart';
import 'openrouter_service.dart';
import 'mcp_client_service.dart';
import 'default_model_service.dart';
import 'chat_events.dart';
import 'sampling_processor.dart';

export 'chat_events.dart';

/// Convert a MIME type like 'audio/mpeg' to its short format name like 'mp3'.
String _audioFormatFromMimeType(String mimeType) {
  const mimeToFormat = {
    'audio/mpeg': 'mp3',
    'audio/mp3': 'mp3',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/wave': 'wav',
    'audio/aiff': 'aiff',
    'audio/x-aiff': 'aiff',
    'audio/aac': 'aac',
    'audio/ogg': 'ogg',
    'audio/flac': 'flac',
    'audio/x-flac': 'flac',
    'audio/mp4': 'm4a',
    'audio/x-m4a': 'm4a',
    'audio/m4a': 'm4a',
    'audio/pcm': 'pcm16',
    'audio/L16': 'pcm16',
    'audio/webm': 'webm',
  };
  return mimeToFormat[mimeType] ?? mimeType.replaceFirst('audio/', '');
}

/// Service that handles the chat event loop, decoupled from UI
class ChatService {
  final OpenRouterService _openRouterService;
  final Map<String, McpClientService> _mcpClients;
  final Map<String, List<McpTool>> _mcpTools;
  final Map<String, String> _serverNames; // serverId -> server name
  late final SamplingProcessor _samplingProcessor;

  ChatService({
    required OpenRouterService openRouterService,
    required Map<String, McpClientService> mcpClients,
    required Map<String, List<McpTool>> mcpTools,
    Map<String, String>? serverNames,
  }) : _openRouterService = openRouterService,
       _mcpClients = mcpClients,
       _mcpTools = mcpTools,
       _serverNames = serverNames ?? {} {
    _samplingProcessor = SamplingProcessor(
      openRouterService: _openRouterService,
      executeToolCalls: _executeToolCalls,
    );
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

  /// Update the MCP server references and register handlers for new clients.
  /// Call this when the set of active MCP servers changes mid-conversation.
  void updateServers({
    required Map<String, McpClientService> mcpClients,
    required Map<String, List<McpTool>> mcpTools,
    required Map<String, String> serverNames,
  }) {
    // Update server names
    _serverNames.clear();
    _serverNames.addAll(serverNames);

    // Register handlers for any new clients
    for (final entry in mcpClients.entries) {
      final serverId = entry.key;
      if (_mcpClients.containsKey(serverId)) continue; // Already registered

      final client = entry.value;
      client.setServerId(serverId);
      client.onSamplingRequest = _handleSamplingRequest;
      client.onElicitationRequest = _handleElicitationRequest;

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

      client.onGenericNotification = (method, params, serverId) {
        final serverName = _serverNames[serverId] ?? serverId;
        final event = McpGenericNotificationReceived(
          serverId: serverId,
          serverName: serverName,
          method: method,
          params: params,
        );
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

    // Sync the maps. If the caller passes the same map instances we hold,
    // we must avoid clearing them first (which would destroy the data).
    // Only copy if they are different objects.
    if (!identical(_mcpClients, mcpClients)) {
      _mcpClients.clear();
      _mcpClients.addAll(mcpClients);
    }
    if (!identical(_mcpTools, mcpTools)) {
      _mcpTools.clear();
      _mcpTools.addAll(mcpTools);
    }
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

  /// Process a sampling request and return the LLM response.
  /// Delegates to SamplingProcessor.
  Future<Map<String, dynamic>> processSamplingRequest({
    required Map<String, dynamic> request,
    String? preferredModel,
  }) async {
    return _samplingProcessor.processSamplingRequest(
      request: request,
      preferredModel: preferredModel,
    );
  }

  /// Run the agentic loop for a conversation
  Future<void> runAgenticLoop({
    required String conversationId,
    required String model,
    required List<Message> messages,
    int maxIterations = 10,
    bool modelSupportsImages = false,
    bool modelSupportsAudio = false,
  }) async {
    final bool unlimited = maxIterations <= 0;
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

    while (unlimited || iterationCount < maxIterations) {
      iterationCount++;

      // Build API messages from current message list, prepending system prompt
      // Filter out elicitation messages (they return null from toApiMessage)
      final apiMessages = <Map<String, dynamic>>[
        {'role': 'system', 'content': systemPrompt},
      ];
      for (final msg in messages) {
        final apiMsg = msg.toApiMessage();
        if (apiMsg == null) continue;
        apiMessages.add(apiMsg);

        // If the model supports images and this tool result has image data,
        // inject a user message with the images so the LLM can see them
        if (modelSupportsImages &&
            msg.role == MessageRole.tool &&
            msg.imageData != null) {
          try {
            final images = jsonDecode(msg.imageData!) as List;
            if (images.isNotEmpty) {
              final contentParts = <Map<String, dynamic>>[
                {
                  'type': 'text',
                  'text':
                      '[Images returned by tool "${msg.toolName ?? 'unknown'}"]',
                },
              ];
              for (final img in images) {
                final data = img['data'] as String;
                final mimeType = img['mimeType'] as String? ?? 'image/png';
                contentParts.add({
                  'type': 'image_url',
                  'image_url': {'url': 'data:$mimeType;base64,$data'},
                });
              }
              apiMessages.add({'role': 'user', 'content': contentParts});
            }
          } catch (e) {
            print('ChatService: Failed to inject images: $e');
          }
        }

        // If the model supports audio and this tool result has audio data,
        // inject a user message with the audio so the LLM can process it
        if (modelSupportsAudio &&
            msg.role == MessageRole.tool &&
            msg.audioData != null) {
          try {
            final audioList = jsonDecode(msg.audioData!) as List;
            if (audioList.isNotEmpty) {
              final contentParts = <Map<String, dynamic>>[
                {
                  'type': 'text',
                  'text':
                      '[Audio returned by tool "${msg.toolName ?? 'unknown'}"]',
                },
              ];
              for (final audio in audioList) {
                final data = audio['data'] as String;
                final mimeType = audio['mimeType'] as String? ?? 'audio/wav';
                contentParts.add({
                  'type': 'input_audio',
                  'input_audio': {
                    'data': data,
                    'format': _audioFormatFromMimeType(mimeType),
                  },
                });
              }
              apiMessages.add({'role': 'user', 'content': contentParts});
            }
          } catch (e) {
            print('ChatService: Failed to inject audio: $e');
          }
        }
      }

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
            imageData: result['imageData'] as String?,
            audioData: result['audioData'] as String?,
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

    if (!unlimited && iterationCount >= maxIterations) {
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
      String? imageDataJson;
      String? audioDataJson;
      for (final entry in _mcpTools.entries) {
        final serverId = entry.key;
        final tools = entry.value;

        if (tools.any((t) => t.name == toolName)) {
          final mcpClient = _mcpClients[serverId];
          try {
            if (mcpClient != null) {
              final toolResult = await mcpClient.callTool(toolName, toolArgs);
              // Extract text content
              final textParts = toolResult.content
                  .where((c) => c.type == 'text' && c.text != null)
                  .map((c) => c.text!)
                  .toList();
              result = textParts.join('\n');

              // Extract image content
              final images = toolResult.content
                  .where((c) => c.type == 'image' && c.data != null)
                  .map(
                    (c) => {
                      'data': c.data as String,
                      'mimeType': c.mimeType ?? 'image/png',
                    },
                  )
                  .toList();
              if (images.isNotEmpty) {
                imageDataJson = jsonEncode(images);
              }

              // Extract audio content
              final audioItems = toolResult.content
                  .where((c) => c.type == 'audio' && c.data != null)
                  .map(
                    (c) => {
                      'data': c.data as String,
                      'mimeType': c.mimeType ?? 'audio/wav',
                    },
                  )
                  .toList();
              if (audioItems.isNotEmpty) {
                audioDataJson = jsonEncode(audioItems);
              }
            }
          } on McpAuthRequiredException catch (e) {
            result = 'Error: Authentication required for MCP server';
            _eventController.add(
              McpAuthRequiredForServer(serverId: serverId, serverUrl: e.serverUrl),
            );
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

      return {
        'toolId': toolId,
        'toolName': toolName,
        'result': finalResult,
        if (imageDataJson != null) 'imageData': imageDataJson,
        if (audioDataJson != null) 'audioData': audioDataJson,
      };
    }).toList();

    return await Future.wait(toolResultFutures);
  }
}
