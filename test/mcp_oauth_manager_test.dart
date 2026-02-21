import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:joey_mcp_client_flutter/models/mcp_server.dart';
import 'package:joey_mcp_client_flutter/services/mcp_oauth_manager.dart';
import 'package:joey_mcp_client_flutter/widgets/mcp_oauth_card.dart';

void main() {
  // Use an in-memory SQLite database so DatabaseService calls in
  // McpOAuthManager (e.g. updateMcpServer) do not hit the file system.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiInMemory;
  });

  late McpOAuthManager oauthManager;
  late McpServer server;
  late List<McpServer> mcpServers;

  setUp(() {
    oauthManager = McpOAuthManager();
    server = McpServer(
      id: 'test-server-id',
      name: 'Test MCP Server',
      url: 'https://test.example.com/mcp',
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );
    mcpServers = [server];
  });

  tearDown(() {
    oauthManager.dispose();
  });

  group('McpOAuthManager.handleServerNeedsOAuth', () {
    test('adds server to serversNeedingOAuth on first call', () {
      oauthManager.handleServerNeedsOAuth(server, mcpServers);

      expect(oauthManager.serversNeedingOAuth.length, equals(1));
      expect(oauthManager.serversNeedingOAuth.first.id, equals(server.id));
      expect(
        oauthManager.serverOAuthStatus[server.id],
        equals(McpOAuthCardStatus.pending),
      );
    });

    test('marks server as requiring OAuth in the list', () {
      oauthManager.handleServerNeedsOAuth(server, mcpServers);

      expect(
        oauthManager.serversNeedingOAuth.first.oauthStatus,
        equals(McpOAuthStatus.required),
      );
    });

    test('does not add server again when already pending', () {
      oauthManager.handleServerNeedsOAuth(server, mcpServers);
      oauthManager.handleServerNeedsOAuth(server, mcpServers);

      expect(oauthManager.serversNeedingOAuth.length, equals(1));
      expect(
        oauthManager.serverOAuthStatus[server.id],
        equals(McpOAuthCardStatus.pending),
      );
    });

    test('does not add server again when auth is in-progress', () {
      oauthManager.handleServerNeedsOAuth(server, mcpServers);
      oauthManager.serverOAuthStatus[server.id] = McpOAuthCardStatus.inProgress;

      oauthManager.handleServerNeedsOAuth(server, mcpServers);

      expect(oauthManager.serversNeedingOAuth.length, equals(1));
      expect(
        oauthManager.serverOAuthStatus[server.id],
        equals(McpOAuthCardStatus.inProgress),
      );
    });

    // Regression test: after an MCP server disconnects and reconnects it needs
    // to re-authenticate, but the client previously held the server in
    // serversNeedingOAuth with a "completed" status, causing the OAuth banner
    // never to re-appear.
    test(
      're-adds server with pending status after server was previously '
      'completed (reconnect re-auth scenario)',
      () {
        // Simulate the state left by a previous successful OAuth flow: the
        // server is still in serversNeedingOAuth with "completed" status.
        oauthManager.serversNeedingOAuth.add(server);
        oauthManager.serverOAuthStatus[server.id] = McpOAuthCardStatus.completed;

        // Server disconnects and needs OAuth again.
        oauthManager.handleServerNeedsOAuth(server, mcpServers);

        // The OAuth banner must be re-shown.
        expect(oauthManager.serversNeedingOAuth.length, equals(1));
        expect(
          oauthManager.serverOAuthStatus[server.id],
          equals(McpOAuthCardStatus.pending),
        );
      },
    );

    test('fires onServerOAuthRequired callback on first auth', () {
      String? capturedName;
      oauthManager.onServerOAuthRequired = (name) => capturedName = name;

      oauthManager.handleServerNeedsOAuth(server, mcpServers);

      expect(capturedName, equals(server.name));
    });

    test(
      'fires onServerOAuthRequired callback when re-auth is required '
      'after a previously completed OAuth',
      () {
        // Pre-condition: completed OAuth left server in list.
        oauthManager.serversNeedingOAuth.add(server);
        oauthManager.serverOAuthStatus[server.id] = McpOAuthCardStatus.completed;

        String? capturedName;
        oauthManager.onServerOAuthRequired = (name) => capturedName = name;

        oauthManager.handleServerNeedsOAuth(server, mcpServers);

        expect(capturedName, equals(server.name));
      },
    );

    test('does not fire onServerOAuthRequired when already pending', () {
      oauthManager.handleServerNeedsOAuth(server, mcpServers);

      int callCount = 0;
      oauthManager.onServerOAuthRequired = (_) => callCount++;

      // Second call while pending — should be a no-op.
      oauthManager.handleServerNeedsOAuth(server, mcpServers);

      expect(callCount, equals(0));
    });

    test('notifies listeners when server is first added', () {
      int notifyCount = 0;
      oauthManager.addListener(() => notifyCount++);

      oauthManager.handleServerNeedsOAuth(server, mcpServers);

      expect(notifyCount, greaterThan(0));
    });

    test('notifies listeners when completed server is re-added', () {
      oauthManager.serversNeedingOAuth.add(server);
      oauthManager.serverOAuthStatus[server.id] = McpOAuthCardStatus.completed;

      int notifyCount = 0;
      oauthManager.addListener(() => notifyCount++);

      oauthManager.handleServerNeedsOAuth(server, mcpServers);

      expect(notifyCount, greaterThan(0));
    });

    test('does nothing when server is not in mcpServers list', () {
      oauthManager.handleServerNeedsOAuth(server, []);

      expect(oauthManager.serversNeedingOAuth.isEmpty, isTrue);
      expect(oauthManager.serverOAuthStatus.isEmpty, isTrue);
    });
  });

  group('McpOAuthManager.skipServerOAuth', () {
    test('removes server from pending list and clears status', () {
      oauthManager.handleServerNeedsOAuth(server, mcpServers);

      oauthManager.skipServerOAuth(server);

      expect(oauthManager.serversNeedingOAuth.isEmpty, isTrue);
      expect(oauthManager.serverOAuthStatus.containsKey(server.id), isFalse);
    });
  });

  group('McpOAuthManager.removeServer', () {
    test('removes all state for the given server', () {
      oauthManager.handleServerNeedsOAuth(server, mcpServers);

      oauthManager.removeServer(server.id);

      expect(oauthManager.serversNeedingOAuth.isEmpty, isTrue);
      expect(oauthManager.serverOAuthStatus.containsKey(server.id), isFalse);
      expect(oauthManager.oauthProviders.containsKey(server.id), isFalse);
    });
  });

  group('McpOAuthManager.dismissAll', () {
    test('clears all pending servers and their statuses', () {
      oauthManager.handleServerNeedsOAuth(server, mcpServers);
      // Add a second server.
      final server2 = McpServer(
        id: 'server-2',
        name: 'Server 2',
        url: 'https://server2.example.com/mcp',
        createdAt: DateTime(2025),
        updatedAt: DateTime(2025),
      );
      oauthManager.serversNeedingOAuth.add(server2);
      oauthManager.serverOAuthStatus[server2.id] = McpOAuthCardStatus.pending;

      oauthManager.dismissAll();

      expect(oauthManager.serversNeedingOAuth.isEmpty, isTrue);
      expect(oauthManager.serverOAuthStatus.isEmpty, isTrue);
    });

    test('notifies listeners', () {
      oauthManager.handleServerNeedsOAuth(server, mcpServers);

      int notifyCount = 0;
      oauthManager.addListener(() => notifyCount++);

      oauthManager.dismissAll();

      expect(notifyCount, greaterThan(0));
    });
  });
}
