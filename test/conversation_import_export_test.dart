import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:joey_mcp_client_flutter/models/conversation.dart';
import 'package:joey_mcp_client_flutter/models/message.dart';
import 'package:joey_mcp_client_flutter/providers/conversation_provider.dart';
import 'package:joey_mcp_client_flutter/services/conversation_import_export_service.dart';
import 'package:joey_mcp_client_flutter/services/database_service.dart';

/// Helper to clear all data from the shared in-memory database between tests.
Future<void> _clearDatabase() async {
  final db = await DatabaseService.instance.database;
  await db.delete('messages');
  await db.delete('conversations');
}

void main() {
  // Use an in-memory SQLite database so provider calls don't hit the file system.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // Clean DB state between tests so no data leaks across tests.
  setUp(() async {
    await _clearDatabase();
  });

  group('Export format', () {
    test('exportSingleConversation produces valid envelope', () {
      final conversation = Conversation(
        id: 'conv-1',
        title: 'Test Chat',
        model: 'anthropic/claude-3-5-sonnet',
        createdAt: DateTime.utc(2025, 1, 1),
        updatedAt: DateTime.utc(2025, 1, 2),
      );

      final messages = [
        Message(
          id: 'msg-1',
          conversationId: 'conv-1',
          role: MessageRole.user,
          content: 'Hello',
          timestamp: DateTime.utc(2025, 1, 1, 10, 0),
        ),
        Message(
          id: 'msg-2',
          conversationId: 'conv-1',
          role: MessageRole.assistant,
          content: 'Hi there!',
          timestamp: DateTime.utc(2025, 1, 1, 10, 1),
        ),
      ];

      final jsonString = ConversationImportExportService.exportSingleConversation(
        conversation,
        messages,
      );
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      expect(data['version'], equals(1));
      expect(data['appName'], equals('joey-mcp-client'));
      expect(data['exportedAt'], isNotNull);
      // Verify exportedAt is valid ISO8601
      expect(() => DateTime.parse(data['exportedAt']), returnsNormally);

      final conversations = data['conversations'] as List;
      expect(conversations.length, equals(1));

      final conv = conversations[0] as Map<String, dynamic>;
      expect(conv['title'], equals('Test Chat'));
      expect(conv['model'], equals('anthropic/claude-3-5-sonnet'));

      final msgs = conv['messages'] as List;
      expect(msgs.length, equals(2));
      expect(msgs[0]['role'], equals('user'));
      expect(msgs[0]['content'], equals('Hello'));
      expect(msgs[1]['role'], equals('assistant'));
      expect(msgs[1]['content'], equals('Hi there!'));
    });

    test('exportSingleConversation preserves all message fields', () {
      final conversation = Conversation(
        id: 'conv-1',
        title: 'Tool Chat',
        model: 'openai/gpt-4',
        createdAt: DateTime.utc(2025, 1, 1),
        updatedAt: DateTime.utc(2025, 1, 1),
      );

      final messages = [
        Message(
          id: 'msg-1',
          conversationId: 'conv-1',
          role: MessageRole.assistant,
          content: 'Let me look that up.',
          timestamp: DateTime.utc(2025, 1, 1, 10, 0),
          reasoning: 'I should use the search tool.',
          toolCallData: '[{"id":"tc-1","type":"function","function":{"name":"search","arguments":"{}"}}]',
        ),
        Message(
          id: 'msg-2',
          conversationId: 'conv-1',
          role: MessageRole.tool,
          content: '{"result": "found"}',
          timestamp: DateTime.utc(2025, 1, 1, 10, 1),
          toolCallId: 'tc-1',
          toolName: 'search',
        ),
        Message(
          id: 'msg-3',
          conversationId: 'conv-1',
          role: MessageRole.user,
          content: 'Check this image',
          timestamp: DateTime.utc(2025, 1, 1, 10, 2),
          imageData: '[{"data":"abc123","mimeType":"image/png"}]',
        ),
      ];

      final jsonString = ConversationImportExportService.exportSingleConversation(
        conversation,
        messages,
      );
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final msgs = (data['conversations'][0]['messages'] as List);

      // Assistant message with reasoning and tool calls
      expect(msgs[0]['reasoning'], equals('I should use the search tool.'));
      expect(msgs[0]['toolCallData'], isNotNull);

      // Tool result message
      expect(msgs[1]['role'], equals('tool'));
      expect(msgs[1]['toolCallId'], equals('tc-1'));
      expect(msgs[1]['toolName'], equals('search'));

      // User message with image data
      expect(msgs[2]['imageData'], contains('abc123'));
    });

    test('exportSingleConversation with empty messages', () {
      final conversation = Conversation(
        id: 'conv-1',
        title: 'Empty Chat',
        model: 'some-model',
        createdAt: DateTime.utc(2025, 1, 1),
        updatedAt: DateTime.utc(2025, 1, 1),
      );

      final jsonString = ConversationImportExportService.exportSingleConversation(
        conversation,
        [],
      );
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final msgs = (data['conversations'][0]['messages'] as List);
      expect(msgs, isEmpty);
    });
  });

  group('Export all conversations', () {
    test('exportAllConversations includes all conversations with messages', () async {
      final provider = ConversationProvider();
      await provider.initialize();

      // Create two conversations
      final conv1 = await provider.createConversation(
        title: 'Chat 1',
        model: 'model-a',
      );
      final conv2 = await provider.createConversation(
        title: 'Chat 2',
        model: 'model-b',
      );

      // Add messages
      await provider.addMessage(Message(
        id: 'msg-1',
        conversationId: conv1.id,
        role: MessageRole.user,
        content: 'Hello from chat 1',
        timestamp: DateTime.now(),
      ));
      await provider.addMessage(Message(
        id: 'msg-2',
        conversationId: conv2.id,
        role: MessageRole.user,
        content: 'Hello from chat 2',
        timestamp: DateTime.now(),
      ));

      final jsonString = await ConversationImportExportService.exportAllConversations(provider);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      expect(data['version'], equals(1));
      final conversations = data['conversations'] as List;
      expect(conversations.length, equals(2));

      // Verify both conversations have their messages
      for (final conv in conversations) {
        final msgs = (conv as Map<String, dynamic>)['messages'] as List;
        expect(msgs.length, equals(1));
      }
    });
  });

  group('Import', () {
    test('importConversations creates conversations with new UUIDs', () async {
      final provider = ConversationProvider();
      await provider.initialize();

      final exportJson = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'appName': 'joey-mcp-client',
        'conversations': [
          {
            'id': 'original-conv-id',
            'title': 'Imported Chat',
            'model': 'anthropic/claude-3-5-sonnet',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'updatedAt': '2025-01-02T00:00:00.000Z',
            'messages': [
              {
                'id': 'original-msg-id',
                'conversationId': 'original-conv-id',
                'role': 'user',
                'content': 'Hello',
                'timestamp': '2025-01-01T10:00:00.000Z',
              },
            ],
          },
        ],
      });

      final result = await ConversationImportExportService.importConversations(
        exportJson,
        provider,
      );

      expect(result.imported, equals(1));
      expect(result.skipped, equals(0));

      // Conversation should exist with a new ID
      expect(provider.conversations.length, equals(1));
      expect(provider.conversations[0].id, isNot(equals('original-conv-id')));
      expect(provider.conversations[0].title, equals('Imported Chat'));
      expect(provider.conversations[0].model, equals('anthropic/claude-3-5-sonnet'));

      // Messages should be remapped to the new conversation ID
      final messages = provider.getMessages(provider.conversations[0].id);
      expect(messages.length, equals(1));
      expect(messages[0].id, isNot(equals('original-msg-id')));
      expect(messages[0].conversationId, equals(provider.conversations[0].id));
      expect(messages[0].content, equals('Hello'));
    });

    test('importConversations preserves conversation order', () async {
      final provider = ConversationProvider();
      await provider.initialize();

      final exportJson = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'appName': 'joey-mcp-client',
        'conversations': [
          {
            'id': 'conv-a',
            'title': 'First Chat',
            'model': 'model-a',
            'createdAt': '2025-01-03T00:00:00.000Z',
            'updatedAt': '2025-01-03T00:00:00.000Z',
            'messages': [
              {
                'id': 'msg-a',
                'conversationId': 'conv-a',
                'role': 'user',
                'content': 'A',
                'timestamp': '2025-01-03T10:00:00.000Z',
              },
            ],
          },
          {
            'id': 'conv-b',
            'title': 'Second Chat',
            'model': 'model-b',
            'createdAt': '2025-01-02T00:00:00.000Z',
            'updatedAt': '2025-01-02T00:00:00.000Z',
            'messages': [
              {
                'id': 'msg-b',
                'conversationId': 'conv-b',
                'role': 'user',
                'content': 'B',
                'timestamp': '2025-01-02T10:00:00.000Z',
              },
            ],
          },
          {
            'id': 'conv-c',
            'title': 'Third Chat',
            'model': 'model-c',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'updatedAt': '2025-01-01T00:00:00.000Z',
            'messages': [
              {
                'id': 'msg-c',
                'conversationId': 'conv-c',
                'role': 'user',
                'content': 'C',
                'timestamp': '2025-01-01T10:00:00.000Z',
              },
            ],
          },
        ],
      });

      final result = await ConversationImportExportService.importConversations(
        exportJson,
        provider,
      );

      expect(result.imported, equals(3));

      // Order should be preserved: First, Second, Third
      expect(provider.conversations[0].title, equals('First Chat'));
      expect(provider.conversations[1].title, equals('Second Chat'));
      expect(provider.conversations[2].title, equals('Third Chat'));
    });

    test('importConversations handles multiple imports without collision', () async {
      final provider = ConversationProvider();
      await provider.initialize();

      final exportJson = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'appName': 'joey-mcp-client',
        'conversations': [
          {
            'id': 'conv-1',
            'title': 'Chat',
            'model': 'model-a',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'updatedAt': '2025-01-01T00:00:00.000Z',
            'messages': [],
          },
        ],
      });

      // Import same file twice
      await ConversationImportExportService.importConversations(exportJson, provider);
      await ConversationImportExportService.importConversations(exportJson, provider);

      // Should have two conversations with different IDs
      expect(provider.conversations.length, equals(2));
      expect(
        provider.conversations[0].id,
        isNot(equals(provider.conversations[1].id)),
      );
    });

    test('importConversations preserves all message fields', () async {
      final provider = ConversationProvider();
      await provider.initialize();

      final exportJson = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'appName': 'joey-mcp-client',
        'conversations': [
          {
            'id': 'conv-1',
            'title': 'Full Chat',
            'model': 'model-a',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'updatedAt': '2025-01-01T00:00:00.000Z',
            'messages': [
              {
                'id': 'msg-1',
                'conversationId': 'conv-1',
                'role': 'assistant',
                'content': 'Let me search.',
                'timestamp': '2025-01-01T10:00:00.000Z',
                'reasoning': 'User wants info.',
                'toolCallData': '[{"id":"tc-1"}]',
              },
              {
                'id': 'msg-2',
                'conversationId': 'conv-1',
                'role': 'tool',
                'content': '{"result":"ok"}',
                'timestamp': '2025-01-01T10:01:00.000Z',
                'toolCallId': 'tc-1',
                'toolName': 'search',
              },
              {
                'id': 'msg-3',
                'conversationId': 'conv-1',
                'role': 'user',
                'content': 'See this',
                'timestamp': '2025-01-01T10:02:00.000Z',
                'imageData': '[{"data":"base64img","mimeType":"image/png"}]',
                'audioData': '[{"data":"base64aud","mimeType":"audio/wav"}]',
              },
            ],
          },
        ],
      });

      await ConversationImportExportService.importConversations(exportJson, provider);

      final messages = provider.getMessages(provider.conversations[0].id);
      expect(messages.length, equals(3));

      // Assistant with reasoning and tool calls
      expect(messages[0].role, equals(MessageRole.assistant));
      expect(messages[0].reasoning, equals('User wants info.'));
      expect(messages[0].toolCallData, equals('[{"id":"tc-1"}]'));

      // Tool result
      expect(messages[1].role, equals(MessageRole.tool));
      expect(messages[1].toolCallId, equals('tc-1'));
      expect(messages[1].toolName, equals('search'));

      // User with image and audio
      expect(messages[2].role, equals(MessageRole.user));
      expect(messages[2].imageData, contains('base64img'));
      expect(messages[2].audioData, contains('base64aud'));
    });

    test('importConversations rejects unsupported version', () async {
      final provider = ConversationProvider();
      await provider.initialize();

      final exportJson = jsonEncode({
        'version': 99,
        'exportedAt': DateTime.now().toIso8601String(),
        'appName': 'joey-mcp-client',
        'conversations': [],
      });

      expect(
        () => ConversationImportExportService.importConversations(exportJson, provider),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported export version'),
        )),
      );
    });

    test('importConversations rejects missing conversations key', () async {
      final provider = ConversationProvider();
      await provider.initialize();

      final exportJson = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'appName': 'joey-mcp-client',
      });

      expect(
        () => ConversationImportExportService.importConversations(exportJson, provider),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('No conversations found'),
        )),
      );
    });

    test('importConversations skips malformed conversations and counts them', () async {
      final provider = ConversationProvider();
      await provider.initialize();

      final exportJson = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'appName': 'joey-mcp-client',
        'conversations': [
          {
            'id': 'conv-good',
            'title': 'Good Chat',
            'model': 'model-a',
            'createdAt': '2025-01-01T00:00:00.000Z',
            'updatedAt': '2025-01-01T00:00:00.000Z',
            'messages': [],
          },
          {
            // Missing required fields — should be skipped
            'title': 'Bad Chat',
          },
        ],
      });

      final result = await ConversationImportExportService.importConversations(
        exportJson,
        provider,
      );

      expect(result.imported, equals(1));
      expect(result.skipped, equals(1));
      expect(provider.conversations.length, equals(1));
      expect(provider.conversations[0].title, equals('Good Chat'));
    });

    test('importConversations handles empty conversations list', () async {
      final provider = ConversationProvider();
      await provider.initialize();

      final exportJson = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'appName': 'joey-mcp-client',
        'conversations': [],
      });

      final result = await ConversationImportExportService.importConversations(
        exportJson,
        provider,
      );

      expect(result.imported, equals(0));
      expect(result.skipped, equals(0));
    });
  });

  group('Round-trip (export then import)', () {
    test('export then import preserves conversation data', () async {
      // Set up source provider with conversations
      final sourceProvider = ConversationProvider();
      await sourceProvider.initialize();

      final conv = await sourceProvider.createConversation(
        title: 'Round Trip Chat',
        model: 'anthropic/claude-3-5-sonnet',
      );

      await sourceProvider.addMessage(Message(
        id: 'msg-1',
        conversationId: conv.id,
        role: MessageRole.user,
        content: 'What is the weather?',
        timestamp: DateTime.utc(2025, 6, 15, 10, 0),
      ));
      await sourceProvider.addMessage(Message(
        id: 'msg-2',
        conversationId: conv.id,
        role: MessageRole.assistant,
        content: 'Let me check that for you.',
        timestamp: DateTime.utc(2025, 6, 15, 10, 1),
        reasoning: 'User wants weather info.',
        toolCallData: '[{"id":"tc-1","type":"function","function":{"name":"get_weather","arguments":"{}"}}]',
      ));
      await sourceProvider.addMessage(Message(
        id: 'msg-3',
        conversationId: conv.id,
        role: MessageRole.tool,
        content: '{"temp": 72, "conditions": "sunny"}',
        timestamp: DateTime.utc(2025, 6, 15, 10, 2),
        toolCallId: 'tc-1',
        toolName: 'get_weather',
      ));
      await sourceProvider.addMessage(Message(
        id: 'msg-4',
        conversationId: conv.id,
        role: MessageRole.assistant,
        content: 'It is 72F and sunny!',
        timestamp: DateTime.utc(2025, 6, 15, 10, 3),
      ));

      // Export
      final jsonString = await ConversationImportExportService.exportAllConversations(
        sourceProvider,
      );

      // Clear DB to simulate a fresh install
      await _clearDatabase();

      // Import into a fresh provider
      final destProvider = ConversationProvider();
      await destProvider.initialize();

      final result = await ConversationImportExportService.importConversations(
        jsonString,
        destProvider,
      );

      expect(result.imported, equals(1));
      expect(result.skipped, equals(0));

      // Verify conversation
      final importedConv = destProvider.conversations[0];
      expect(importedConv.title, equals('Round Trip Chat'));
      expect(importedConv.model, equals('anthropic/claude-3-5-sonnet'));
      expect(importedConv.id, isNot(equals(conv.id))); // New UUID

      // Verify messages
      final importedMessages = destProvider.getMessages(importedConv.id);
      expect(importedMessages.length, equals(4));

      expect(importedMessages[0].role, equals(MessageRole.user));
      expect(importedMessages[0].content, equals('What is the weather?'));

      expect(importedMessages[1].role, equals(MessageRole.assistant));
      expect(importedMessages[1].content, equals('Let me check that for you.'));
      expect(importedMessages[1].reasoning, equals('User wants weather info.'));
      expect(importedMessages[1].toolCallData, isNotNull);

      expect(importedMessages[2].role, equals(MessageRole.tool));
      expect(importedMessages[2].toolName, equals('get_weather'));
      expect(importedMessages[2].toolCallId, equals('tc-1'));

      expect(importedMessages[3].role, equals(MessageRole.assistant));
      expect(importedMessages[3].content, equals('It is 72F and sunny!'));
    });

    test('export then import preserves order of multiple conversations', () async {
      final sourceProvider = ConversationProvider();
      await sourceProvider.initialize();

      // Create conversations in order (createConversation inserts at index 0)
      await sourceProvider.createConversation(title: 'Oldest', model: 'model-a');
      await sourceProvider.createConversation(title: 'Middle', model: 'model-b');
      await sourceProvider.createConversation(title: 'Newest', model: 'model-c');

      // In-memory order after creation: [Newest, Middle, Oldest]
      expect(sourceProvider.conversations[0].title, equals('Newest'));
      expect(sourceProvider.conversations[1].title, equals('Middle'));
      expect(sourceProvider.conversations[2].title, equals('Oldest'));

      // Export
      final jsonString = await ConversationImportExportService.exportAllConversations(
        sourceProvider,
      );

      // Clear DB to simulate a fresh install
      await _clearDatabase();

      // Import into fresh provider
      final destProvider = ConversationProvider();
      await destProvider.initialize();

      await ConversationImportExportService.importConversations(jsonString, destProvider);

      // Order should be preserved
      expect(destProvider.conversations[0].title, equals('Newest'));
      expect(destProvider.conversations[1].title, equals('Middle'));
      expect(destProvider.conversations[2].title, equals('Oldest'));
    });
  });
}
