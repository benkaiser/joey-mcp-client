---
# joey_mcp_client_flutter-qio8
title: MCP OAuth - Support MCP spec for oauth against MCP servers
status: todo
type: feature
created_at: 2026-02-05T13:55:27Z
updated_at: 2026-02-05T13:55:27Z
---

Implement OAuth authentication support for MCP servers according to the MCP specification.

The mcp_dart library already has OAuth support via OAuthClientProvider. Need to:
1. Implement OAuthClientProvider interface for the app
2. Store and manage OAuth tokens securely
3. Handle redirectToAuthorization flow
4. Exchange authorization codes for tokens
5. Integrate with StreamableHttpClientTransportOptions.authProvider

Reference: The transport accepts an authProvider in StreamableHttpClientTransportOptions that handles the OAuth flow automatically.