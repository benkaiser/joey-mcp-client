import 'dart:convert';

/// OAuth status for an MCP server
enum McpOAuthStatus {
  /// No OAuth configured or required
  none,
  /// OAuth is required but not yet authenticated
  required,
  /// OAuth authentication in progress
  pending,
  /// Successfully authenticated with valid tokens
  authenticated,
  /// Authentication expired, needs refresh or re-auth
  expired,
  /// Authentication failed
  failed,
}

/// Stored OAuth tokens for an MCP server
class McpServerOAuthTokens {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String? tokenType;
  final String? scope;

  McpServerOAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.tokenType,
    this.scope,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!.subtract(const Duration(seconds: 30)));
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt?.toIso8601String(),
    'tokenType': tokenType,
    'scope': scope,
  };

  factory McpServerOAuthTokens.fromJson(Map<String, dynamic> json) => McpServerOAuthTokens(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String?,
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
        : null,
    tokenType: json['tokenType'] as String?,
    scope: json['scope'] as String?,
  );

  String encode() => jsonEncode(toJson());

  static McpServerOAuthTokens? decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return McpServerOAuthTokens.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
    } catch (e) {
      return null;
    }
  }
}

class McpServer {
  final String id;
  final String name;
  final String url;
  final Map<String, String>? headers;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// OAuth status for this server
  final McpOAuthStatus oauthStatus;

  /// Stored OAuth tokens (if authenticated)
  final McpServerOAuthTokens? oauthTokens;

  /// Optional custom client ID for OAuth (if server requires registration)
  final String? oauthClientId;

  /// Optional client secret for OAuth (not recommended - only for providers that don't support PKCE)
  final String? oauthClientSecret;

  McpServer({
    required this.id,
    required this.name,
    required this.url,
    this.headers,
    this.isEnabled = true,
    required this.createdAt,
    required this.updatedAt,
    this.oauthStatus = McpOAuthStatus.none,
    this.oauthTokens,
    this.oauthClientId,
    this.oauthClientSecret,
  });

  /// Check if this server requires OAuth and is not yet authenticated
  bool get needsOAuth =>
      oauthStatus == McpOAuthStatus.required ||
      oauthStatus == McpOAuthStatus.expired ||
      oauthStatus == McpOAuthStatus.failed;

  /// Check if this server has valid OAuth tokens
  bool get hasValidOAuthTokens =>
      oauthStatus == McpOAuthStatus.authenticated &&
      oauthTokens != null &&
      !oauthTokens!.isExpired;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'headers': headers != null ? _encodeHeaders(headers!) : null,
      'isEnabled': isEnabled ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'oauthStatus': oauthStatus.name,
      'oauthTokens': oauthTokens?.encode(),
      'oauthClientId': oauthClientId,
      'oauthClientSecret': oauthClientSecret,
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
      oauthStatus: _parseOAuthStatus(map['oauthStatus']),
      oauthTokens: McpServerOAuthTokens.decode(map['oauthTokens'] as String?),
      oauthClientId: map['oauthClientId'] as String?,
      oauthClientSecret: map['oauthClientSecret'] as String?,
    );
  }

  static McpOAuthStatus _parseOAuthStatus(String? status) {
    if (status == null) return McpOAuthStatus.none;
    try {
      return McpOAuthStatus.values.firstWhere((e) => e.name == status);
    } catch (_) {
      return McpOAuthStatus.none;
    }
  }

  McpServer copyWith({
    String? id,
    String? name,
    String? url,
    Map<String, String>? headers,
    bool? isEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
    McpOAuthStatus? oauthStatus,
    McpServerOAuthTokens? oauthTokens,
    String? oauthClientId,
    String? oauthClientSecret,
    bool clearOAuthTokens = false,
  }) {
    return McpServer(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      oauthStatus: oauthStatus ?? this.oauthStatus,
      oauthTokens: clearOAuthTokens ? null : (oauthTokens ?? this.oauthTokens),
      oauthClientId: oauthClientId ?? this.oauthClientId,
      oauthClientSecret: oauthClientSecret ?? this.oauthClientSecret,
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
