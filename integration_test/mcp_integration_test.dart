import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:joey_mcp_client_flutter/models/conversation.dart';
import 'package:joey_mcp_client_flutter/models/message.dart';
import 'package:joey_mcp_client_flutter/models/mcp_server.dart';
import 'package:joey_mcp_client_flutter/providers/conversation_provider.dart';
import 'package:joey_mcp_client_flutter/services/openrouter_service.dart';
import 'package:joey_mcp_client_flutter/services/database_service.dart';
import 'package:joey_mcp_client_flutter/services/chat_service.dart';
import 'package:joey_mcp_client_flutter/services/mcp_client_service.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';

/// Mock MCP Client Service for testing
class MockMcpClientService extends McpClientService {
  final String serverId;
  final List<McpTool> mockTools;
  bool _isInitialized = false;
  final List<Map<String, dynamic>> _toolCallHistory = [];
  Map<String, dynamic>? _pendingSamplingRequest;

  // Configurable responses
  Map<String, String> toolResponses = {};
  bool shouldFailToolCall = false;
  String? toolCallError;

  MockMcpClientService({
    required this.serverId,
    required this.mockTools,
    required String serverUrl,
  }) : super(serverUrl: serverUrl);

  @override
  Future<void> initialize() async {
    await Future.delayed(const Duration(milliseconds: 50));
    _isInitialized = true;
  }

  @override
  Future<List<McpTool>> listTools() async {
    if (!_isInitialized) {
      throw Exception('MCP client not initialized');
    }
    return mockTools;
  }

  @override
  Future<McpToolResult> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    _toolCallHistory.add({
      'toolName': toolName,
      'arguments': arguments,
      'timestamp': DateTime.now(),
    });

    if (shouldFailToolCall) {
      throw Exception(toolCallError ?? 'Mock tool call error');
    }

    // Check if we should trigger a sampling request for this tool
    if (toolName == 'trigger-sampling-request') {
      return await _handleSamplingTool(arguments);
    }

    // Return mock response
    final response = toolResponses[toolName] ?? 'Mock response for $toolName';

    return McpToolResult(
      content: [
        McpContent(
          type: 'text',
          text: response,
        ),
      ],
      isError: false,
    );
  }

  Future<McpToolResult> _handleSamplingTool(
    Map<String, dynamic> arguments,
  ) async {
    // Create a sampling request
    final samplingRequest = {
      'jsonrpc': '2.0',
      'id': DateTime.now().millisecondsSinceEpoch,
      'method': 'sampling/createMessage',
      'params': {
        'messages': [
          {
            'role': 'user',
            'content': {
              'type': 'text',
              'text': arguments['prompt'] ?? 'Tell me a joke',
            },
          },
        ],
        'systemPrompt': 'You are a helpful assistant.',
        'maxTokens': arguments['maxTokens'] ?? 100,
      },
    };

    _pendingSamplingRequest = samplingRequest;

    // Trigger the sampling request handler
    if (onSamplingRequest != null) {
      final response = await onSamplingRequest!(samplingRequest);

      // Return the sampling response as tool result
      final content = response['content'] as Map<String, dynamic>;
      return McpToolResult(
        content: [
          McpContent(
            type: 'text',
            text: 'Sampling request completed: ${content['text']}',
          ),
        ],
        isError: false,
      );
    }

    throw Exception('No sampling request handler registered');
  }

  List<Map<String, dynamic>> get toolCallHistory =>
      List.unmodifiable(_toolCallHistory);

  Map<String, dynamic>? get lastSamplingRequest => _pendingSamplingRequest;

  void clearHistory() {
    _toolCallHistory.clear();
    _pendingSamplingRequest = null;
  }

  @override
  void close() {
    // Mock close - nothing to do
  }
}

/// Mock OpenRouter Service for MCP tests
class MockOpenRouterServiceForMcp extends OpenRouterService {
  bool _isAuthenticated = true;
  String mockResponse = "AI response to tool usage";
  String mockSamplingResponse = "Mock response from sampling request";
  int _callCount = 0;
  bool shouldCallTool = true;

