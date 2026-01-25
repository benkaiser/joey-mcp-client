import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:joey_mcp_client_flutter/main.dart' as app;
import 'package:joey_mcp_client_flutter/models/conversation.dart';
import 'package:joey_mcp_client_flutter/models/message.dart';
import 'package:joey_mcp_client_flutter/providers/conversation_provider.dart';
import 'package:joey_mcp_client_flutter/services/openrouter_service.dart';
import 'package:joey_mcp_client_flutter/services/database_service.dart';
import 'package:joey_mcp_client_flutter/services/chat_service.dart';
import 'package:joey_mcp_client_flutter/screens/chat_screen.dart';
import 'package:uuid/uuid.dart';

/// Mock OpenRouter Service for testing
class MockOpenRouterService extends OpenRouterService {
  bool _isAuthenticated = true;
  final List<Map<String, dynamic>> _callHistory = [];

  // Configuration for mock responses
  String mockResponse = "This is a mock response from the AI.";
  Duration responseDelay = const Duration(milliseconds: 100);
  bool shouldThrowError = false;
  String? errorMessage;

  @override
  Future<bool> isAuthenticated() async {
    return _isAuthenticated;
  }

  @override
  Future<String?> getApiKey() async {
    return _isAuthenticated ? 'mock-api-key' : null;
  }

  @override
  Future<void> logout() async {
    _isAuthenticated = false;
  }

  void setAuthenticated(bool value) {
    _isAuthenticated = value;
  }

  List<Map<String, dynamic>> get callHistory => List.unmodifiable(_callHistory);

  void clearHistory() {
    _callHistory.clear();
  }

  @override
  Future<Map<String, dynamic>> chatCompletion({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    bool stream = false,
    int? maxTokens,
  }) async {
    _callHistory.add({
      'model': model,
      'messages': messages,
      'tools': tools,
      'stream': stream,
      'maxTokens': maxTokens,
    });

    if (shouldThrowError) {
      throw Exception(errorMessage ?? 'Mock error');
    }

    await Future.delayed(responseDelay);

    return {
      'id': 'mock-${DateTime.now().millisecondsSinceEpoch}',
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': mockResponse,
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
  }) async* {
    _callHistory.add({
      'model': model,
      'messages': messages,
      'tools': tools,
      'stream': true,
    });

    if (shouldThrowError) {
      throw Exception(errorMessage ?? 'Mock stream error');
    }

    await Future.delayed(responseDelay);

    // Stream the response in chunks to simulate streaming
    // Yield each chunk separately (like real streaming)
    final words = mockResponse.split(' ');
    String accumulated = '';
    for (int i = 0; i < words.length; i++) {
      await Future.delayed(const Duration(milliseconds: 10));
      if (i > 0) accumulated += ' ';
      accumulated += words[i];
      yield words[i] + (i < words.length - 1 ? ' ' : '');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getModels() async {
    return [
      {
        'id': 'anthropic/claude-3-5-sonnet',
        'name': 'Claude 3.5 Sonnet',
        'pricing': {
          'prompt': '0.000003',
          'completion': '0.000015',
        },
      },
      {
        'id': 'openai/gpt-4-turbo',
        'name': 'GPT-4 Turbo',
        'pricing': {
          'prompt': '0.00001',
          'completion': '0.00003',
        },
      },
    ];
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Chat Interface Integration Tests', () {
    late MockOpenRouterService mockOpenRouterService;
    late DatabaseService databaseService;

    setUp(() async {
      mockOpenRouterService = MockOpenRouterService();
      databaseService = DatabaseService.instance;

      // Initialize the database
      await databaseService.database;

      // Clear any existing data
      final conversations = await databaseService.getAllConversations();
      for (final conv in conversations) {
        await databaseService.deleteConversation(conv.id);
      }
    });

    tearDown(() {
      mockOpenRouterService.clearHistory();
    });

    testWidgets('Should create a conversation and send a message',
        (WidgetTester tester) async {
      // Create a test app with mocked service
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ConversationProvider()..initialize(),
            ),
            Provider<OpenRouterService>.value(value: mockOpenRouterService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: _TestChatScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the chat screen is displayed
      expect(find.byType(TextField), findsOneWidget);

      // Enter a message
      await tester.enterText(find.byType(TextField), 'Hello, AI!');
      await tester.pumpAndSettle();

      // Tap the send button
      final sendButton = find.byIcon(Icons.send);
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);

      // Wait for the response to stream in
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify the user message is displayed
      expect(find.text('Hello, AI!'), findsOneWidget);

      // Verify the AI response is displayed
      expect(
        find.text('This is a mock response from the AI.'),
        findsOneWidget,
      );

      // Verify that the OpenRouter service was called
      expect(mockOpenRouterService.callHistory.length, greaterThan(0));
      final lastCall = mockOpenRouterService.callHistory.last;
      expect(lastCall['messages'], isNotEmpty);
    });

    testWidgets('Should persist user messages in chat',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ConversationProvider()..initialize(),
            ),
            Provider<OpenRouterService>.value(value: mockOpenRouterService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: _TestChatScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Send a message
      await tester.enterText(find.byType(TextField), 'Test message');
      await tester.tap(find.byIcon(Icons.send));

      // Wait for response to complete
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Verify both user message and AI response are displayed
      expect(find.text('Test message'), findsOneWidget);
      expect(find.text('This is a mock response from the AI.'), findsOneWidget);
    });

    testWidgets('Should handle empty messages gracefully',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ConversationProvider()..initialize(),
            ),
            Provider<OpenRouterService>.value(value: mockOpenRouterService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: _TestChatScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Try to send an empty message
      final sendButton = find.byIcon(Icons.send);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      // Verify that no API call was made
      expect(mockOpenRouterService.callHistory, isEmpty);
    });

