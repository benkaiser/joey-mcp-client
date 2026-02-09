import 'package:flutter/material.dart';
import '../models/mcp_server.dart';
import 'database_service.dart';
import 'mcp_client_service.dart';
import 'mcp_oauth_service.dart';
import 'mcp_oauth_manager.dart';

/// Delegate class that manages MCP server lifecycle:
/// loading, initializing, refreshing tools, and updating servers.
class McpServerManager {
  List<McpServer> mcpServers = [];
  final Map<String, McpClientService> mcpClients = {};
  final Map<String, List<McpTool>> mcpTools = {};

  /// Reference to the OAuth manager (for creating providers, handling auth).
  McpOAuthManager? oauthManager;

  /// The conversation ID this manager is associated with.
  String? conversationId;

  /// Callback invoked when internal state changes (re-render needed).
  VoidCallback? onStateChanged;

  /// Callback invoked when a server needs OAuth authentication.
  void Function(McpServer server)? onServerNeedsOAuth;

  /// Load MCP servers for the given conversation from the database.
  Future<void> loadMcpServers(String conversationId) async {
    this.conversationId = conversationId;
    try {
      final servers = await DatabaseService.instance.getConversationMcpServers(
        conversationId,
      );
      mcpServers = servers;
      onStateChanged?.call();

      // Initialize MCP clients for each server
      for (final server in servers) {
        await initializeMcpServer(server);
      }
    } catch (e) {
      debugPrint('Failed to load MCP servers: $e');
    }
  }

  /// Initialize a single MCP server, handling OAuth if needed
  Future<void> initializeMcpServer(McpServer server) async {
    final convId = conversationId;
    if (convId == null) return;

    try {
      // Create OAuth provider if server has OAuth tokens
      McpOAuthClientProvider? oauthProvider;

      if (server.oauthStatus != McpOAuthStatus.none ||
          server.oauthTokens != null) {
        oauthProvider = oauthManager?.createOAuthProvider(server);
        if (oauthProvider != null) {
          oauthManager?.oauthProviders[server.id] = oauthProvider;
        }
      }

      final client = McpClientService(
        serverUrl: server.url,
        headers: server.headers,
        oauthProvider: oauthProvider,
      );

      // Set up auth required callback
      client.onAuthRequired = (serverUrl) {
        onServerNeedsOAuth?.call(server);
      };

      // Set up session re-established callback for when server restarts
      client.onSessionReestablished = (newSessionId) {
        debugPrint(
          'MCP: Session re-established for ${server.name}: $newSessionId',
        );
        DatabaseService.instance.updateMcpSessionId(
          convId,
          server.id,
          newSessionId,
        );
        // Refresh tools since the server may have changed
        refreshToolsForServer(server.id);
      };

      // Look up stored session ID for resumption
      final storedSessionId = await DatabaseService.instance.getMcpSessionId(
        convId,
        server.id,
      );
      if (storedSessionId != null) {
        debugPrint('MCP: Attempting to resume session for ${server.name}');
      }

      await client.initialize(sessionId: storedSessionId);

      List<McpTool> tools;
      try {
        tools = await client.listTools();
      } catch (e) {
        // If listing tools fails with an invalid session error, retry with a fresh session
        if (e.toString().toLowerCase().contains('no valid session') ||
            (e.toString().contains('400') &&
                e.toString().toLowerCase().contains('session'))) {
          debugPrint(
            'MCP: Session invalid after initialize for ${server.name}, retrying fresh...',
          );
          await client.close();
          final freshClient = McpClientService(
            serverUrl: server.url,
            headers: server.headers,
            oauthProvider: oauthProvider,
          );
          freshClient.onAuthRequired = client.onAuthRequired;
          freshClient.onSessionReestablished = client.onSessionReestablished;
          await freshClient.initialize(); // No session ID
          tools = await freshClient.listTools();
          // Replace client reference for the rest of setup
          mcpClients[server.id] = freshClient;
          mcpTools[server.id] = tools;
          // Update stored session ID
          await DatabaseService.instance.updateMcpSessionId(
            convId,
            server.id,
            freshClient.sessionId,
          );
          debugPrint(
            'MCP: Fresh session established for ${server.name}: ${freshClient.sessionId}',
          );

          // Update server OAuth status if it was previously pending
          if (server.oauthStatus == McpOAuthStatus.required ||
              server.oauthStatus == McpOAuthStatus.pending) {
            final updatedServer = server.copyWith(
              oauthStatus: McpOAuthStatus.authenticated,
              updatedAt: DateTime.now(),
            );
            await DatabaseService.instance.updateMcpServer(updatedServer);
            final index = mcpServers.indexWhere((s) => s.id == server.id);
            if (index >= 0) {
              mcpServers[index] = updatedServer;
              oauthManager?.serverOAuthStatus.remove(server.id);
              onStateChanged?.call();
            }
          }
          return; // Skip the rest of setup since we've handled it
        }
        rethrow;
      }

      mcpClients[server.id] = client;
      mcpTools[server.id] = tools;

      // Persist the session ID (may be new or same as stored)
      final newSessionId = client.sessionId;
      if (newSessionId != storedSessionId) {
        await DatabaseService.instance.updateMcpSessionId(
          convId,
          server.id,
          newSessionId,
        );
        debugPrint('MCP: Stored session ID for ${server.name}: $newSessionId');
      }

      // Update server OAuth status if it was previously pending
      if (server.oauthStatus == McpOAuthStatus.required ||
          server.oauthStatus == McpOAuthStatus.pending) {
        final updatedServer = server.copyWith(
          oauthStatus: McpOAuthStatus.authenticated,
          updatedAt: DateTime.now(),
        );
        await DatabaseService.instance.updateMcpServer(updatedServer);

        // Update local state
        final index = mcpServers.indexWhere((s) => s.id == server.id);
        if (index >= 0) {
          mcpServers[index] = updatedServer;
          oauthManager?.serverOAuthStatus.remove(server.id);
          onStateChanged?.call();
        }
      }
    } on McpAuthRequiredException catch (e) {
      debugPrint('MCP server ${server.name} requires OAuth: $e');
      onServerNeedsOAuth?.call(server);
    } catch (e) {
      debugPrint('Failed to initialize MCP server ${server.name}: $e');

      // Check if this looks like an auth error
      if (e.toString().contains('401') ||
          e.toString().toLowerCase().contains('unauthorized') ||
          e.toString().toLowerCase().contains('authentication')) {
        onServerNeedsOAuth?.call(server);
      }
    }
  }

  /// Refresh the tools list for a specific MCP server
  Future<void> refreshToolsForServer(String serverId) async {
    final client = mcpClients[serverId];
    if (client == null) return;

    try {
      final tools = await client.listTools();
      mcpTools[serverId] = tools;
      onStateChanged?.call();
      print('Refreshed tools for server $serverId: ${tools.length} tools');
    } catch (e) {
      print('Failed to refresh tools for server $serverId: $e');
    }
  }

  /// Build a server names map for ChatService
  Map<String, String> get serverNames {
    final names = <String, String>{};
    for (final server in mcpServers) {
      names[server.id] = server.name;
    }
    return names;
  }

  /// Close all MCP clients
  Future<void> dispose() async {
    for (final client in mcpClients.values) {
      await client.close();
    }
  }
}