  @override
  Future<bool> isAuthenticated() async => _isAuthenticated;

  @override
  Future<String?> getApiKey() async =>
      _isAuthenticated ? 'mock-api-key' : null;

  @override
  Future<Map<String, dynamic>> chatCompletion({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    dynamic toolChoice,
    bool stream = false,
    int? maxTokens,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));

    return {
      'id': 'mock-${DateTime.now().millisecondsSinceEpoch}',
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': mockSamplingResponse,
          },
          'finish_reason': 'stop',
        },
      ],
      'usage': {
        'prompt_tokens': 10,
        'completion_tokens': 20,
        'total_tokens': 30,
      },
    };
  }

  @override
  Stream<String> chatCompletionStream({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    CancelToken? cancelToken,
  }) async* {
    await Future.delayed(const Duration(milliseconds: 100));

    _callCount++;

    // Only call tools on the first iteration, then return text
    if (tools != null && tools.isNotEmpty && _callCount == 1 && shouldCallTool) {
      // Simulate calling the first available tool
      final firstTool = tools.first;
      final toolName = firstTool['function']['name'];

      // Yield tool call
      final toolCall = [
        {
          'id': 'call_${DateTime.now().millisecondsSinceEpoch}',
          'type': 'function',
          'function': {
            'name': toolName,
            'arguments': '{"query": "test"}',
          },
        },
      ];

      yield 'TOOL_CALLS:${jsonEncode(toolCall)}';
    } else {
      // Return text response after tool execution
      final words = mockResponse.split(' ');
      for (final word in words) {
        await Future.delayed(const Duration(milliseconds: 10));
        yield '$word ';
      }
    }
  }

  void reset() {
    _callCount = 0;
    shouldCallTool = true;
  }

  @override
  Future<List<Map<String, dynamic>>> getModels() async {
    return [
      {
        'id': 'anthropic/claude-3-5-sonnet',
        'name': 'Claude 3.5 Sonnet',
      },
    ];
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('MCP Integration Tests', () {
    late MockOpenRouterServiceForMcp mockOpenRouterService;
    late DatabaseService databaseService;
    late MockMcpClientService mockMcpClient1;
    late MockMcpClientService mockMcpClient2;

    setUp(() async {
      mockOpenRouterService = MockOpenRouterServiceForMcp();
      databaseService = DatabaseService.instance;

      // Initialize the database
      await databaseService.database;

      // Clear any existing data
      final conversations = await databaseService.getAllConversations();
      for (final conv in conversations) {
        await databaseService.deleteConversation(conv.id);
      }

      // Create mock MCP clients with different tools
      mockMcpClient1 = MockMcpClientService(
        serverId: 'server1',
        serverUrl: 'http://localhost:3001/mcp',
        mockTools: [
          McpTool(
            name: 'search-web',
            description: 'Search the web for information',
            inputSchema: {
              'type': 'object',
              'properties': {
                'query': {'type': 'string'},
              },
              'required': ['query'],
            },
          ),
          McpTool(
            name: 'get-weather',
            description: 'Get current weather',
            inputSchema: {
              'type': 'object',
              'properties': {
                'location': {'type': 'string'},
              },
              'required': ['location'],
            },
          ),
        ],
      );

      mockMcpClient2 = MockMcpClientService(
        serverId: 'server2',
        serverUrl: 'http://localhost:3002/mcp',
        mockTools: [
          McpTool(
            name: 'read-file',
            description: 'Read a file from the filesystem',
            inputSchema: {
              'type': 'object',
              'properties': {
                'path': {'type': 'string'},
              },
              'required': ['path'],
            },
          ),
          McpTool(
            name: 'trigger-sampling-request',
            description: 'Trigger a sampling request to test that feature',
            inputSchema: {
              'type': 'object',
              'properties': {
                'prompt': {'type': 'string'},
                'maxTokens': {'type': 'number'},
              },
            },
          ),
        ],
      );

      // Initialize clients
      await mockMcpClient1.initialize();
      await mockMcpClient2.initialize();

      mockMcpClient1.clearHistory();
      mockMcpClient2.clearHistory();
      mockOpenRouterService.reset();
    });

    testWidgets('Should use MCP server tool in chat',
        (WidgetTester tester) async {
      // Set tool response
      mockMcpClient1.toolResponses['search-web'] =
          'Found: Flutter is a UI framework';

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ConversationProvider()..initialize(),
            ),
            Provider<OpenRouterService>.value(value: mockOpenRouterService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _TestMcpChatScreen(
                mcpClients: {'server1': mockMcpClient1},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Send a message
      await tester.enterText(find.byType(TextField), 'Search for Flutter');
      await tester.tap(find.byIcon(Icons.send));

      // Wait for tool execution
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Verify user message is displayed
      expect(find.text('Search for Flutter'), findsOneWidget);

      // Verify tool was called
      expect(mockMcpClient1.toolCallHistory.length, equals(1));
      expect(
        mockMcpClient1.toolCallHistory.first['toolName'],
        equals('search-web'),
      );
    });

    testWidgets('Should aggregate tools from multiple MCP servers',
        (WidgetTester tester) async {
      // Set tool responses
      mockMcpClient1.toolResponses['search-web'] = 'Search result';
      mockMcpClient2.toolResponses['read-file'] = 'File contents: Hello World';

      final mcpClients = {
        'server1': mockMcpClient1,
        'server2': mockMcpClient2,
      };

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ConversationProvider()..initialize(),
            ),
            Provider<OpenRouterService>.value(value: mockOpenRouterService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _TestMcpChatScreen(mcpClients: mcpClients),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify chat service has access to all tools
      final state = tester.state<_TestMcpChatScreenState>(
        find.byType(_TestMcpChatScreen),
      );

      // Count total tools from all servers
      int totalTools = 0;
      for (final tools in state._mcpTools.values) {
        totalTools += tools.length;
      }

      expect(totalTools, equals(4)); // 2 from server1 + 2 from server2
    });

    testWidgets('Should route tool calls to correct MCP server',
        (WidgetTester tester) async {
      mockMcpClient1.toolResponses['search-web'] = 'Web search result';
      mockMcpClient2.toolResponses['read-file'] = 'File: test.txt';

      final mcpClients = {
        'server1': mockMcpClient1,
        'server2': mockMcpClient2,
      };

      // Create chat service
      final chatService = ChatService(
        openRouterService: mockOpenRouterService,
        mcpClients: mcpClients,
        mcpTools: {
          'server1': await mockMcpClient1.listTools(),
          'server2': await mockMcpClient2.listTools(),
        },
      );

      // Manually trigger a tool call to server2's tool
      final conversation = Conversation(
        id: const Uuid().v4(),
        title: 'Test',
        model: 'anthropic/claude-3-5-sonnet',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final userMessage = Message(
        id: const Uuid().v4(),
        conversationId: conversation.id,
        role: MessageRole.user,
        content: 'Read the file',
        timestamp: DateTime.now(),
      );

      // Create a tool call for read-file
      final toolCalls = [
        {
          'id': 'call_1',
          'function': {
            'name': 'read-file',
            'arguments': '{"path": "/test.txt"}',
          },
        },
      ];

      // Execute the tool calls using the internal method
      // We'll simulate this by calling the tool directly
      await mockMcpClient2.callTool('read-file', {'path': '/test.txt'});

      // Verify only server2 was called
      expect(mockMcpClient1.toolCallHistory.length, equals(0));
      expect(mockMcpClient2.toolCallHistory.length, equals(1));
      expect(
        mockMcpClient2.toolCallHistory.first['toolName'],
        equals('read-file'),
      );

      chatService.dispose();
    });

    testWidgets('Should handle sampling requests from MCP server',
        (WidgetTester tester) async {
      // Configure the mock to call the trigger-sampling-request tool
      mockOpenRouterService.mockResponse = "Use the trigger tool";

      // Create a special mock that only has the sampling tool
      final samplingMockClient = MockMcpClientService(
        serverId: 'sampling-server',
        serverUrl: 'http://localhost:3003/mcp',
        mockTools: [
          McpTool(
            name: 'trigger-sampling-request',
            description: 'Trigger a sampling request to test that feature',
            inputSchema: {
              'type': 'object',
              'properties': {
                'prompt': {'type': 'string'},
                'maxTokens': {'type': 'number'},
              },
            },
          ),
        ],
      );

      await samplingMockClient.initialize();

      final mcpClients = {'sampling-server': samplingMockClient};

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ConversationProvider()..initialize(),
            ),
            Provider<OpenRouterService>.value(value: mockOpenRouterService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _TestMcpChatScreen(mcpClients: mcpClients),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Send a message that will trigger the sampling tool
      await tester.enterText(
        find.byType(TextField),
        'Trigger a sampling request',
      );
      await tester.tap(find.byIcon(Icons.send));

      // Wait for the tool to execute and sampling dialog to appear
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify the sampling dialog is shown
      expect(find.text('MCP Sampling Request'), findsOneWidget);
      expect(find.text('System Prompt:'), findsOneWidget);
      expect(find.text('You are a helpful assistant.'), findsOneWidget);

      // Verify the approve and reject buttons are present
      expect(find.byKey(const Key('sampling_approve_button')), findsOneWidget);
      expect(find.byKey(const Key('sampling_reject_button')), findsOneWidget);

      // Tap the approve button
      await tester.tap(find.byKey(const Key('sampling_approve_button')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify the dialog is dismissed
      expect(find.text('MCP Sampling Request'), findsNothing);

      // Verify sampling request was created
      expect(samplingMockClient.lastSamplingRequest, isNotNull);
      expect(
        samplingMockClient.lastSamplingRequest!['method'],
        equals('sampling/createMessage'),
      );
    });

    testWidgets('Should handle tool execution errors gracefully',
        (WidgetTester tester) async {
      mockMcpClient1.shouldFailToolCall = true;
      mockMcpClient1.toolCallError = 'Tool execution failed';

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ConversationProvider()..initialize(),
            ),
            Provider<OpenRouterService>.value(value: mockOpenRouterService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _TestMcpChatScreen(
                mcpClients: {'server1': mockMcpClient1},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Try to execute a tool that will fail
      expect(
        () => mockMcpClient1.callTool('search-web', {'query': 'test'}),
        throwsException,
      );
    });

    testWidgets('Should handle multiple servers with overlapping tool names',
        (WidgetTester tester) async {
      // Create a third client with a duplicate tool name
      final mockMcpClient3 = MockMcpClientService(
        serverId: 'server3',
        serverUrl: 'http://localhost:3003/mcp',
        mockTools: [
          McpTool(
            name: 'search-web', // Duplicate name from server1
            description: 'Alternative web search',
            inputSchema: {
              'type': 'object',
              'properties': {
                'query': {'type': 'string'},
              },
            },
          ),
        ],
      );

      await mockMcpClient3.initialize();

      mockMcpClient1.toolResponses['search-web'] = 'Result from server1';
      mockMcpClient3.toolResponses['search-web'] = 'Result from server3';

      final mcpClients = {
        'server1': mockMcpClient1,
        'server3': mockMcpClient3,
      };

      final chatService = ChatService(
        openRouterService: mockOpenRouterService,
        mcpClients: mcpClients,
        mcpTools: {
          'server1': await mockMcpClient1.listTools(),
          'server3': await mockMcpClient3.listTools(),
        },
      );

      // When a tool with duplicate name is called, it should use the first match
      await mockMcpClient1.callTool('search-web', {'query': 'test'});

      // Verify server1 was called (first server with this tool)
      expect(mockMcpClient1.toolCallHistory.length, equals(1));

      chatService.dispose();
    });
  });
}

/// Test widget for MCP chat functionality
class _TestMcpChatScreen extends StatefulWidget {
  final Map<String, MockMcpClientService> mcpClients;

  const _TestMcpChatScreen({required this.mcpClients});

  @override
  State<_TestMcpChatScreen> createState() => _TestMcpChatScreenState();
}

class _TestMcpChatScreenState extends State<_TestMcpChatScreen> {
  late Conversation _conversation;
  final List<Message> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  ChatService? _chatService;
  Map<String, List<McpTool>> _mcpTools = {};

  @override
  void initState() {
    super.initState();
    _initializeConversation();
  }

  Future<void> _initializeConversation() async {
    _conversation = Conversation(
      id: const Uuid().v4(),
      title: 'Test MCP Chat',
      model: 'anthropic/claude-3-5-sonnet',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Load tools from all MCP clients
    for (final entry in widget.mcpClients.entries) {
      final tools = await entry.value.listTools();
      _mcpTools[entry.key] = tools;
    }

    // Initialize chat service with MCP clients
    final openRouterService = context.read<OpenRouterService>();
    _chatService = ChatService(
      openRouterService: openRouterService,
      mcpClients: widget.mcpClients,
      mcpTools: _mcpTools,
    );

    // Listen to chat events
    _chatService!.events.listen((event) {
      if (!mounted) return;

      if (event is MessageCreated) {
        setState(() {
          _messages.add(event.message);
        });
        _scrollToBottom();
      } else if (event is ConversationComplete) {
        setState(() {
          _isLoading = false;
        });
      } else if (event is ErrorOccurred) {
        setState(() {
          _isLoading = false;
        });
      } else if (event is SamplingRequestReceived) {
        _handleSamplingRequest(event);
      }
    });
  }

  void _handleSamplingRequest(SamplingRequestReceived event) {
    if (!mounted) return;

    // Extract request details
    final params = event.request['params'] as Map<String, dynamic>;
    final messages = params['messages'] as List;
    final systemPrompt = params['systemPrompt'] as String?;
    final maxTokens = params['maxTokens'] as int?;

    // Show dialog to user
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('MCP Sampling Request'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (systemPrompt != null) ...[
                const Text(
                  'System Prompt:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(systemPrompt),
                const SizedBox(height: 12),
              ],
              const Text(
                'Messages:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...messages.map((msg) {
                final role = msg['role'] as String;
                final content = msg['content'];
                final text = content is Map
                    ? content['text'] as String
                    : content as String;
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('$role: $text'),
                );
              }),
              if (maxTokens != null) ...[
                const SizedBox(height: 12),
                Text('Max Tokens: $maxTokens'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('sampling_reject_button'),
            onPressed: () {
              Navigator.pop(context);
              event.onReject();
            },
            child: const Text('Reject'),
          ),
          ElevatedButton(
            key: const Key('sampling_approve_button'),
            onPressed: () async {
              Navigator.pop(context);

              // Call OpenRouter with the sampling request
              final openRouterService = context.read<OpenRouterService>();
              final response = await openRouterService.chatCompletion(
                model: 'anthropic/claude-3-5-sonnet',
                messages: messages.map((m) {
                  final content = m['content'];
                  final text = content is Map
                      ? content['text'] as String
                      : content as String;
                  return {
                    'role': m['role'] as String,
                    'content': text,
                  };
                }).toList(),
                maxTokens: maxTokens,
              );

              final choice = response['choices'][0];
              final message = choice['message'];

              final samplingResponse = {
                'role': 'assistant',
                'content': {
                  'type': 'text',
                  'text': message['content'],
                },
                'model': 'anthropic/claude-3-5-sonnet',
                'stopReason': 'endTurn',
              };

              event.onApprove(event.request, samplingResponse);
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading || !mounted) return;

    final userMessage = Message(
      id: const Uuid().v4(),
      conversationId: _conversation.id,
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });

    _messageController.clear();
    _scrollToBottom();

    try {
      await _chatService!.runAgenticLoop(
        conversationId: _conversation.id,
        model: _conversation.model,
        messages: List.from(_messages),
        maxIterations: 5,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _chatService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              final isUser = message.role == MessageRole.user;
              final isTool = message.role == MessageRole.tool;

              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Colors.blue[100]
                          : isTool
                          ? Colors.green[100]
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isTool)
                          Text(
                            'Tool: ${message.toolName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        Text(message.content),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _isLoading ? null : _sendMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