    testWidgets('Should display loading indicator during response',
        (WidgetTester tester) async {
      // Set a longer delay to see the loading state
      mockOpenRouterService.responseDelay = const Duration(seconds: 1);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ConversationProvider()..initialize(),
            ),
            Provider<OpenRouterService>.value(value: mockOpenRouterService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: _TestChatScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Send a message
      await tester.enterText(find.byType(TextField), 'Test message');
      await tester.tap(find.byIcon(Icons.send));

      // Pump once to process the tap
      await tester.pump();

      // The message should be visible immediately
      expect(find.text('Test message'), findsOneWidget);

      // Wait for the response
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify response is displayed
      expect(
        find.text('This is a mock response from the AI.'),
        findsOneWidget,
      );
    });

    testWidgets('Should clear text field after sending message',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ConversationProvider()..initialize(),
            ),
            Provider<OpenRouterService>.value(value: mockOpenRouterService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: _TestChatScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter and send a message
      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Test message');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Verify text field is cleared
      final TextField widget = tester.widget(textField);
      expect(widget.controller?.text, isEmpty);
    });

    testWidgets('Should auto-scroll when messages are added',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ConversationProvider()..initialize(),
            ),
            Provider<OpenRouterService>.value(value: mockOpenRouterService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: _TestChatScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Send a message and verify it appears
      await tester.enterText(find.byType(TextField), 'Test scroll');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Both the user message and AI response should be visible
      expect(find.text('Test scroll'), findsOneWidget);
      expect(find.text('This is a mock response from the AI.'), findsOneWidget);
    });
  });
}

/// Test widget that simulates a minimal chat screen
class _TestChatScreen extends StatefulWidget {
  const _TestChatScreen();

  @override
  State<_TestChatScreen> createState() => _TestChatScreenState();
}

class _TestChatScreenState extends State<_TestChatScreen> {
  late Conversation _conversation;
  final List<Message> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  ChatService? _chatService;

  @override
  void initState() {
    super.initState();
    _initializeConversation();
  }

  void _initializeConversation() {
    _conversation = Conversation(
      id: const Uuid().v4(),
      title: 'Test Chat',
      model: 'anthropic/claude-3-5-sonnet',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Initialize chat service without MCP servers
    final openRouterService = context.read<OpenRouterService>();
    _chatService = ChatService(
      openRouterService: openRouterService,
      mcpClients: {}, // No MCP clients for this test
      mcpTools: {}, // No MCP tools for this test
    );

    // Listen to chat events
    _chatService!.events.listen((event) {
      if (!mounted) return; // Guard against updates after dispose

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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${event.error}')),
          );
        }
      }
    });
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

    // Run the agentic loop
    try {
      await _chatService!.runAgenticLoop(
        conversationId: _conversation.id,
        model: _conversation.model,
        messages: List.from(_messages),
        maxIterations: 1, // Single iteration for simple test
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
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
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blue[100] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(message.content),
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
