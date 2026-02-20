import 'dart:convert';

enum MessageRole {
  user,
  assistant,
  system,
  tool, // For tool result messages
  elicitation, // For elicitation request cards (local display only, not sent to LLM)
  mcpNotification, // For MCP server notifications (included as context for LLM)
  modelChange, // For model change indicators (local display only, not sent to LLM)
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
  final String?
  elicitationData; // JSON string of elicitation request for elicitation role messages
  final String?
  notificationData; // JSON string of MCP notification data for mcpNotification role messages
  final String?
  imageData; // JSON array of image objects [{data: base64, mimeType: string}]
  final String?
  audioData; // JSON array of audio objects [{data: base64, mimeType: string}]
  final String?
  usageData; // JSON string of usage/cost data from OpenRouter

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
    this.elicitationData,
    this.notificationData,
    this.imageData,
    this.audioData,
    this.usageData,
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
      'elicitationData': elicitationData,
      'notificationData': notificationData,
      'imageData': imageData,
      'audioData': audioData,
      'usageData': usageData,
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
      elicitationData: map['elicitationData'],
      notificationData: map['notificationData'],
      imageData: map['imageData'],
      audioData: map['audioData'],
      usageData: map['usageData'],
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
    String? elicitationData,
    String? notificationData,
    String? imageData,
    String? audioData,
    String? usageData,
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
      elicitationData: elicitationData ?? this.elicitationData,
      notificationData: notificationData ?? this.notificationData,
      imageData: imageData ?? this.imageData,
      audioData: audioData ?? this.audioData,
      usageData: usageData ?? this.usageData,
    );
  }

  /// Convert this message to the format expected by OpenRouter API
  /// Returns null for elicitation messages as they should not be sent to the LLM
  Map<String, dynamic>? toApiMessage() {
    // Elicitation messages are local-only, don't send to LLM
    if (role == MessageRole.elicitation) {
      return null;
    }
    // Model change indicators are local-only, don't send to LLM
    if (role == MessageRole.modelChange) {
      return null;
    }
    // MCP notifications are sent as system messages for context
    if (role == MessageRole.mcpNotification) {
      final data = notificationData != null
          ? jsonDecode(notificationData!)
          : {};
      final serverName = data['serverName'] ?? 'MCP Server';
      final method = data['method'] ?? 'unknown';
      final params = data['params'];

      // Format the notification as context for the LLM
      String notificationContent =
          '[Notification from MCP server "$serverName"]\n';
      notificationContent += 'Method: $method\n';
      if (params != null) {
        notificationContent += 'Params: ${jsonEncode(params)}';
      }

      return {'role': 'user', 'content': notificationContent};
    }
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
      return {'role': 'assistant', 'content': content, 'tool_calls': jsonDecode(toolCallData!)};
    } else {
      // Regular user/assistant message
      final apiRole = role == MessageRole.user ? 'user' : 'assistant';

      // If user message has image or audio attachments, build multi-part content
      if (role == MessageRole.user && (imageData != null || audioData != null)) {
        final contentParts = <Map<String, dynamic>>[
          {'type': 'text', 'text': content},
        ];

        // Add image parts
        if (imageData != null) {
          try {
            final images = jsonDecode(imageData!) as List;
            for (final img in images) {
              final data = img['data'] as String;
              final mimeType = img['mimeType'] as String? ?? 'image/png';
              contentParts.add({
                'type': 'image_url',
                'image_url': {'url': 'data:$mimeType;base64,$data'},
              });
            }
          } catch (e) {
            // Ignore image parse errors
          }
        }

        // Add audio parts
        if (audioData != null) {
          try {
            final audioList = jsonDecode(audioData!) as List;
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
          } catch (e) {
            // Ignore audio parse errors
          }
        }

        if (contentParts.length > 1) {
          return {'role': apiRole, 'content': contentParts};
        }
      }

      return {'role': apiRole, 'content': content};
    }
  }

  /// Convert audio MIME type to OpenRouter format string
  static String _audioFormatFromMimeType(String mimeType) {
    const mimeToFormat = {
      'audio/mpeg': 'mp3',
      'audio/mp3': 'mp3',
      'audio/wav': 'wav',
      'audio/x-wav': 'wav',
      'audio/wave': 'wav',
      'audio/aac': 'aac',
      'audio/ogg': 'ogg',
      'audio/flac': 'flac',
      'audio/mp4': 'm4a',
      'audio/x-m4a': 'm4a',
      'audio/m4a': 'm4a',
      'audio/webm': 'webm',
    };
    return mimeToFormat[mimeType] ?? mimeType.replaceFirst('audio/', '');
  }
}
