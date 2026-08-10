---
# joey_mcp_client_flutter-a08m
title: Upgrade mcp_dart to upstream 2.4.0 with native DCR
status: completed
type: feature
priority: normal
created_at: 2026-08-10T00:57:49Z
updated_at: 2026-08-10T01:12:28Z
---

Switch from the benkaiser/mcp_dart fork (based on 1.2.2) to upstream mcp_dart 2.4.0 to gain native OAuth 2.1 DCR support and the MCP 2026-07-28 dual-era protocol. Added RFC 7591 Dynamic Client Registration in McpOAuthService (persisting client_id to the McpServer so it registers once), since upstream native DCR never surfaces the client_id for persistence. Tool-call error handling was already compatible with the new CallToolResult(isError:true) contract. Validated against strict require2026 servers.

## Checklist
- [x] Point pubspec.yaml at upstream mcp_dart ^2.4.0; run pub get
- [x] Fix compile errors from 1.2.2 -> 2.4.0 API changes (source-compatible, 0 errors)
- [x] Confirm forks additionalProperties patch is obsolete (upstream Draft 2020-12 engine handles it)
- [x] Add RFC 7591 DCR to McpOAuthService (registerClient)
- [x] Persist DCR client_id/client_secret onto McpServer so registration happens once
- [x] Audit tool-call error handling (already converts isError result + thrown McpError uniformly)
- [x] Confirm non-object structuredContent handled gracefully (null, consumers null-safe)
- [x] Remove dead finishAuth passthrough; silence legacy elicitationId deprecations
- [x] flutter analyze clean
- [x] flutter test passes (156 tests)
- [x] Validate 2026-07-28 negotiation + input_required + non-object result via McpClientService against strict require2026 server
- [x] Validate DCR against mock RFC 8414/9728/7591 server
- [x] Ran upstream strict stdio example on 2.4.0 (Negotiated 2026-07-28, Hello Ada)