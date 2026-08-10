import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:joey_mcp_client_flutter/models/mcp_server.dart';
import 'package:joey_mcp_client_flutter/services/chat_service.dart';
import 'package:joey_mcp_client_flutter/services/mcp_client_service.dart';
import 'package:joey_mcp_client_flutter/services/openrouter_service.dart';

McpServer _server({required String id, String? systemPrompt}) {
  final now = DateTime.now();
  return McpServer(
    id: id,
    name: 'Server $id',
    url: 'https://example.com/$id',
    createdAt: now,
    updatedAt: now,
    systemPrompt: systemPrompt,
  );
}

ChatService _chatService({
  required Map<String, McpClientService> clients,
  required Map<String, String> prompts,
}) {
  return ChatService(
    openRouterService: OpenRouterService(),
    mcpClients: clients,
    mcpTools: {},
    serverSystemPrompts: prompts,
  );
}

McpClientService _client(String id) =>
    McpClientService(serverUrl: 'https://example.com/$id');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'system_prompt': 'Base prompt.'});
  });

  group('McpServer.systemPrompt persistence', () {
    test('round-trips through toMap/fromMap', () {
      final server = _server(id: 'a', systemPrompt: 'Be terse.');
      final restored = McpServer.fromMap(server.toMap());
      expect(restored.systemPrompt, 'Be terse.');
    });

    test('is null when absent (older exports/rows)', () {
      final map = _server(id: 'a').toMap()..remove('systemPrompt');
      expect(McpServer.fromMap(map).systemPrompt, isNull);
    });

    test('copyWith can set and clear the prompt', () {
      final server = _server(id: 'a', systemPrompt: 'Be terse.');
      expect(server.copyWith(systemPrompt: 'Be verbose.').systemPrompt,
          'Be verbose.');
      expect(server.copyWith().systemPrompt, 'Be terse.');
      expect(server.copyWith(clearSystemPrompt: true).systemPrompt, isNull);
    });
  });

  group('ChatService.buildSystemPrompt', () {
    test('returns the base prompt when no servers have prompts', () async {
      final service = _chatService(clients: {'a': _client('a')}, prompts: {});
      expect(await service.buildSystemPrompt(), 'Base prompt.');
      service.dispose();
    });

    test('appends prompts of connected servers joined by newlines', () async {
      final service = _chatService(
        clients: {'a': _client('a'), 'b': _client('b')},
        prompts: {'a': 'Server A rules.', 'b': 'Server B rules.'},
      );
      expect(
        await service.buildSystemPrompt(),
        'Base prompt.\nServer A rules.\nServer B rules.',
      );
      service.dispose();
    });

    test('ignores prompts for servers that are not connected', () async {
      final service = _chatService(
        clients: {'a': _client('a')},
        prompts: {'a': 'Server A rules.', 'b': 'Server B rules.'},
      );
      expect(await service.buildSystemPrompt(), 'Base prompt.\nServer A rules.');
      service.dispose();
    });

    test('ignores blank prompts', () async {
      final service = _chatService(
        clients: {'a': _client('a')},
        prompts: {'a': '   '},
      );
      expect(await service.buildSystemPrompt(), 'Base prompt.');
      service.dispose();
    });

    test('omits an empty base prompt', () async {
      SharedPreferences.setMockInitialValues({'system_prompt': ''});
      final service = _chatService(
        clients: {'a': _client('a')},
        prompts: {'a': 'Server A rules.'},
      );
      expect(await service.buildSystemPrompt(), 'Server A rules.');
      service.dispose();
    });

    test('updateServers refreshes the per-server prompts', () async {
      final clients = {'a': _client('a')};
      final service = _chatService(clients: clients, prompts: {});
      service.updateServers(
        mcpClients: clients,
        mcpTools: {},
        serverNames: {'a': 'Server a'},
        serverSystemPrompts: {'a': 'Server A rules.'},
      );
      expect(await service.buildSystemPrompt(), 'Base prompt.\nServer A rules.');

      service.updateServers(
        mcpClients: clients,
        mcpTools: {},
        serverNames: {'a': 'Server a'},
        serverSystemPrompts: {},
      );
      expect(await service.buildSystemPrompt(), 'Base prompt.');
      service.dispose();
    });
  });
}
