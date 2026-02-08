# MCP OAuth Architecture

## Overview

Joey MCP Client implements OAuth 2.1 authentication for MCP (Model Context Protocol) servers that require user authorization. The implementation follows the MCP Authorization specification and supports both PKCE-based flows and legacy client secret authentication.

## Architecture Components

### 1. Service Layer (`lib/services/mcp_oauth_service.dart`)

#### McpOAuthService
The core OAuth service that handles all OAuth operations:

- **Discovery**: Implements RFC 9728 (Protected Resource Metadata) and RFC 8414 (Authorization Server Metadata)
  - Discovers OAuth endpoints from well-known URIs
  - Validates PKCE support (S256 code challenge method)
  - Caches metadata to reduce network calls

- **PKCE Flow**: Full OAuth 2.1 PKCE implementation
  - Generates cryptographically secure code verifiers (128 characters)
  - Creates S256 code challenges using SHA-256
  - Stores state parameters with expiration (10 minutes)
  - Validates state on callback to prevent CSRF attacks

- **Token Management**:
  - Exchanges authorization codes for access tokens
  - Supports token refresh with refresh tokens
  - Handles both JSON and URL-encoded form responses
  - Validates token responses and provides detailed error messages

- **Client Secret Support** (optional):
  - Allows client secrets for providers that require them (e.g., GitHub)
  - Security warning: Not recommended for mobile apps but necessary for some providers

#### McpOAuthClientProvider
Implements `mcp_dart`'s `OAuthClientProvider` interface:

- Bridges between Joey's OAuth implementation and mcp_dart library
- Automatically refreshes expired tokens
- Loads and saves tokens via callbacks
- Stores client credentials (ID and optional secret)

#### Key Classes

**McpOAuthTokens**: Token storage with expiration tracking
- `accessToken`: Bearer token for API requests
- `refreshToken`: Optional token for refreshing access
- `expiresAt`: Expiration timestamp (considers 30s buffer)
- `tokenType`: Typically "bearer"
- `scope`: OAuth scopes granted

**McpOAuthState**: Tracks in-flight OAuth requests
- `codeVerifier`: PKCE code verifier
- `state`: CSRF protection parameter
- `resourceUrl`: MCP server URL
- `authServerUrl`: OAuth provider URL
- `clientId`: Client identifier
- `redirectUri`: Callback URI
- Expires after 10 minutes

### 2. Data Model (`lib/models/mcp_server.dart`)

#### McpOAuthStatus Enum
Tracks server OAuth state:
- `none`: No OAuth configured or required
- `required`: OAuth needed but not authenticated
- `pending`: Waiting for user to initiate auth
- `authenticated`: Successfully authenticated
- `expired`: Token expired, needs refresh
- `failed`: Authentication failed

#### McpServer OAuth Fields
- `oauthStatus`: Current OAuth state
- `oauthTokens`: Stored tokens (encrypted in database)
- `oauthClientId`: Optional custom client ID (default: "joey-mcp-client")
- `oauthClientSecret`: Optional client secret (not recommended)

### 3. Database Layer (`lib/services/database_service.dart`)

**Schema Version 11** - OAuth support:
```sql
CREATE TABLE mcp_servers (
  ...
  oauthStatus TEXT DEFAULT 'none',
  oauthTokens TEXT,
  oauthClientId TEXT,
  oauthClientSecret TEXT
)
```

- Tokens stored as JSON strings
- Status persisted across app restarts
- Automatic migration from v10 to v11

### 4. UI Components

#### McpOAuthBanner (`lib/widgets/mcp_oauth_card.dart`)
Top-of-chat banner showing servers needing authentication:
- Lists server names requiring auth
- Single "Sign In" button to start OAuth flow
- User-controlled: No auto-launch of browser
- Can be dismissed

#### McpServerDialog (`lib/screens/mcp_servers_screen.dart`)
Configuration UI for OAuth settings:
- **OAuth Client ID** field with helper text showing default
- **OAuth Client Secret** field (password-masked) with security warning
- Info dialog showing:
  - Redirect URIs that must be registered
  - Step-by-step setup instructions
  - Default client ID documentation

