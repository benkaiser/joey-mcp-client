// Validation for the mcp_dart 2.4.0 upgrade: RFC 7591 Dynamic Client
// Registration (DCR) in McpOAuthService, and MCP 2026-07-28 client behavior
// (server/discover negotiation, input_required elicitation, and non-object
// structured tool results) exercised through Joey's real McpClientService
// against a strict `require2026` Streamable HTTP server.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'package:joey_mcp_client_flutter/models/elicitation.dart'
    as app_elicitation;
import 'package:joey_mcp_client_flutter/services/mcp_client_service.dart';
import 'package:joey_mcp_client_flutter/services/mcp_oauth_service.dart';

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  group('RFC 7591 Dynamic Client Registration (McpOAuthService)', () {
    late HttpServer server;
    late int port;
    Map<String, dynamic>? capturedRegistrationBody;

    setUp(() async {
      capturedRegistrationBody = null;
      port = await _freePort();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      final base = 'http://localhost:$port';

      server.listen((HttpRequest req) async {
        final path = req.uri.path;
        void json(Object body, {int status = 200}) {
          req.response.statusCode = status;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(body));
        }

        // Protected Resource Metadata (RFC 9728) for the DCR-capable resource.
        if (path == '/.well-known/oauth-protected-resource/mcp') {
          json({
            'resource': '$base/mcp',
            'authorization_servers': ['$base/as-dcr'],
            'scopes_supported': ['tools:read'],
          });
        }
        // PRM for a resource whose AS does NOT support DCR.
        else if (path == '/.well-known/oauth-protected-resource/nodcr') {
          json({
            'resource': '$base/nodcr',
            'authorization_servers': ['$base/as-nodcr'],
            'scopes_supported': ['tools:read'],
          });
        }
        // Authorization Server Metadata (RFC 8414) WITH a registration endpoint.
        else if (path == '/.well-known/oauth-authorization-server/as-dcr') {
          json({
            'issuer': '$base/as-dcr',
            'authorization_endpoint': '$base/authorize',
            'token_endpoint': '$base/token',
            'registration_endpoint': '$base/register',
            'code_challenge_methods_supported': ['S256'],
            'scopes_supported': ['tools:read'],
          });
        }
        // AS metadata WITHOUT a registration endpoint (DCR unsupported).
        else if (path == '/.well-known/oauth-authorization-server/as-nodcr') {
          json({
            'issuer': '$base/as-nodcr',
            'authorization_endpoint': '$base/authorize',
            'token_endpoint': '$base/token',
            'code_challenge_methods_supported': ['S256'],
          });
        }
        // RFC 7591 registration endpoint.
        else if (path == '/register' && req.method == 'POST') {
          final body = await utf8.decoder.bind(req).join();
          capturedRegistrationBody =
              jsonDecode(body) as Map<String, dynamic>;
          json({
            'client_id': 'dcr-generated-client-id',
            'client_secret': 'dcr-secret',
            'token_endpoint_auth_method': 'none',
          }, status: 201);
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('registers a client and returns the issued client_id', () async {
      final service = McpOAuthService();
      final registration =
          await service.registerClient(serverUrl: 'http://localhost:$port/mcp');

      expect(registration, isNotNull);
      expect(registration!.clientId, 'dcr-generated-client-id');
      expect(registration.clientSecret, 'dcr-secret');

      // Verify the RFC 7591 request payload.
      expect(capturedRegistrationBody, isNotNull);
      expect(capturedRegistrationBody!['redirect_uris'],
          contains('joey://mcp-oauth/callback'));
      expect(capturedRegistrationBody!['grant_types'],
          containsAll(['authorization_code', 'refresh_token']));
      expect(capturedRegistrationBody!['response_types'], contains('code'));
    });

    test('the registered client_id is usable in the authorization URL',
        () async {
      final service = McpOAuthService();
      final registration =
          await service.registerClient(serverUrl: 'http://localhost:$port/mcp');
      final authUrl = await service.buildAuthorizationUrl(
        serverUrl: 'http://localhost:$port/mcp',
        clientId: registration!.clientId,
        clientSecret: registration.clientSecret,
      );

      final uri = Uri.parse(authUrl);
      expect(uri.queryParameters['client_id'], 'dcr-generated-client-id');
      expect(uri.queryParameters['code_challenge_method'], 'S256');
      expect(uri.queryParameters['response_type'], 'code');
    });

    test('returns null when the auth server does not advertise DCR', () async {
      final service = McpOAuthService();
      final registration = await service.registerClient(
        serverUrl: 'http://localhost:$port/nodcr',
      );
      expect(registration, isNull);
    });
  });

  group('MCP 2026-07-28 client behavior (McpClientService, strict server)', () {
    late StreamableMcpServer httpServer;
    late int port;

    setUp(() async {
      port = await _freePort();
      httpServer = StreamableMcpServer(
        serverFactory: (sessionId) => _createStrictGreetingServer(),
        host: 'localhost',
        port: port,
        path: '/mcp',
        protocol: McpProtocol.require2026,
      );
      await httpServer.start();
    });

    tearDown(() async {
      await httpServer.stop();
    });

    test(
        'negotiates 2026-07-28, routes input_required elicitation, and handles '
        'a non-object structured result without crashing', () async {
      final client = McpClientService(serverUrl: 'http://localhost:$port/mcp');

      var elicitationFired = false;
      String? elicitationMessage;
      client.onElicitationRequest = (request, sendComplete) async {
        elicitationFired = true;
        elicitationMessage = request.message;
        await sendComplete(
          request.id,
          app_elicitation.ElicitationAction.accept,
          {'name': 'Joey'},
        );
      };

      await client.initialize();

      final tools = await client.listTools();
      expect(tools.map((t) => t.name), contains('personalized_greeting'));

      final result =
          await client.callTool('personalized_greeting', <String, dynamic>{});

      // The server embeds an elicitation as an input_required round-trip.
      expect(elicitationFired, isTrue);
      expect(elicitationMessage, contains('name'));

      // Non-object (string-root) structured content must not crash the wrapper;
      // Joey reads structuredContent as Map?, which is null for a string root.
      expect(result.isError == true, isFalse);
      expect(result.structuredContent, isNull);

      await client.close();
    });
  });
}

/// Builds a strict MCP 2026-07-28 server exposing a greeting tool that requires
/// an elicitation round-trip and returns a non-object structured result.
McpServer _createStrictGreetingServer() {
  final server = McpServer(
    const Implementation(name: 'strict-greeting-server', version: '1.0.0'),
    options: const McpServerOptions(
      protocol: McpProtocol.require2026,
      capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
    ),
  );

  server.registerStatelessTool(
    'personalized_greeting',
    description: 'Collect a name, then return a personalized greeting.',
    inputSchema: JsonSchema.object(properties: {}),
    outputJsonSchema: JsonSchema.string(),
    callback: (args, extra) async {
      final profileResponse = extra.inputResponses?['profile'];
      if (profileResponse == null) {
        return InputRequiredResult(
          requestState: 'greeting-v1',
          inputRequests: {
            'profile': InputRequest.elicit(
              ElicitRequest.form(
                message: 'What name should the greeting use?',
                requestedSchema: JsonSchema.object(
                  properties: {'name': JsonSchema.string(minLength: 1)},
                  required: ['name'],
                ),
              ),
            ),
          },
        );
      }

      final elicitation = ElicitResult.fromJson(profileResponse.toJson());
      final name = elicitation.content?['name'];
      if (name is! String || name.isEmpty) {
        throw McpError(
          ErrorCode.invalidParams.value,
          'The profile response must contain a name.',
        );
      }
      return CallToolResult.fromStructuredString('Hello, $name!');
    },
  );

  return server;
}
