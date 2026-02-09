import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import '../models/mcp_server.dart';
import '../widgets/mcp_oauth_card.dart';
import 'database_service.dart';
import 'mcp_oauth_service.dart';

/// Delegate class that manages MCP OAuth authentication flows.
///
/// Communicates back to the host via callbacks:
/// - [onStateChanged] — called when internal state changes (e.g. OAuth status)
/// - [onReinitializeServer] — called when a server should be re-initialized after OAuth
/// - [onShowMessage] — called when a message should be shown to the user
class McpOAuthManager {
  final McpOAuthService _mcpOAuthService = McpOAuthService();
  final AppLinks _appLinks = AppLinks();
  StreamSubscription? _deepLinkSubscription;

  /// Servers that need OAuth authentication
  final List<McpServer> serversNeedingOAuth = [];

  /// OAuth provider instances for each server
  final Map<String, McpOAuthClientProvider> oauthProviders = {};

  /// Track OAuth status for each server
  final Map<String, McpOAuthCardStatus> serverOAuthStatus = {};

  /// Callback invoked when internal state changes (re-render needed).
  VoidCallback? onStateChanged;

  /// Callback to re-initialize a server after successful OAuth.
  Future<void> Function(McpServer server)? onReinitializeServer;

  /// Callback to show a message to the user (text, color).
  void Function(String message, Color color)? onShowMessage;

  /// Access the underlying OAuth service.
  McpOAuthService get oauthService => _mcpOAuthService;

