---
# joey_mcp_client_flutter-bmf7
title: MCP session resumption via stored session ID
status: completed
type: feature
priority: normal
created_at: 2026-02-05T13:55:35Z
updated_at: 2026-02-08T10:18:22Z
---

Implement MCP session resumption by storing the session ID on conversations and reusing it when re-establishing connections.

## Implementation

1. Store the MCP session ID on the Conversation model when a connection is established
2. When reconnecting to an MCP server for a conversation, pass the stored session ID to resume the session
3. Handle session expiration gracefully (clear stored ID if server rejects it)

## Example Usage
```dart
// Resume session
final transport = StreamableHTTPClientTransport(
  Uri.parse('http://localhost:3000'),
  sessionId: 'existing-session-id',  // Resume this session
);
```

The mcp_dart library already supports this via StreamableHttpClientTransportOptions.sessionId parameter.