import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../providers/conversation_provider.dart';
import 'chat_service.dart';
import 'mcp_oauth_manager.dart';
import 'mcp_server_manager.dart';

/// Holds the services for a conversation whose agentic loop is still running
/// after the user navigated away from the chat screen.
class ActiveChat {
  final ChatService chatService;
  final McpServerManager serverManager;
  final McpOAuthManager oauthManager;
  final String conversationId;
  final String model;

  ActiveChat({
    required this.chatService,
    required this.serverManager,
    required this.oauthManager,
    required this.conversationId,
    required this.model,
  });
}

/// Singleton that keeps agentic loops alive when the user navigates away.
class BackgroundChatManager extends ChangeNotifier {
  BackgroundChatManager._();
  static final BackgroundChatManager instance = BackgroundChatManager._();

  final Map<String, ActiveChat> _active = {};
  final Map<String, StreamSubscription> _subscriptions = {};
  bool _notifyScheduled = false;

  /// Schedule a deferred notifyListeners to avoid calling during build/dispose.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  /// IDs of conversations with running background loops.
  Set<String> get activeConversationIds => _active.keys.toSet();

  /// Whether a conversation has an active background loop.
  bool isActive(String conversationId) => _active.containsKey(conversationId);

  /// Register a running chat to continue in the background.
  /// [provider] is used to persist messages that arrive while the UI is gone.
  void register(ActiveChat chat, ConversationProvider provider) {
    final id = chat.conversationId;
    _active[id] = chat;

    _subscriptions[id] = chat.chatService.events.listen((event) {
      if (event is MessageCreated) {
        provider.addMessage(event.message);
      } else if (event is ConversationComplete ||
          event is MaxIterationsReached ||
          event is ErrorOccurred) {
        _cleanup(id);
      }
      // Streaming/UI events (ContentChunk, ReasoningChunk, etc.) are ignored.
      // Sampling/elicitation completers block naturally until the user returns.
    });

    _scheduleNotify();
  }

  /// Detach a conversation from background management so the UI can reattach.
  /// Returns the [ActiveChat] if one was running, otherwise null.
  ActiveChat? detach(String conversationId) {
    final chat = _active.remove(conversationId);
    _subscriptions.remove(conversationId)?.cancel();
    if (chat != null) {
      _scheduleNotify();
    }
    return chat;
  }

  void _cleanup(String conversationId) {
    final chat = _active.remove(conversationId);
    _subscriptions.remove(conversationId)?.cancel();
    if (chat != null) {
      chat.chatService.dispose();
      chat.oauthManager.dispose();
      chat.serverManager.dispose();
      _scheduleNotify();
    }
  }
}