  /// Initialize deep link listener for MCP OAuth callbacks
  void initDeepLinkListener() {
    _deepLinkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        final isCustomScheme = uri.scheme == 'joey' && uri.host == 'mcp-oauth';
        final isHttpsCallback =
            uri.scheme == 'https' &&
            uri.host == 'openrouterauth.benkaiser.dev' &&
            uri.path == '/api/mcp-oauth';

        if (isCustomScheme || isHttpsCallback) {
          handleMcpOAuthCallback(uri);
        }
      },
      onError: (err) {
        debugPrint('MCP OAuth deep link error: $err');
      },
    );
  }

  /// Create an OAuth provider for a server
  McpOAuthClientProvider createOAuthProvider(McpServer server) {
    // Convert stored tokens if available
    McpOAuthTokens? initialTokens;
    if (server.oauthTokens != null) {
      initialTokens = McpOAuthTokens(
        accessToken: server.oauthTokens!.accessToken,
        refreshToken: server.oauthTokens!.refreshToken,
        expiresAt: server.oauthTokens!.expiresAt,
        tokenType: server.oauthTokens!.tokenType,
        scope: server.oauthTokens!.scope,
      );
    }

    return McpOAuthClientProvider(
      serverUrl: server.url,
      clientId: server.oauthClientId,
      clientSecret: server.oauthClientSecret,
      oauthService: _mcpOAuthService,
      initialTokens: initialTokens,
      onAuthRequired: (authUrl) async {
        // Don't auto-launch - let user click the button in the banner
        debugPrint('MCP OAuth required for ${server.name}: $authUrl');
      },
      loadTokens: (serverUrl) async {
        // Reload server from database to get latest tokens
        final servers = await DatabaseService.instance.getAllMcpServers();
        final currentServer = servers.firstWhere(
          (s) => s.url == serverUrl,
          orElse: () => server,
        );

        if (currentServer.oauthTokens != null) {
          return McpOAuthTokens(
            accessToken: currentServer.oauthTokens!.accessToken,
            refreshToken: currentServer.oauthTokens!.refreshToken,
            expiresAt: currentServer.oauthTokens!.expiresAt,
            tokenType: currentServer.oauthTokens!.tokenType,
            scope: currentServer.oauthTokens!.scope,
          );
        }
        return null;
      },
      saveTokens: (serverUrl, tokens) async {
        // Find and update the server with new tokens
        final servers = await DatabaseService.instance.getAllMcpServers();
        final currentServer = servers.firstWhere(
          (s) => s.url == serverUrl,
          orElse: () => server,
        );

        McpServerOAuthTokens? storedTokens;
        if (tokens != null) {
          storedTokens = McpServerOAuthTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt,
            tokenType: tokens.tokenType,
            scope: tokens.scope,
          );
        }

        final updatedServer = currentServer.copyWith(
          oauthStatus: tokens != null
              ? McpOAuthStatus.authenticated
              : McpOAuthStatus.none,
          oauthTokens: storedTokens,
          clearOAuthTokens: tokens == null,
          updatedAt: DateTime.now(),
        );

        await DatabaseService.instance.updateMcpServer(updatedServer);
      },
    );
  }

  /// Handle when a server indicates it needs OAuth
  void handleServerNeedsOAuth(McpServer server, List<McpServer> mcpServers) {
    final index = mcpServers.indexWhere((s) => s.id == server.id);
    if (index >= 0 && !serversNeedingOAuth.any((s) => s.id == server.id)) {
      serversNeedingOAuth.add(mcpServers[index]);
      serverOAuthStatus[server.id] = McpOAuthCardStatus.pending;
      onStateChanged?.call();

      // Update server in database
      final updatedServer = server.copyWith(
        oauthStatus: McpOAuthStatus.required,
        updatedAt: DateTime.now(),
      );
      DatabaseService.instance.updateMcpServer(updatedServer);
    }
  }

  /// Handle MCP OAuth callback from deep link
  Future<void> handleMcpOAuthCallback(
    Uri uri, {
    List<McpServer> mcpServers = const [],
  }) async {
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    final error = uri.queryParameters['error'];

    if (error != null) {
      debugPrint('MCP OAuth error: $error');
      // Find the server that was authenticating and mark as failed
      for (final entry in serverOAuthStatus.entries) {
        if (entry.value == McpOAuthCardStatus.inProgress) {
          serverOAuthStatus[entry.key] = McpOAuthCardStatus.failed;
          onStateChanged?.call();
          break;
        }
      }
      return;
    }

    if (code == null || state == null) {
      debugPrint('MCP OAuth callback missing code or state');
      return;
    }

    try {
      // Find which server this is for to get client secret
      final pendingState = _mcpOAuthService.getPendingState(state);
      McpServer? server;

      if (pendingState != null) {
        server = mcpServers.firstWhere(
          (s) => s.url == pendingState.resourceUrl,
          orElse: () => serversNeedingOAuth.firstWhere(
            (s) => s.url == pendingState.resourceUrl,
          ),
        );
      }

      // Exchange code for tokens
      final tokens = await _mcpOAuthService.exchangeCodeForTokens(
        authorizationCode: code,
        state: state,
        clientId: server?.oauthClientId,
        clientSecret: server?.oauthClientSecret,
      );

      // Use the server we found, or try to find it again
      if (pendingState == null) {
        // Try to find by URL in our servers
        for (final s in serversNeedingOAuth) {
          if (serverOAuthStatus[s.id] == McpOAuthCardStatus.inProgress) {
            await completeServerOAuth(s, tokens, mcpServers);
            return;
          }
        }
        return;
      }

      if (server == null) {
        server = mcpServers.firstWhere(
          (s) => s.url == pendingState.resourceUrl,
          orElse: () => serversNeedingOAuth.firstWhere(
            (s) => s.url == pendingState.resourceUrl,
          ),
        );
      }

      await completeServerOAuth(server, tokens, mcpServers);
    } catch (e) {
      debugPrint('MCP OAuth token exchange failed: $e');

      // Mark the in-progress server as failed
      for (final entry in serverOAuthStatus.entries) {
        if (entry.value == McpOAuthCardStatus.inProgress) {
          serverOAuthStatus[entry.key] = McpOAuthCardStatus.failed;
          onStateChanged?.call();
          break;
        }
      }

      onShowMessage?.call('OAuth failed: ${e.toString()}', Colors.red);
    }
  }

  /// Complete OAuth for a server after successful token exchange
  Future<void> completeServerOAuth(
    McpServer server,
    McpOAuthTokens tokens,
    List<McpServer> mcpServers,
  ) async {
    // Update OAuth provider with new tokens
    final provider = oauthProviders[server.id];
    if (provider != null) {
      await provider.updateTokens(tokens);
    }

    // Save tokens to server
    final storedTokens = McpServerOAuthTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAt,
      tokenType: tokens.tokenType,
      scope: tokens.scope,
    );

    final updatedServer = server.copyWith(
      oauthStatus: McpOAuthStatus.authenticated,
      oauthTokens: storedTokens,
      updatedAt: DateTime.now(),
    );

    await DatabaseService.instance.updateMcpServer(updatedServer);

    // Update local state
    final index = mcpServers.indexWhere((s) => s.id == server.id);
    if (index >= 0) {
      mcpServers[index] = updatedServer;
      serverOAuthStatus[server.id] = McpOAuthCardStatus.completed;
      serversNeedingOAuth.removeWhere((s) => s.id == server.id);
      onStateChanged?.call();
    }

    // Re-initialize the server with the new tokens
    await onReinitializeServer?.call(updatedServer);

    onShowMessage?.call('Connected to ${server.name}', Colors.green);
  }

  /// Start OAuth flow for a specific server
  Future<void> startServerOAuth(McpServer server) async {
    try {
      // Create provider if not exists
      if (!oauthProviders.containsKey(server.id)) {
        oauthProviders[server.id] = createOAuthProvider(server);
      }

      serverOAuthStatus[server.id] = McpOAuthCardStatus.inProgress;
      onStateChanged?.call();

      // Build and launch auth URL
      final authUrl = await _mcpOAuthService.buildAuthorizationUrl(
        serverUrl: server.url,
        clientId: server.oauthClientId,
        clientSecret: server.oauthClientSecret,
      );

      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch browser');
      }
    } catch (e) {
      debugPrint('Failed to start OAuth for ${server.name}: $e');
      serverOAuthStatus[server.id] = McpOAuthCardStatus.failed;
      onStateChanged?.call();

      onShowMessage?.call(
        'Failed to start sign in: ${e.toString()}',
        Colors.red,
      );
    }
  }

  /// Skip OAuth for a server (remove from pending list)
  void skipServerOAuth(McpServer server) {
    serversNeedingOAuth.removeWhere((s) => s.id == server.id);
    serverOAuthStatus.remove(server.id);
    onStateChanged?.call();
  }

  /// Start OAuth for all servers that need it
  Future<void> startAllServersOAuth() async {
    for (final server in serversNeedingOAuth) {
      if (serverOAuthStatus[server.id] != McpOAuthCardStatus.inProgress) {
        await startServerOAuth(server);
        // Only start one at a time to avoid confusion
        break;
      }
    }
  }

  /// Clean up on removal of a server
  void removeServer(String serverId) {
    oauthProviders.remove(serverId);
    serverOAuthStatus.remove(serverId);
    serversNeedingOAuth.removeWhere((s) => s.id == serverId);
  }

  /// Dispose of resources
  void dispose() {
    _deepLinkSubscription?.cancel();
  }
}
