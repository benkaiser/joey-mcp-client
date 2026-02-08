import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:mcp_dart/mcp_dart.dart' show OAuthClientProvider, OAuthTokens;

/// MCP OAuth tokens with expiration tracking
class McpOAuthTokens {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String? tokenType;
  final String? scope;

  McpOAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.tokenType,
    this.scope,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    // Consider token expired 30 seconds before actual expiry
    return DateTime.now().isAfter(expiresAt!.subtract(const Duration(seconds: 30)));
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt?.toIso8601String(),
    'tokenType': tokenType,
    'scope': scope,
  };

  factory McpOAuthTokens.fromJson(Map<String, dynamic> json) => McpOAuthTokens(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String?,
    expiresAt: json['expiresAt'] != null
        ? DateTime.parse(json['expiresAt'] as String)
        : null,
    tokenType: json['tokenType'] as String?,
    scope: json['scope'] as String?,
  );

  OAuthTokens toMcpDartTokens() => OAuthTokens(
    accessToken: accessToken,
    refreshToken: refreshToken,
  );
}

/// Protected Resource Metadata per RFC 9728
class ProtectedResourceMetadata {
  final String resource;
  final List<String> authorizationServers;
  final String? jwksUri;
  final List<String>? scopesSupported;
  final List<String>? bearerMethodsSupported;
  final List<String>? resourceSigningAlgValuesSupported;
  final String? resourceDocumentation;

  ProtectedResourceMetadata({
    required this.resource,
    required this.authorizationServers,
    this.jwksUri,
    this.scopesSupported,
    this.bearerMethodsSupported,
    this.resourceSigningAlgValuesSupported,
    this.resourceDocumentation,
  });

