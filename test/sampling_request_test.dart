import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'dart:async';
import 'package:joey_mcp_client_flutter/services/chat_service.dart';
import 'package:joey_mcp_client_flutter/services/openrouter_service.dart';
import 'package:joey_mcp_client_flutter/services/mcp_client_service.dart';
import 'package:joey_mcp_client_flutter/models/message.dart';

// Generate mocks for OpenRouterService
@GenerateMocks([OpenRouterService])
import 'sampling_request_test.mocks.dart';

void main() {
  group('Sampling Request Flow', () {
    late MockOpenRouterService mockOpenRouterService;
    late ChatService chatService;
    late McpClientService mcpClient;
    late StreamController<ChatEvent> eventController;
    late List<ChatEvent> capturedEvents;

    setUp(() {
      mockOpenRouterService = MockOpenRouterService();
      capturedEvents = [];
      eventController = StreamController<ChatEvent>.broadcast();

      // Create a real MCP client with a fake URL (we won't actually call it)
      mcpClient = McpClientService(
        serverUrl: 'https://fake-mcp-server.example.com',
      );

      // Create ChatService with mocked OpenRouter
      chatService = ChatService(
        openRouterService: mockOpenRouterService,
        mcpClients: {'test-server': mcpClient},
        mcpTools: {
          'test-server': [
            McpTool(
              name: 'test_tool',
              description: 'A test tool',
              inputSchema: {'type': 'object', 'properties': {}},
            ),
          ],
        },
      );

      // Capture all events emitted by the chat service
      chatService.events.listen((event) {
        capturedEvents.add(event);
      });
    });

    tearDown(() {
      chatService.dispose();
      mcpClient.close();
      eventController.close();
    });

    test('should emit SamplingRequestReceived event when MCP server requests sampling', () async {
      // Arrange: Create a sampling request that would come from an MCP server
      final samplingRequest = {
        'jsonrpc': '2.0',
        'id': 123,
        'method': 'sampling/createMessage',
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {
                'type': 'text',
                'text': 'What is the weather like today?',
              },
            },
          ],
          'systemPrompt': 'You are a helpful weather assistant.',
          'maxTokens': 500,
          'modelPreferences': {
            'hints': [
              {'name': 'claude-3-sonnet'},
            ],
            'intelligencePriority': 0.8,
          },
        },
      };

      // Mock OpenRouter response for the sampling request
      final mockOpenRouterResponse = {
        'choices': [
          {
            'message': {'content': 'It is sunny today'},
            'finish_reason': 'stop',
          },
        ],
      };

      when(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
        maxTokens: anyNamed('maxTokens'),
      )).thenAnswer((_) async => mockOpenRouterResponse);

      // Act: Trigger the sampling request through the MCP client's handler
      SamplingRequestReceived? samplingEvent;

      // Listen for the event
      final eventCompleter = Completer<void>();
      chatService.events.listen((event) {
        if (event is SamplingRequestReceived) {
          samplingEvent = event;
          // Simulate approval
          event.onApprove(samplingRequest, {
            'role': 'assistant',
            'content': {'type': 'text', 'text': 'It is sunny today'},
            'model': 'anthropic/claude-3-5-sonnet',
            'stopReason': 'endTurn',
          });
          eventCompleter.complete();
        }
      });

      // Trigger the handler (this would normally be called by _parseSSEStreamReal)
      mcpClient.handleSamplingRequest(samplingRequest);

      // Wait for the event
      await eventCompleter.future.timeout(const Duration(seconds: 2));

      // Assert: Verify the event was emitted correctly
      expect(samplingEvent, isNotNull);
      expect(samplingEvent!.request, equals(samplingRequest));
      expect(samplingEvent!.onApprove, isNotNull);
      expect(samplingEvent!.onReject, isNotNull);
    });

    test('should process approved sampling request and call OpenRouter', () async {
      // Arrange: Mock OpenRouter response
      final mockOpenRouterResponse = {
        'choices': [
          {
            'message': {
              'content': 'The weather is sunny and warm today.',
            },
            'finish_reason': 'stop',
          },
        ],
      };

      when(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
        maxTokens: anyNamed('maxTokens'),
      )).thenAnswer((_) async => mockOpenRouterResponse);

      final samplingRequest = {
        'jsonrpc': '2.0',
        'id': 456,
        'method': 'sampling/createMessage',
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {
                'type': 'text',
                'text': 'What is 2+2?',
              },
            },
          ],
          'systemPrompt': 'You are a math tutor.',
          'maxTokens': 100,
        },
      };

      // Act: Process the sampling request directly
      final response = await chatService.processSamplingRequest(
        request: samplingRequest,
        preferredModel: 'anthropic/claude-3-5-sonnet',
      );

      // Assert: Verify OpenRouter was called correctly
      verify(mockOpenRouterService.chatCompletion(
        model: 'anthropic/claude-3-5-sonnet',
        messages: argThat(
          containsAll([
            {'role': 'system', 'content': 'You are a math tutor.'},
            {'role': 'user', 'content': 'What is 2+2?'},
          ]),
          named: 'messages',
        ),
        maxTokens: 100,
      )).called(1);

      // Assert: Verify the response is in correct MCP format
      expect(response['role'], equals('assistant'));
      expect(response['content']['type'], equals('text'));
      expect(response['content']['text'], equals('The weather is sunny and warm today.'));
      expect(response['model'], equals('anthropic/claude-3-5-sonnet'));
      expect(response['stopReason'], equals('endTurn'));
    });

    test('should use model hint from preferences if provided', () async {
      // Arrange: Mock OpenRouter response
      final mockOpenRouterResponse = {
        'choices': [
          {
            'message': {'content': 'Response'},
            'finish_reason': 'stop',
          },
        ],
      };

      when(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
      )).thenAnswer((_) async => mockOpenRouterResponse);

      final samplingRequest = {
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'Hello'},
            },
          ],
          'modelPreferences': {
            'hints': [
              {'name': 'openai/gpt-4'},
            ],
          },
        },
      };

      // Act
      await chatService.processSamplingRequest(
        request: samplingRequest,
        preferredModel: 'anthropic/claude-3-5-sonnet',
      );

      // Assert: Should use the hint model instead of preferred
      verify(mockOpenRouterService.chatCompletion(
        model: 'openai/gpt-4',
        messages: anyNamed('messages'),
      )).called(1);
    });

    test('should handle complex content formats in sampling requests', () async {
      // Arrange
      final mockOpenRouterResponse = {
        'choices': [
          {
            'message': {'content': 'Processed'},
            'finish_reason': 'stop',
          },
        ],
      };

      when(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
      )).thenAnswer((_) async => mockOpenRouterResponse);

      final samplingRequest = {
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {
                'type': 'text',
                'text': 'Analyze this data',
              },
            },
            {
              'role': 'assistant',
              'content': {
                'type': 'text',
                'text': 'I see the data',
              },
            },
            {
              'role': 'user',
              'content': {
                'type': 'text',
                'text': 'What does it mean?',
              },
            },
          ],
          'systemPrompt': 'You are a data analyst.',
        },
      };

      // Act
      final response = await chatService.processSamplingRequest(
        request: samplingRequest,
        preferredModel: 'anthropic/claude-3-5-sonnet',
      );

      // Assert: Verify all messages were converted correctly
      final captured = verify(
        mockOpenRouterService.chatCompletion(
          model: anyNamed('model'),
          messages: captureAnyNamed('messages'),
        ),
      ).captured.single as List<Map<String, dynamic>>;

      expect(captured.length, equals(4)); // system + 3 messages
      expect(captured[0]['role'], equals('system'));
      expect(captured[0]['content'], equals('You are a data analyst.'));
      expect(captured[1]['role'], equals('user'));
      expect(captured[1]['content'], equals('Analyze this data'));
      expect(captured[2]['role'], equals('assistant'));
      expect(captured[2]['content'], equals('I see the data'));
      expect(captured[3]['role'], equals('user'));
      expect(captured[3]['content'], equals('What does it mean?'));
    });

    test('should skip non-text content types in sampling requests', () async {
      // Arrange
      final mockOpenRouterResponse = {
        'choices': [
          {
            'message': {'content': 'OK'},
            'finish_reason': 'stop',
          },
        ],
      };

      when(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
      )).thenAnswer((_) async => mockOpenRouterResponse);

      final samplingRequest = {
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {
                'type': 'text',
                'text': 'Hello',
              },
            },
            {
              'role': 'user',
              'content': {
                'type': 'image',
                'data': 'base64-image-data',
              },
            },
            {
              'role': 'user',
              'content': {
                'type': 'text',
                'text': 'World',
              },
            },
          ],
        },
      };

      // Act
      await chatService.processSamplingRequest(
        request: samplingRequest,
        preferredModel: 'anthropic/claude-3-5-sonnet',
      );

      // Assert: Only text messages should be included
      final captured = verify(
        mockOpenRouterService.chatCompletion(
          model: anyNamed('model'),
          messages: captureAnyNamed('messages'),
        ),
      ).captured.single as List<Map<String, dynamic>>;

      expect(captured.length, equals(2)); // Only 2 text messages
      expect(captured[0]['content'], equals('Hello'));
      expect(captured[1]['content'], equals('World'));
    });

    test('should convert OpenRouter finish reasons correctly', () async {
      // Test different finish reasons
      final testCases = [
        {'openRouterReason': 'stop', 'expectedMcpReason': 'endTurn'},
        {'openRouterReason': 'length', 'expectedMcpReason': 'maxTokens'},
        {'openRouterReason': 'tool_calls', 'expectedMcpReason': 'toolUse'},
        {'openRouterReason': null, 'expectedMcpReason': 'endTurn'},
        {'openRouterReason': 'unknown', 'expectedMcpReason': 'endTurn'},
      ];

      for (final testCase in testCases) {
        // Arrange
        final mockResponse = {
          'choices': [
            {
              'message': {'content': 'Response'},
              'finish_reason': testCase['openRouterReason'],
            },
          ],
        };

        when(mockOpenRouterService.chatCompletion(
          model: anyNamed('model'),
          messages: anyNamed('messages'),
        )).thenAnswer((_) async => mockResponse);

        final samplingRequest = {
          'params': {
            'messages': [
              {
                'role': 'user',
                'content': {'type': 'text', 'text': 'Test'},
              },
            ],
          },
        };

        // Act
        final response = await chatService.processSamplingRequest(
          request: samplingRequest,
        );

        // Assert
        expect(
          response['stopReason'],
          equals(testCase['expectedMcpReason']),
          reason: 'Failed for finish_reason: ${testCase['openRouterReason']}',
        );
      }
    });

    test('should handle sampling request rejection', () async {
      // Arrange
      final samplingRequest = {
        'jsonrpc': '2.0',
        'id': 789,
        'method': 'sampling/createMessage',
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'Test'},
            },
          ],
        },
      };

      // Act & Assert
      final eventCompleter = Completer<void>();
      Exception? caughtException;

      // Listen for the sampling event and reject it
      chatService.events.listen((event) {
        if (event is SamplingRequestReceived) {
          // Simulate user rejection
          event.onReject();
          eventCompleter.complete();
        }
      });

      // Trigger the sampling request - it should eventually throw
      try {
        await mcpClient.handleSamplingRequest(samplingRequest);
      } catch (e) {
        caughtException = e as Exception;
      }

      // Wait for the event to be processed
      await eventCompleter.future.timeout(const Duration(seconds: 2));

      // Should have caught an exception
      expect(caughtException, isNotNull);
      expect(caughtException.toString(), contains('rejected by user'));
    });

    test('should handle string content format in sampling requests', () async {
      // Some MCP servers might send content as a plain string instead of an object
      // Arrange
      final mockOpenRouterResponse = {
        'choices': [
          {
            'message': {'content': 'Response'},
            'finish_reason': 'stop',
          },
        ],
      };

      when(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
      )).thenAnswer((_) async => mockOpenRouterResponse);

      final samplingRequest = {
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': 'Plain string content',
            },
          ],
        },
      };

      // Act
      await chatService.processSamplingRequest(
        request: samplingRequest,
        preferredModel: 'anthropic/claude-3-5-sonnet',
      );

      // Assert
      final captured = verify(
        mockOpenRouterService.chatCompletion(
          model: anyNamed('model'),
          messages: captureAnyNamed('messages'),
        ),
      ).captured.single as List<Map<String, dynamic>>;

      expect(captured.length, equals(1));
      expect(captured[0]['role'], equals('user'));
      expect(captured[0]['content'], equals('Plain string content'));
    });

    test('should include maxTokens in OpenRouter request when specified', () async {
      // Arrange
      final mockOpenRouterResponse = {
        'choices': [
          {
            'message': {'content': 'Short response'},
            'finish_reason': 'stop',
          },
        ],
      };

      when(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
        maxTokens: anyNamed('maxTokens'),
      )).thenAnswer((_) async => mockOpenRouterResponse);

      final samplingRequest = {
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'Be brief'},
            },
          ],
          'maxTokens': 50,
        },
      };

      // Act
      await chatService.processSamplingRequest(
        request: samplingRequest,
      );

      // Assert
      verify(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
        maxTokens: 50,
      )).called(1);
    });

    test('should omit maxTokens from OpenRouter request when not specified', () async {
      // Arrange
      final mockOpenRouterResponse = {
        'choices': [
          {
            'message': {'content': 'Response'},
            'finish_reason': 'stop',
          },
        ],
      };

      when(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
      )).thenAnswer((_) async => mockOpenRouterResponse);

      final samplingRequest = {
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'Test'},
            },
          ],
          // No maxTokens specified
        },
      };

      // Act
      await chatService.processSamplingRequest(
        request: samplingRequest,
      );

      // Assert: Should not pass maxTokens parameter
      verify(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
      )).called(1);

      // Verify maxTokens was not passed
      verifyNever(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
        maxTokens: anyNamed('maxTokens'),
      ));
    });

    test('should handle sampling with tools - initial request returns tool_use', () async {
      // Arrange: Mock OpenRouter response with tool_calls
      final mockOpenRouterResponse = {
        'choices': [
          {
            'message': {
              'tool_calls': [
                {
                  'id': 'call_abc123',
                  'type': 'function',
                  'function': {
                    'name': 'get_weather',
                    'arguments': '{"city": "Paris"}',
                  },
                },
                {
                  'id': 'call_def456',
                  'type': 'function',
                  'function': {
                    'name': 'get_weather',
                    'arguments': '{"city": "London"}',
                  },
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      };

      when(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
        tools: anyNamed('tools'),
        maxTokens: anyNamed('maxTokens'),
      )).thenAnswer((_) async => mockOpenRouterResponse);

      final samplingRequest = {
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {
                'type': 'text',
                'text': "What's the weather like in Paris and London?",
              },
            },
          ],
          'tools': [
            {
              'name': 'get_weather',
              'description': 'Get current weather for a city',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'city': {'type': 'string', 'description': 'City name'},
                },
                'required': ['city'],
              },
            },
          ],
          'maxTokens': 1000,
        },
      };

      // Act
      final response = await chatService.processSamplingRequest(
        request: samplingRequest,
        preferredModel: 'anthropic/claude-3-5-sonnet',
      );

      // Assert: Verify OpenRouter was called with tools
      verify(mockOpenRouterService.chatCompletion(
        model: 'anthropic/claude-3-5-sonnet',
        messages: anyNamed('messages'),
        tools: argThat(
          isA<List>().having((t) => t.length, 'length', 1),
          named: 'tools',
        ),
        maxTokens: 1000,
      )).called(1);

      // Assert: Response should contain tool_use content in MCP format
      expect(response['role'], equals('assistant'));
      expect(response['content'], isA<List>());
      final content = response['content'] as List;
      expect(content.length, equals(2));
      
      // First tool use
      expect(content[0]['type'], equals('tool_use'));
      expect(content[0]['id'], equals('call_abc123'));
      expect(content[0]['name'], equals('get_weather'));
      expect(content[0]['input'], equals({'city': 'Paris'}));
      
      // Second tool use
      expect(content[1]['type'], equals('tool_use'));
      expect(content[1]['id'], equals('call_def456'));
      expect(content[1]['name'], equals('get_weather'));
      expect(content[1]['input'], equals({'city': 'London'}));
      
      // Stop reason should be toolUse
      expect(response['stopReason'], equals('toolUse'));
    });

    test('should handle sampling with tools - follow-up with tool results', () async {
      // Arrange: Mock OpenRouter response with final text
      final mockOpenRouterResponse = {
        'choices': [
          {
            'message': {
              'content': 'Based on the current weather data:\n\n- **Paris**: 18°C and partly cloudy\n- **London**: 15°C and rainy',
            },
            'finish_reason': 'stop',
          },
        ],
      };

      when(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
        tools: anyNamed('tools'),
        maxTokens: anyNamed('maxTokens'),
      )).thenAnswer((_) async => mockOpenRouterResponse);

      final samplingRequest = {
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {
                'type': 'text',
                'text': "What's the weather like in Paris and London?",
              },
            },
            {
              'role': 'assistant',
              'content': [
                {
                  'type': 'tool_use',
                  'id': 'call_abc123',
                  'name': 'get_weather',
                  'input': {'city': 'Paris'},
                },
                {
                  'type': 'tool_use',
                  'id': 'call_def456',
                  'name': 'get_weather',
                  'input': {'city': 'London'},
                },
              ],
            },
            {
              'role': 'user',
              'content': [
                {
                  'type': 'tool_result',
                  'toolUseId': 'call_abc123',
                  'content': [
                    {
                      'type': 'text',
                      'text': 'Weather in Paris: 18°C, partly cloudy',
                    },
                  ],
                },
                {
                  'type': 'tool_result',
                  'toolUseId': 'call_def456',
                  'content': [
                    {
                      'type': 'text',
                      'text': 'Weather in London: 15°C, rainy',
                    },
                  ],
                },
              ],
            },
          ],
          'tools': [
            {
              'name': 'get_weather',
              'description': 'Get current weather for a city',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'city': {'type': 'string'},
                },
                'required': ['city'],
              },
            },
          ],
          'maxTokens': 1000,
        },
      };

      // Act
      final response = await chatService.processSamplingRequest(
        request: samplingRequest,
        preferredModel: 'anthropic/claude-3-5-sonnet',
      );

      // Assert: Response should contain final text
      expect(response['role'], equals('assistant'));
      expect(response['content']['type'], equals('text'));
      expect(response['content']['text'], contains('Paris'));
      expect(response['content']['text'], contains('London'));
      expect(response['stopReason'], equals('endTurn'));
    });

    test('should handle single tool_use as array', () async {
      // Arrange: Mock OpenRouter response with single tool_call
      final mockOpenRouterResponse = {
        'choices': [
          {
            'message': {
              'tool_calls': [
                {
                  'id': 'call_single',
                  'type': 'function',
                  'function': {
                    'name': 'get_weather',
                    'arguments': '{"city": "Tokyo"}',
                  },
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      };

      when(mockOpenRouterService.chatCompletion(
        model: anyNamed('model'),
        messages: anyNamed('messages'),
        tools: anyNamed('tools'),
      )).thenAnswer((_) async => mockOpenRouterResponse);

      final samplingRequest = {
        'params': {
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'What is the weather?'},
            },
          ],
          'tools': [
            {
              'name': 'get_weather',
              'description': 'Get weather',
              'inputSchema': {'type': 'object', 'properties': {}},
            },
          ],
        },
      };

      // Act
      final response = await chatService.processSamplingRequest(
        request: samplingRequest,
        preferredModel: 'anthropic/claude-3-5-sonnet',
      );

      // Assert: Even single tool_use should be an array
      expect(response['role'], equals('assistant'));
      expect(response['content'], isA<List>()); // Should be array
      final content = response['content'] as List;
      expect(content.length, equals(1));
      expect(content[0]['type'], equals('tool_use'));
      expect(content[0]['id'], equals('call_single'));
      expect(content[0]['name'], equals('get_weather'));
      expect(content[0]['input'], equals({'city': 'Tokyo'}));
      expect(response['stopReason'], equals('toolUse'));
    });
  });
}
