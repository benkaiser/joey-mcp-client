import 'package:flutter/material.dart';
import '../models/mcp_server.dart';
import '../utils/in_app_browser.dart';
import '../widgets/mcp_oauth_card.dart';
import 'database_service.dart';
import 'mcp_oauth_service.dart';

/// Delegate class that manages MCP OAuth authentication flows.
///
/// Extends [ChangeNotifier] for multi-listener state change support.
/// Also communicates back to the host via single-slot action callbacks:
/// - [onReinitializeServer] — called when a server should be re-initialized after OAuth
/// - [onShowMessage] — called when a message should be shown to the user
/// - [onServerOAuthRequired] — called when a server needs OAuth authentication
class McpOAuthManager extends ChangeNotifier {
  final McpOAuthService _mcpOAuthService = McpOAuthService();

  /// Servers that need OAuth authentication
  final List<McpServer> serversNeedingOAuth = [];

  /// OAuth provider instances for each server
  final Map<String, McpOAuthClientProvider> oauthProviders = {};

  /// Track OAuth status for each server
  final Map<String, McpOAuthCardStatus> serverOAuthStatus = {};

  /// Callback to re-initialize a server after successful OAuth.
  Future<void> Function(McpServer server)? onReinitializeServer;

  /// Callback to show a message to the user (text, color).
  void Function(String message, Color color)? onShowMessage;

  /// Callback invoked when a server requires OAuth authentication.
  void Function(String serverName)? onServerOAuthRequired;

  /// Access the underlying OAuth service.
  McpOAuthService get oauthService => _mcpOAuthService;

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
    if (index < 0) return;

    final existingIdx = serversNeedingOAuth.indexWhere((s) => s.id == server.id);
    final existingStatus = serverOAuthStatus[server.id];

    // If already pending or in-progress, don't add again
    if (existingIdx >= 0 && existingStatus != McpOAuthCardStatus.completed) {
      return;
    }

    // If this server previously completed OAuth (banner was hidden) but now needs
    // auth again (e.g. server restarted), remove the stale completed entry so we
    // can re-add it with a fresh pending status below.
    if (existingIdx >= 0) {
      serversNeedingOAuth.removeAt(existingIdx);
    }

    // Update in-memory server with required status
    final updatedServer = mcpServers[index].copyWith(
      oauthStatus: McpOAuthStatus.required,
      updatedAt: DateTime.now(),
    );
    mcpServers[index] = updatedServer;

    serversNeedingOAuth.add(updatedServer);
    serverOAuthStatus[server.id] = McpOAuthCardStatus.pending;
    notifyListeners();

    // Persist to database
    DatabaseService.instance.updateMcpServer(updatedServer);

    onServerOAuthRequired?.call(server.name);
  }

  /// Handle MCP OAuth callback from auth session
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
          notifyListeners();
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
          notifyListeners();
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
    }
    serverOAuthStatus[server.id] = McpOAuthCardStatus.completed;
    notifyListeners();

    // Remove from the pending list BEFORE re-initializing.  This is intentional:
    // if re-initialization itself triggers an auth error (e.g. the new tokens are
    // rejected), McpServerManager will call handleServerNeedsOAuth again, which
    // checks !serversNeedingOAuth.any(...). By removing here we allow that call to
    // re-add the server with a fresh pending status and re-show the OAuth banner.
    serversNeedingOAuth.removeWhere((s) => s.id == server.id);

    try {
      // Re-initialize the server with the new tokens
      await onReinitializeServer?.call(updatedServer);
    } finally {
      // Always clear the completed status so the state is fully reset.
      // On success: leaves a clean slate so future disconnects can re-trigger OAuth.
      // On failure: re-initialization internally calls handleServerNeedsOAuth which
      // re-adds the server with pending status; removing completed here avoids a
      // stale status conflicting with that new pending entry.
      serverOAuthStatus.remove(server.id);
      notifyListeners();
    }
  }

  /// Start OAuth flow for a specific server
  Future<void> startServerOAuth(
    McpServer server, {
    List<McpServer> mcpServers = const [],
  }) async {
    try {
      // Create provider if not exists
      if (!oauthProviders.containsKey(server.id)) {
        oauthProviders[server.id] = createOAuthProvider(server);
      }

      serverOAuthStatus[server.id] = McpOAuthCardStatus.inProgress;
      notifyListeners();

      // Build and launch auth URL via ASWebAuthenticationSession / Auth Tab
      final authUrl = await _mcpOAuthService.buildAuthorizationUrl(
        serverUrl: server.url,
        clientId: server.oauthClientId,
        clientSecret: server.oauthClientSecret,
      );

      final uri = Uri.parse(authUrl);
      final callbackUri = await launchAuthSession(
        uri,
        callbackUrlScheme: 'joey',
      );
      await handleMcpOAuthCallback(callbackUri, mcpServers: mcpServers);
    } catch (e) {
      debugPrint('Failed to start OAuth for ${server.name}: $e');
      serverOAuthStatus[server.id] = McpOAuthCardStatus.failed;
      notifyListeners();

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
    notifyListeners();
  }

  /// Start OAuth for all servers that need it
  Future<void> startAllServersOAuth({
    List<McpServer> mcpServers = const [],
  }) async {
    for (final server in serversNeedingOAuth) {
      if (serverOAuthStatus[server.id] != McpOAuthCardStatus.inProgress) {
        await startServerOAuth(server, mcpServers: mcpServers);
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

  /// Perform OAuth logout for a server: clear providers, status, tokens, persist, notify.
  Future<void> oauthLogout(McpServer server) async {
    oauthProviders.remove(server.id);
    serverOAuthStatus.remove(server.id);
    serversNeedingOAuth.removeWhere((s) => s.id == server.id);

    final updatedServer = server.copyWith(
      oauthStatus: McpOAuthStatus.none,
      clearOAuthTokens: true,
      updatedAt: DateTime.now(),
    );
    await DatabaseService.instance.updateMcpServer(updatedServer);
    notifyListeners();
  }

  /// Dismiss all OAuth banners: clear pending servers and status, notify.
  void dismissAll() {
    serversNeedingOAuth.clear();
    serverOAuthStatus.clear();
    notifyListeners();
  }

  /// Clean up resources (kept for API compatibility).
  void close() {
    // No-op: deep link listener has been removed in favour of
    // blocking FlutterWebAuth2 calls.
  }

  /// Dispose of resources
  @override
  void dispose() {
    close();
    super.dispose();
  }
}
