import 'package:flutter/foundation.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/database_service.dart';
import 'package:uuid/uuid.dart';

class ConversationProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  final List<Conversation> _conversations = [];
  final Map<String, List<Message>> _messages = {};
  bool _isInitialized = false;

  List<Conversation> get conversations => List.unmodifiable(_conversations);

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Load conversations from database
    _conversations.clear();
    _conversations.addAll(await _db.getAllConversations());

    // Load messages for each conversation
    for (final conversation in _conversations) {
      final messages = await _db.getMessagesForConversation(conversation.id);
      _messages[conversation.id] = messages;
    }

    _isInitialized = true;
    notifyListeners();
  }

  List<Message> getMessages(String conversationId) {
    return List.unmodifiable(_messages[conversationId] ?? []);
  }

  Future<Conversation> createConversation({String? title}) async {
    final now = DateTime.now();
    final conversation = Conversation(
      id: const Uuid().v4(),
      title: title ?? 'New Chat ${_conversations.length + 1}',
      createdAt: now,
      updatedAt: now,
    );

    _conversations.insert(0, conversation);
    _messages[conversation.id] = [];

    await _db.insertConversation(conversation);
    notifyListeners();

    return conversation;
  }

  Future<void> deleteConversation(String id) async {
    _conversations.removeWhere((c) => c.id == id);
    _messages.remove(id);

    await _db.deleteConversation(id);
    notifyListeners();
  }

  Future<void> updateConversationTitle(String id, String newTitle) async {
    final index = _conversations.indexWhere((c) => c.id == id);
    if (index != -1) {
      _conversations[index] = _conversations[index].copyWith(
        title: newTitle,
        updatedAt: DateTime.now(),
      );

      await _db.updateConversation(_conversations[index]);
      notifyListeners();
    }
  }

  Future<void> addMessage(Message message) async {
    if (!_messages.containsKey(message.conversationId)) {
      _messages[message.conversationId] = [];
    }
    _messages[message.conversationId]!.add(message);

    // Update conversation's updatedAt timestamp
    final index = _conversations.indexWhere((c) => c.id == message.conversationId);
    if (index != -1) {
      _conversations[index] = _conversations[index].copyWith(
        updatedAt: DateTime.now(),
      );

      // Move to top of list
      final conversation = _conversations.removeAt(index);
      _conversations.insert(0, conversation);

      await _db.updateConversation(conversation);
    }

    await _db.insertMessage(message);
    notifyListeners();
  }

  Future<void> clearMessages(String conversationId) async {
    _messages[conversationId]?.clear();

    await _db.deleteMessagesForConversation(conversationId);
    notifyListeners();
  }

  Future<void> deleteAllConversations() async {
    final conversationIds = _conversations.map((c) => c.id).toList();
    
    _conversations.clear();
    _messages.clear();
    
    // Delete all conversations from database
    for (final id in conversationIds) {
      await _db.deleteConversation(id);
    }
    
    notifyListeners();
  }
}
