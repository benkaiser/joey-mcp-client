import 'dart:convert';
import 'openrouter_service.dart';

/// Processes MCP sampling requests by converting them to OpenRouter API calls
/// and running a mini agentic loop (up to 10 iterations).
class SamplingProcessor {
  final OpenRouterService _openRouterService;

  /// Callback to execute tool calls (shared with ChatService)
  final Future<List<Map<String, dynamic>>> Function(List toolCalls)
      executeToolCalls;

  SamplingProcessor({
    required OpenRouterService openRouterService,
    required this.executeToolCalls,
  }) : _openRouterService = openRouterService;

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
        'SamplingProcessor: Converted ${openRouterTools.length} tools for sampling request',
      );
      print('SamplingProcessor: Tools: ${jsonEncode(openRouterTools)}');
    } else {
      print(
        'SamplingProcessor: No tools in sampling request (tools param is ${tools == null ? "null" : "empty"})',
      );
    }

    int iterations = 0;
    const maxSamplingIterations = 10;

    while (iterations < maxSamplingIterations) {
      iterations++;
      print(
        'SamplingProcessor: Calling OpenRouter with ${apiMessages.length} messages (iteration $iterations), model: $model, tools: ${openRouterTools != null ? openRouterTools.length : 0}',
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
        'SamplingProcessor: OpenRouter response - finish_reason: $finishReason, has tool_calls: ${assistantMessage['tool_calls'] != null}',
      );

      // Check if response contains tool calls
      final toolCalls = assistantMessage['tool_calls'] as List?;
      if (toolCalls != null && toolCalls.isNotEmpty) {
        if (iterations < maxSamplingIterations) {
          print(
            'SamplingProcessor: Iteration $iterations: Executing ${toolCalls.length} tool calls and continuing loop',
          );
          // Execute tool calls
          try {
            final toolResults = await executeToolCalls(toolCalls);

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
            print('SamplingProcessor: Error during tool execution: $e');
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
            'SamplingProcessor: Max iterations reached, returning tool calls to server',
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
}
