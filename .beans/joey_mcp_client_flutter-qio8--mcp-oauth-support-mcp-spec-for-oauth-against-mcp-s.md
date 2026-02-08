---
# joey_mcp_client_flutter-qio8
title: MCP OAuth - Support MCP spec for oauth against MCP servers
status: completed
type: feature
priority: normal
created_at: 2026-02-05T13:55:27Z
updated_at: 2026-02-08T04:28:19Z
---

Implement OAuth authentication support for MCP servers according to the MCP specification.

## Checklist

- [x] Create McpOAuthService for handling the full OAuth 2.1 flow per MCP spec
  - Protected Resource Metadata discovery (RFC 9728)
  - Authorization Server Metadata discovery (RFC 8414)
  - PKCE code challenge generation (S256)
  - Token exchange and refresh
- [x] Create McpOAuthClientProvider implementing mcp_dart OAuthClientProvider interface
  - Token loading/saving with persistence
  - Automatic token refresh
  - Redirect to authorization
- [x] Extend McpServer model with OAuth fields
  - oauthStatus (none, required, pending, authenticated, expired, failed)
  - oauthTokens (access token, refresh token, expiry, etc.)  
  - oauthClientId for custom client registration
- [x] Update database schema (version 10) for OAuth fields
- [x] Modify McpClientService to accept OAuthClientProvider
  - Handle UnauthorizedError and 401 responses
  - Callback for auth required events
- [x] Create UI components for OAuth prompts
  - McpOAuthCard for individual server auth status
  - McpOAuthBanner for banner showing servers needing auth
- [x] Integrate OAuth flow in ChatScreen
  - Deep link listener   - Deep link listener   - Deep link listener   th OA  - Deep link listener   - Deep link listener   -ion af  - Deep link listener   - ansport accepts an authProvider in StreamableHttpClientTransportOptions that handles the OAuth flow automatically.
