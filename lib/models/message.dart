import 'dart:convert';

enum MessageRole {
  user,
  assistant,
  system,
  tool, // For tool result messages
}

class Message {
  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final String? reasoning; // Reasoning/thinking content for assistant messages
  final String?
  toolCallData; // JSON string of tool calls for assistant messages
  final String? toolCallId; // For tool role messages
  final String? toolName; // For tool role messages

  Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.timestamp,
    this.reasoning,
    this.toolCallData,
    this.toolCallId,
    this.toolName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversationId': conversationId,
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'reasoning': reasoning,
      'toolCallData': toolCallData,
      'toolCallId': toolCallId,
      'toolName': toolName,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      conversationId: map['conversationId'],
      role: MessageRole.values.firstWhere((e) => e.name == map['role']),
      content: map['content'],
      timestamp: DateTime.parse(map['timestamp']),
      reasoning: map['reasoning'],
      toolCallData: map['toolCallData'],
      toolCallId: map['toolCallId'],
      toolName: map['toolName'],
    );
  }

  Message copyWith({
    String? id,
    String? conversationId,
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    String? reasoning,
    String? toolCallData,
    String? toolCallId,
    String? toolName,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      reasoning: reasoning ?? this.reasoning,
      toolCallData: toolCallData ?? this.toolCallData,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
    );
  }

  /// Convert this message to the format expected by OpenRouter API
  Map<String, dynamic> toApiMessage() {
    if (role == MessageRole.tool) {
      // Tool result message
      return {
        'role': 'tool',
        'tool_call_id': toolCallId!,
        'name': toolName!,
        'content': content,
      };
    } else if (toolCallData != null) {
      // Assistant message with tool calls
      return {'role': 'assistant', 'tool_calls': jsonDecode(toolCallData!)};
    } else {
      // Regular user/assistant message
      return {
        'role': role == MessageRole.user ? 'user' : 'assistant',
        'content': content,
      };
    }
  }
}