  factory ProtectedResourceMetadata.fromJson(Map<String, dynamic> json) {
    return ProtectedResourceMetadata(
      resource: json['resource'] as String? ?? '',
      authorizationServers: (json['authorization_servers'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [],
      jwksUri: json['jwks_uri'] as String?,
      scopesSupported: (json['scopes_supported'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      bearerMethodsSupported: (json['bearer_methods_supported'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      resourceSigningAlgValuesSupported:
          (json['resource_signing_alg_values_supported'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList(),
      resourceDocumentation: json['resource_documentation'] as String?,
    );
  }
}

/// Authorization Server Metadata per RFC 8414
class AuthorizationServerMetadata {
  final String issuer;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String? registrationEndpoint;
  final String? userInfoEndpoint;
  final String? jwksUri;
  final List<String>? scopesSupported;
  final List<String>? responseTypesSupported;
  final List<String>? grantTypesSupported;
  final List<String>? tokenEndpointAuthMethodsSupported;
  final List<String>? codeChallengeMethodsSupported;
  final bool? clientIdMetadataDocumentSupported;

  AuthorizationServerMetadata({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.registrationEndpoint,
    this.userInfoEndpoint,
    this.jwksUri,
    this.scopesSupported,
    this.responseTypesSupported,
    this.grantTypesSupported,
    this.tokenEndpointAuthMethodsSupported,
    this.codeChallengeMethodsSupported,
    this.clientIdMetadataDocumentSupported,
  });

  bool get supportsPkce =>
      codeChallengeMethodsSupported?.contains('S256') ?? false;

  factory AuthorizationServerMetadata.fromJson(Map<String, dynamic> json) {
    return AuthorizationServerMetadata(
      issuer: json['issuer'] as String? ?? '',
      authorizationEndpoint: json['authorization_endpoint'] as String? ?? '',
      tokenEndpoint: json['token_endpoint'] as String? ?? '',
      registrationEndpoint: json['registration_endpoint'] as String?,
      userInfoEndpoint: json['userinfo_endpoint'] as String?,
      jwksUri: json['jwks_uri'] as String?,
      scopesSupported: (json['scopes_supported'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      responseTypesSupported: (json['response_types_supported'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      grantTypesSupported: (json['grant_types_supported'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      tokenEndpointAuthMethodsSupported:
          (json['token_endpoint_auth_methods_supported'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList(),
      codeChallengeMethodsSupported:
          (json['code_challenge_methods_supported'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList(),
      clientIdMetadataDocumentSupported:
          json['client_id_metadata_document_supported'] as bool?,
    );
  }
}

/// State for tracking OAuth flow
class McpOAuthState {
  final String codeVerifier;
  final String state;
  final String resourceUrl;
  final String authServerUrl;
  final String? scope;
  final String clientId;
  final String redirectUri;
  final DateTime createdAt;

  McpOAuthState({
    required this.codeVerifier,
    required this.state,
    required this.resourceUrl,
    required this.authServerUrl,
    this.scope,
    required this.clientId,
    required this.redirectUri,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isExpired {
    // State expires after 10 minutes
    return DateTime.now().isAfter(createdAt.add(const Duration(minutes: 10)));
  }
}

/// Exception for MCP OAuth errors
class McpOAuthException implements Exception {
  final String message;
  final String? code;
  final int? httpStatus;

  McpOAuthException(this.message, {this.code, this.httpStatus});

  @override
  String toString() => 'McpOAuthException: $message${code != null ? ' (code: $code)' : ''}';
}

/// Result from checking if server requires OAuth
class McpAuthCheckResult {
  final bool requiresAuth;
  final String? resourceMetadataUrl;
  final String? requiredScope;
  final Map<String, String>? wwwAuthenticateParams;

  McpAuthCheckResult({
    required this.requiresAuth,
    this.resourceMetadataUrl,
    this.requiredScope,
    this.wwwAuthenticateParams,
  });
}

/// Service for handling MCP OAuth flows per the MCP Authorization spec
class McpOAuthService {
  final Dio _dio;

  /// Cache for authorization server metadata
  final Map<String, AuthorizationServerMetadata> _asMetadataCache = {};

  /// Cache for protected resource metadata
  final Map<String, ProtectedResourceMetadata> _prMetadataCache = {};

  /// Pending OAuth states (keyed by state parameter)
  final Map<String, McpOAuthState> _pendingStates = {};

  /// Client ID for this application (as a Client ID Metadata Document URL or static ID)
  /// For now, we'll use a simple identifier. For production, this should be an HTTPS URL
  /// pointing to a client metadata document.
  static const String _defaultClientId = 'joey-mcp-client';

  /// Redirect URI for OAuth callbacks
  static const String _redirectUri = 'joey://mcp-oauth/callback';
  static const String _httpsRedirectUri = 'https://openrouterauth.benkaiser.dev/api/mcp-oauth';

  McpOAuthService() : _dio = Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  /// Check if an MCP server requires OAuth authentication
  ///
  /// Makes an unauthenticated request to the server and checks for 401 response
  /// with WWW-Authenticate header
  Future<McpAuthCheckResult> checkAuthRequired(String serverUrl) async {
    try {
      // Try a simple request to the server
      final response = await _dio.post(
        serverUrl,
        data: {
          'jsonrpc': '2.0',
          'method': 'ping',
          'id': 1,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => true, // Accept any status
        ),
      );

      if (response.statusCode == 401) {
        // Parse WWW-Authenticate header
        final wwwAuth = response.headers.value('www-authenticate');
        final params = _parseWwwAuthenticate(wwwAuth);

        return McpAuthCheckResult(
          requiresAuth: true,
          resourceMetadataUrl: params['resource_metadata'],
          requiredScope: params['scope'],
          wwwAuthenticateParams: params,
        );
      }

      // Server doesn't require auth
      return McpAuthCheckResult(requiresAuth: false);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        final wwwAuth = e.response?.headers.value('www-authenticate');
        final params = _parseWwwAuthenticate(wwwAuth);

        return McpAuthCheckResult(
          requiresAuth: true,
          resourceMetadataUrl: params['resource_metadata'],
          requiredScope: params['scope'],
          wwwAuthenticateParams: params,
        );
      }
      rethrow;
    }
  }

  /// Parse WWW-Authenticate header
  Map<String, String> _parseWwwAuthenticate(String? header) {
    final params = <String, String>{};
    if (header == null) return params;

    // Handle Bearer scheme
    if (header.toLowerCase().startsWith('bearer ')) {
      header = header.substring(7);
    }

    // Parse key="value" pairs
    final regex = RegExp(r'(\w+)="([^"]*)"');
    for (final match in regex.allMatches(header)) {
      params[match.group(1)!] = match.group(2)!;
    }

    return params;
  }

  /// Discover protected resource metadata for an MCP server
  Future<ProtectedResourceMetadata> discoverProtectedResourceMetadata(
    String serverUrl, {
    String? metadataUrl,
  }) async {
    // Check cache first
    if (_prMetadataCache.containsKey(serverUrl)) {
      return _prMetadataCache[serverUrl]!;
    }

    final uri = Uri.parse(serverUrl);

    // Try URLs in priority order per spec
    final urlsToTry = <String>[];

    if (metadataUrl != null) {
      urlsToTry.add(metadataUrl);
    }

    // Path-based well-known URI
    if (uri.path.isNotEmpty && uri.path != '/') {
      urlsToTry.add('${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/.well-known/oauth-protected-resource${uri.path}');
    }

    // Root well-known URI
    urlsToTry.add('${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/.well-known/oauth-protected-resource');

    for (final url in urlsToTry) {
      try {
        final response = await _dio.get(
          url,
          options: Options(
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        if (response.statusCode == 200) {
          final metadata = ProtectedResourceMetadata.fromJson(
            response.data as Map<String, dynamic>,
          );
          _prMetadataCache[serverUrl] = metadata;
          return metadata;
        }
      } catch (e) {
        print('McpOAuth: Failed to fetch protected resource metadata from $url: $e');
        continue;
      }
    }

    throw McpOAuthException(
      'Could not discover protected resource metadata for $serverUrl',
    );
  }

  /// Discover authorization server metadata
  Future<AuthorizationServerMetadata> discoverAuthServerMetadata(
    String authServerUrl,
  ) async {
    // Check cache first
    if (_asMetadataCache.containsKey(authServerUrl)) {
      return _asMetadataCache[authServerUrl]!;
    }

    final uri = Uri.parse(authServerUrl);

    // Try discovery endpoints in priority order per spec
    final urlsToTry = <String>[];

    if (uri.path.isNotEmpty && uri.path != '/') {
      // OAuth 2.0 Authorization Server Metadata with path insertion
      urlsToTry.add('${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/.well-known/oauth-authorization-server${uri.path}');
      // OpenID Connect Discovery 1.0 with path insertion
      urlsToTry.add('${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/.well-known/openid-configuration${uri.path}');
      // OpenID Connect Discovery 1.0 path appending
      urlsToTry.add('$authServerUrl/.well-known/openid-configuration');
    } else {
      // OAuth 2.0 Authorization Server Metadata
      urlsToTry.add('${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/.well-known/oauth-authorization-server');
      // OpenID Connect Discovery 1.0
      urlsToTry.add('${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/.well-known/openid-configuration');
    }

    for (final url in urlsToTry) {
      try {
        final response = await _dio.get(
          url,
          options: Options(
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        if (response.statusCode == 200) {
          final metadata = AuthorizationServerMetadata.fromJson(
            response.data as Map<String, dynamic>,
          );

          // Verify PKCE support per spec requirement
          if (!metadata.supportsPkce) {
            print('McpOAuth: Warning - Authorization server at $authServerUrl does not advertise PKCE support');
            // Per spec, MCP clients MUST refuse to proceed if PKCE is not supported
            throw McpOAuthException(
              'Authorization server does not support PKCE (S256)',
              code: 'pkce_not_supported',
            );
          }

          _asMetadataCache[authServerUrl] = metadata;
          return metadata;
        }
      } catch (e) {
        if (e is McpOAuthException) rethrow;
        print('McpOAuth: Failed to fetch auth server metadata from $url: $e');
        continue;
      }
    }

    throw McpOAuthException(
      'Could not discover authorization server metadata for $authServerUrl',
    );
  }

  /// Generate PKCE code verifier (43-128 characters)
  String _generateCodeVerifier() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(128, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Generate PKCE code challenge from verifier (S256)
  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Generate random state parameter
  String _generateState() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Build the authorization URL to redirect the user to
  Future<String> buildAuthorizationUrl({
    required String serverUrl,
    String? clientId,
    String? clientSecret,
    String? scope,
  }) async {
    // Discover protected resource metadata
    final prMetadata = await discoverProtectedResourceMetadata(serverUrl);

    if (prMetadata.authorizationServers.isEmpty) {
      throw McpOAuthException('No authorization servers found for $serverUrl');
    }

    // Select first authorization server (per RFC9728 Section 7.6)
    final authServerUrl = prMetadata.authorizationServers.first;

    // Discover authorization server metadata
    final asMetadata = await discoverAuthServerMetadata(authServerUrl);

    // Generate PKCE parameters
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);
    final state = _generateState();

    // Determine scope to request per spec's scope selection strategy
    final scopeToRequest = scope ??
        prMetadata.scopesSupported?.join(' ') ??
        asMetadata.scopesSupported?.join(' ');

    final effectiveClientId = clientId ?? _defaultClientId;

    // Store state for callback verification
    _pendingStates[state] = McpOAuthState(
      codeVerifier: codeVerifier,
      state: state,
      resourceUrl: serverUrl,
      authServerUrl: authServerUrl,
      scope: scopeToRequest,
      clientId: effectiveClientId,
      redirectUri: _redirectUri,
    );

    // Build authorization URL
    final authUri = Uri.parse(asMetadata.authorizationEndpoint).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': effectiveClientId,
        'redirect_uri': _redirectUri,
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        if (scopeToRequest != null && scopeToRequest.isNotEmpty)
          'scope': scopeToRequest,
      },
    );

    return authUri.toString();
  }

  /// Get canonical resource URI per RFC 8707
  String _getCanonicalResourceUri(String serverUrl) {
    final uri = Uri.parse(serverUrl);
    // Remove trailing slash if present (unless semantically significant)
    var path = uri.path;
    if (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}$path';
  }

  /// Exchange authorization code for tokens
  Future<McpOAuthTokens> exchangeCodeForTokens({
    required String authorizationCode,
    required String state,
    String? clientId,
    String? clientSecret,
  }) async {
    // Retrieve and validate pending state
    final pendingState = _pendingStates.remove(state);
    if (pendingState == null) {
      throw McpOAuthException('Unknown or expired state parameter');
    }

    if (pendingState.isExpired) {
      throw McpOAuthException('Authorization state has expired');
    }

    // Get auth server metadata
    final asMetadata = await discoverAuthServerMetadata(pendingState.authServerUrl);

    // Use client ID from pending state (ensures consistency with authorization request)
    final effectiveClientId = clientId ?? pendingState.clientId;

    // Exchange code for tokens
    try {
      final requestData = {
        'grant_type': 'authorization_code',
        'code': authorizationCode,
        'redirect_uri': pendingState.redirectUri,
        'client_id': effectiveClientId,
        'code_verifier': pendingState.codeVerifier,
        if (clientSecret != null) 'client_secret': clientSecret,
      };

      final response = await _dio.post(
        asMetadata.tokenEndpoint,
        data: requestData,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain, // Get raw response to handle both JSON and form-encoded
        ),
      );

      // Store raw response for error reporting
      final rawResponse = response.data.toString();

      // Parse response data (might be JSON string, Map, or URL-encoded form data)
      final responseData = _parseTokenResponse(response.data);

      if (response.statusCode != 200) {
        final error = responseData['error'] as String?;
        final errorDesc = responseData['error_description'] as String?;
        throw McpOAuthException(
          'Token exchange failed: ${errorDesc ?? error ?? "Unknown error"}. Raw response: $rawResponse',
          code: error,
          httpStatus: response.statusCode,
        );
      }

      final data = responseData;

      DateTime? expiresAt;
      if (data['expires_in'] != null) {
        expiresAt = DateTime.now().add(
          Duration(seconds: data['expires_in'] as int),
        );
      }

      // Validate required fields
      final accessToken = data['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw McpOAuthException(
          'Token response missing access_token. Raw response: $rawResponse',
          code: 'invalid_response',
        );
      }

      return McpOAuthTokens(
        accessToken: accessToken,
        refreshToken: data['refresh_token'] as String?,
        expiresAt: expiresAt,
        tokenType: data['token_type'] as String?,
        scope: data['scope'] as String?,
      );
    } on DioException catch (e) {
      final rawData = e.response?.data?.toString();
      if (rawData != null) {
        try {
          final parsedData = _parseTokenResponse(e.response!.data);
          final error = parsedData['error'] as String?;
          final errorDesc = parsedData['error_description'] as String?;
          throw McpOAuthException(
            'Token exchange failed: ${errorDesc ?? error ?? "Unknown error"}. Raw response: $rawData',
            code: error,
            httpStatus: e.response?.statusCode,
          );
        } catch (_) {
          // If parsing fails, include raw response
          throw McpOAuthException(
            'Token exchange failed with unparseable response. Raw response: $rawData',
            httpStatus: e.response?.statusCode,
          );
        }
      }
      throw McpOAuthException('Token exchange failed: ${e.message}');
    }
  }

  /// Refresh an access token using a refresh token
  Future<McpOAuthTokens> refreshTokens({
    required String serverUrl,
    required String refreshToken,
    String? clientId,
    String? clientSecret,
  }) async {
    // Discover metadata
    final prMetadata = await discoverProtectedResourceMetadata(serverUrl);
    if (prMetadata.authorizationServers.isEmpty) {
      throw McpOAuthException('No authorization servers found');
    }

    final authServerUrl = prMetadata.authorizationServers.first;
    final asMetadata = await discoverAuthServerMetadata(authServerUrl);

    try {
      final response = await _dio.post(
        asMetadata.tokenEndpoint,
        data: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': clientId ?? _defaultClientId,
          if (clientSecret != null) 'client_secret': clientSecret,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
        ),
      );

// Store raw response for error reporting
      final rawResponse = response.data.toString();

      // Parse response data (might be JSON string, Map, or URL-encoded form data)
      final responseData = _parseTokenResponse(response.data);

      if (response.statusCode != 200) {
        final error = responseData['error'] as String?;
        final errorDesc = responseData['error_description'] as String?;
        throw McpOAuthException(
          'Token refresh failed: ${errorDesc ?? error ?? "Unknown error"}. Raw response: $rawResponse',
          code: error,
          httpStatus: response.statusCode,
        );
      }

      final data = responseData;

      DateTime? expiresAt;
      if (data['expires_in'] != null) {
        expiresAt = DateTime.now().add(
          Duration(seconds: data['expires_in'] as int),
        );
      }

      // Validate required fields
      final accessToken = data['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw McpOAuthException(
          'Token refresh response missing access_token. Raw response: $rawResponse',
          code: 'invalid_response',
        );
      }

      return McpOAuthTokens(
        accessToken: accessToken,
        refreshToken: data['refresh_token'] as String? ?? refreshToken,
        expiresAt: expiresAt,
        tokenType: data['token_type'] as String?,
        scope: data['scope'] as String?,
      );
    } on DioException catch (e) {
      final rawData = e.response?.data?.toString();
      if (rawData != null) {
        try {
          final parsedData = _parseTokenResponse(e.response!.data);
          final error = parsedData['error'] as String?;
          final errorDesc = parsedData['error_description'] as String?;
          throw McpOAuthException(
            'Token refresh failed: ${errorDesc ?? error ?? "Unknown error"}. Raw response: $rawData',
            code: error,
            httpStatus: e.response?.statusCode,
          );
        } catch (_) {
          // If parsing fails, include raw response
          throw McpOAuthException(
            'Token refresh failed with unparseable response. Raw response: $rawData',
            httpStatus: e.response?.statusCode,
          );
        }
      }
      throw McpOAuthException('Token refresh failed: ${e.message}');
    }
  }

  /// Parse token response - handles both JSON and URL-encoded form data
  Map<String, dynamic> _parseTokenResponse(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is! String) {
      throw McpOAuthException('Unexpected token response type: ${data.runtimeType}');
    }

    // Try to parse as JSON first
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      // If JSON parsing fails, try URL-encoded form data
      try {
        final params = Uri.splitQueryString(data);
        return params;
      } catch (e) {
        throw McpOAuthException('Failed to parse token response: $data');
      }
    }
  }

  /// Get the pending state for a given state parameter
  McpOAuthState? getPendingState(String state) => _pendingStates[state];

  /// Clear cached metadata (useful for testing or when servers update)
  void clearCache() {
    _asMetadataCache.clear();
    _prMetadataCache.clear();
  }

  /// Clean up expired pending states
  void cleanupExpiredStates() {
    _pendingStates.removeWhere((_, state) => state.isExpired);
  }
}

/// Implementation of mcp_dart's OAuthClientProvider for MCP servers
class McpOAuthClientProvider implements OAuthClientProvider {
  final String serverUrl;
  final String? clientId;
  final String? clientSecret;
  final McpOAuthService _oauthService;
  McpOAuthTokens? _tokens;
  final Future<void> Function(String authUrl) _onAuthRequired;
  final Future<McpOAuthTokens?> Function(String serverUrl) _loadTokens;
  final Future<void> Function(String serverUrl, McpOAuthTokens? tokens) _saveTokens;

  McpOAuthClientProvider({
    required this.serverUrl,
    this.clientId,
    this.clientSecret,
    required McpOAuthService oauthService,
    required Future<void> Function(String authUrl) onAuthRequired,
    required Future<McpOAuthTokens?> Function(String serverUrl) loadTokens,
    required Future<void> Function(String serverUrl, McpOAuthTokens? tokens) saveTokens,
    McpOAuthTokens? initialTokens,
  }) : _oauthService = oauthService,
       _onAuthRequired = onAuthRequired,
       _loadTokens = loadTokens,
       _saveTokens = saveTokens,
       _tokens = initialTokens;

  @override
  Future<OAuthTokens?> tokens() async {
    // Try to load tokens if not already loaded
    if (_tokens == null) {
      _tokens = await _loadTokens(serverUrl);
    }

    if (_tokens == null) {
      return null;
    }

    // Check if token is expired and try to refresh
    if (_tokens!.isExpired && _tokens!.refreshToken != null) {
      try {
        _tokens = await _oauthService.refreshTokens(
          serverUrl: serverUrl,
          refreshToken: _tokens!.refreshToken!,
          clientId: clientId,
          clientSecret: clientSecret,
        );
        await _saveTokens(serverUrl, _tokens);
      } catch (e) {
        print('McpOAuth: Failed to refresh token: $e');
        // Clear expired tokens
        _tokens = null;
        await _saveTokens(serverUrl, null);
        return null;
      }
    }

    return _tokens?.toMcpDartTokens();
  }

  @override
  Future<void> redirectToAuthorization() async {
    final authUrl = await _oauthService.buildAuthorizationUrl(
      serverUrl: serverUrl,
      clientId: clientId,
      clientSecret: clientSecret,
    );
    await _onAuthRequired(authUrl);
  }

  /// Update tokens after OAuth callback
  Future<void> updateTokens(McpOAuthTokens tokens) async {
    _tokens = tokens;
    await _saveTokens(serverUrl, tokens);
  }

  /// Clear stored tokens
  Future<void> clearTokens() async {
    _tokens = null;
    await _saveTokens(serverUrl, null);
  }

  /// Get current tokens (for checking status)
  McpOAuthTokens? get currentTokens => _tokens;
}