#### McpOAuthCardStatus
Visual states for OAuth flow:
- `pending`: Blue - waiting for user action
- `inProgress`: Orange - browser opened, waiting for completion
- `completed`: Green - successfully authenticated
- `failed`: Red - error with retry option

### 5. Integration Layer (`lib/screens/chat_screen.dart`)

#### OAuth Flow Management

**Initialization**:
1. Load MCP servers from database
2. Check OAuth status for each server
3. Create OAuth providers for servers with tokens
4. Attempt to initialize MCP clients
5. Catch auth errors and mark servers as needing OAuth

**Authentication Flow**:
1. User clicks "Sign In" in banner
2. `_startServerOAuth()` called
3. Build authorization URL with PKCE params
4. Launch system browser
5. User authenticates with OAuth provider
6. Redirect to `joey://mcp-oauth/callback?code=...&state=...`
7. Deep link listener catches callback
8. `_handleMcpOAuthCallback()` extracts params
9. Exchange code for tokens with client secret if needed
10. Save tokens to database
11. Reinitialize MCP client with new tokens
12. Update UI to show success

**Deep Link Handling**:
- Primary: `joey://mcp-oauth/callback`
- Fallback: `https://openrouterauth.benkaiser.dev/api/mcp-oauth`
- Configured via `app_links` package

## OAuth Flow Diagrams

### PKCE Authorization Code Flow

```
App                     MCP Server              OAuth Provider
 |                           |                         |
 |-- Connect to MCP -------->|                         |
 |<-- 401 Unauthorized ------| (WWW-Authenticate)      |
 |                           |                         |
 |-- Discover Metadata ----->|                         |
 |<-- OAuth Server URL ------| (well-known)            |
 |                           |                         |
 |-- Discover Auth Server ----------------------->     |
 |<-- Endpoints (auth, token) ---------------------    |
 |                           |                         |
 |-- Generate PKCE params    |                         |
 |   (verifier, challenge)   |                         |
 |                           |                         |
 |-- Build auth URL --------------------------->|      |
 |   + code_challenge (S256) |                   |      |
 |   + state (CSRF)          |                   |      |
 |   + client_id             |                   |      |
 |                           |                   |      |
 |-- Launch browser -------------------------------->  |
 |                           |                   |      |
 |                           |      User authenticates |
 |                           |                   |      |
 |<-- Redirect joey://... <------------------------|   |
 |   + code                  |                   |      |
 |   + state                 |                   |      |
 |                           |                   |      |
 |-- Exchange code for token ------------------->|     |
 |   + code                  |                   |      |
 |   + code_verifier (PKCE)  |                   |      |
 |   + client_id             |                   |      |
 |   + client_secret (if req)|                   |      |
 |                           |                   |      |
 |<-- Access + Refresh token ---------------------|    |
 |                           |                   |      |
 |-- Save tokens to DB       |                   |      |
 |                           |                   |      |
 |-- Connect with token ----->|                  |      |
 |<-- Success ----------------| (200 OK)         |      |
```

### Token Refresh Flow

```
App                     MCP Server              OAuth Provider
 |                           |                         |
 |-- Request with token ---->|                         |
 |<-- 401 Token expired -----| (WWW-Authenticate)      |
 |                           |                         |
 |-- Check refresh token     |                         |
 |   available?              |                         |
 |                           |                         |
 |-- POST /token --------------------------->|         |
 |   + grant_type=refresh_token              |         |
 |   + refresh_token         |               |         |
 |   + client_id             |               |         |
 |   + client_secret (if req)|               |         |
 |                           |               |         |
 |<-- New access token ----------------------|         |
 |                           |               |         |
 |-- Save new tokens         |               |         |
 |                           |               |         |
 |-- Retry request --------->|               |         |
 |<-- Success ---------------| (200 OK)      |         |
```

## Configuration

