import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../providers/conversation_provider.dart';

class ImportResult {
  final int imported;
  final int skipped;

  ImportResult({required this.imported, required this.skipped});
}

class ConversationImportExportService {
  static const int _currentVersion = 1;
  static const String _appName = 'joey-mcp-client';

  /// Export all conversations and their messages as a JSON string.
  static Future<String> exportAllConversations(
    ConversationProvider provider,
  ) async {
    final conversationsData = <Map<String, dynamic>>[];

    for (final conversation in provider.conversations) {
      final messages = provider.getMessages(conversation.id);
      final conversationMap = conversation.toMap();
      conversationMap['messages'] = messages.map((m) => m.toMap()).toList();
      conversationsData.add(conversationMap);
    }

    final envelope = {
      'version': _currentVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'appName': _appName,
      'conversations': conversationsData,
    };

    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Export a single conversation and its messages as a JSON string.
  static String exportSingleConversation(
    Conversation conversation,
    List<Message> messages,
  ) {
    final conversationMap = conversation.toMap();
    conversationMap['messages'] = messages.map((m) => m.toMap()).toList();

    final envelope = {
      'version': _currentVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'appName': _appName,
      'conversations': [conversationMap],
    };

    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Import conversations from a JSON string.
  /// Generates new UUIDs for conversations and messages to avoid collisions.
  static Future<ImportResult> importConversations(
    String jsonString,
    ConversationProvider provider,
  ) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;

    // Validate envelope
    final version = data['version'] as int?;
    if (version == null || version > _currentVersion) {
      throw FormatException(
        'Unsupported export version: $version (max supported: $_currentVersion)',
      );
    }

    final conversations = data['conversations'] as List<dynamic>?;
    if (conversations == null) {
      throw const FormatException('No conversations found in import file');
    }

    const uuid = Uuid();
    int imported = 0;
    int skipped = 0;

    // Import in reverse order so the final in-memory list matches the
    // original display order (importConversation inserts at position 0,
    // and addMessage moves the conversation to the top).
    for (final convData in conversations.reversed) {
      try {
        final convMap = convData as Map<String, dynamic>;
        final messagesData = convMap['messages'] as List<dynamic>? ?? [];

        // Generate a new ID for the conversation
        final newConversationId = uuid.v4();

        // Create the conversation with a new ID
        final conversationMap = Map<String, dynamic>.from(convMap);
        conversationMap['id'] = newConversationId;
        conversationMap.remove('messages');

        final conversation = Conversation.fromMap(conversationMap);

        // Import the conversation via the provider
        await provider.importConversation(conversation);

        // Import messages with new IDs and remapped conversationId
        for (final msgData in messagesData) {
          final msgMap = Map<String, dynamic>.from(msgData as Map<String, dynamic>);
          msgMap['id'] = uuid.v4();
          msgMap['conversationId'] = newConversationId;

          final message = Message.fromMap(msgMap);
          await provider.addMessage(message);
        }

        imported++;
      } catch (e) {
        skipped++;
      }
    }

    return ImportResult(imported: imported, skipped: skipped);
  }
}
