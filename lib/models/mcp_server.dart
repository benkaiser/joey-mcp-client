class McpServer {
  final String id;
  final String name;
  final String url;
  final Map<String, String>? headers;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  McpServer({
    required this.id,
    required this.name,
    required this.url,
    this.headers,
    this.isEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'headers': headers != null ? _encodeHeaders(headers!) : null,
      'isEnabled': isEnabled ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory McpServer.fromMap(Map<String, dynamic> map) {
    return McpServer(
      id: map['id'],
      name: map['name'],
      url: map['url'],
      headers: map['headers'] != null ? _decodeHeaders(map['headers']) : null,
      isEnabled: map['isEnabled'] == 1,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  McpServer copyWith({
    String? id,
    String? name,
    String? url,
    Map<String, String>? headers,
    bool? isEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return McpServer(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String _encodeHeaders(Map<String, String> headers) {
    return headers.entries.map((e) => '${e.key}:${e.value}').join('|||');
  }

  static Map<String, String> _decodeHeaders(String encoded) {
    if (encoded.isEmpty) return {};
    final pairs = encoded.split('|||');
    final result = <String, String>{};
    for (final pair in pairs) {
      final parts = pair.split(':');
      if (parts.length >= 2) {
        result[parts[0]] = parts.sublist(1).join(':');
      }
    }
    return result;
  }
}