### Default Client Credentials
- **Client ID**: `joey-mcp-client`
- **Redirect URIs**:
  - Primary: `joey://mcp-oauth/callback`
  - Fallback: `https://openrouterauth.benkaiser.dev/api/mcp-oauth`

### Per-Server Configuration
Users can override defaults in MCP Server settings:
- Custom Client ID (for pre-registered OAuth apps)
- Client Secret (for providers requiring it)

### Example: GitHub OAuth Setup

1. **Register OAuth App**:
   - Go to GitHub Settings → Developer settings → OAuth Apps
   - Create new OAuth App
   - Set Authorization callback URL: `joey://mcp-oauth/callback`
   - Enable device flow (recommended for security)

2. **Configure in Joey**:
   - Edit MCP server
   - Enter Client ID from GitHub
   - Enter Client Secret (required by GitHub even with PKCE)
   - Save

3. **Authenticate**:
   - Click "Sign In" in chat
   - Complete GitHub OAuth
   - Return to app

## Security Considerations

### PKCE (Proof Key for Code Exchange)
- **Required** by MCP spec for public clients
- Prevents authorization code interception attacks
- Uses S256 (SHA-256) code challenge method
- Code verifier: 128 random characters from unreserved set

### Client Secrets
- **Not recommended** for mobile apps (can be extracted)
- Only use when OAuth provider requires it
- Stored encrypted in SQLite database
- UI shows security warning when configured

### State Parameter
- Random 32-byte value for CSRF protection
- Validated on callback
- Expires after 10 minutes
- Prevents authorization code injection

### Token Storage
- Tokens stored in SQLite database
- Automatic token refresh when expired
- 30-second expiration buffer
- Cleared on auth failure

### Deep Link Security
- Custom scheme: `joey://` prevents web interception
- HTTPS fallback for providers not supporting custom schemes
- State validation on all callbacks

## Error Handling

### Discovery Errors
- Falls back through multiple well-known URI patterns
- Clear error messages for missing metadata
- Validates PKCE support before proceeding

### Token Exchange Errors
- Handles both JSON and URL-encoded responses
- Includes full raw response in error messages
- Specific error codes for debugging

### Network Errors
- 30-second timeouts for all HTTP requests
- Retry logic for expired tokens
- User-friendly error messages in UI

## Testing

### Integration Tests
Located in `integration_test/mcp_integration_test.dart`:
- OAuth flow simulation
- Token refresh scenarios
- Error handling validation

### Manual Testing Checklist
1. ✓ Server requires OAuth → Banner appears
2. ✓ Click "Sign In" → Browser opens
3. ✓ Complete OAuth → Returns to app
4. ✓ Token saved → Server connects
5. ✓ Token expires → Auto-refresh works
6. ✓ Refresh fails → Shows error, allows retry

## Future Enhancements

### Potential Improvements
- **Device Flow**: Full implementation for better mobile security
- **Token Encryption**: Encrypt tokens at rest with device keychain
- **Multi-Account**: Support multiple OAuth accounts per server
- **Scope Management**: UI for requesting specific scopes
- **Token Revocation**: Implement OAuth token revocation on logout
- **Biometric Auth**: Require biometric confirmation for token use

### Standards Compliance
Currently implements:
- ✓ RFC 6749: OAuth 2.0 Authorization Framework
- ✓ RFC 7636: PKCE
- ✓ RFC 8414: Authorization Server Metadata
- ✓ RFC 9728: Protected Resource Metadata
- ✓ OAuth 2.1 (draft)

Planned:
- ☐ RFC 7009: Token Revocation
- ☐ RFC 8628: Device Authorization Grant (device flow)
- ☐ RFC 9449: DPoP (Demonstrating Proof of Possession)

## References

- [MCP Authorization Spec](https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/authentication/)
- [OAuth 2.1](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-v2-1-11)
- [RFC 7636 - PKCE](https://datatracker.ietf.org/doc/html/rfc7636)
- [RFC 8414 - AS Metadata](https://datatracker.ietf.org/doc/html/rfc8414)
- [RFC 9728 - Protected Resource Metadata](https://datatracker.ietf.org/doc/html/rfc9728)
