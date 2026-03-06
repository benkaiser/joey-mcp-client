---
# joey_mcp_client_flutter-4p94
title: Add MCP server ping/health status to settings
status: completed
type: feature
priority: normal
created_at: 2026-03-01T23:28:08Z
updated_at: 2026-03-01T23:29:10Z
---

Add ping/health check functionality to MCP servers settings screen:

1. When loading the MCP servers screen, ping all configured servers and show status dots:
   - Green dot: server responded to ping successfully
   - Red dot: server failed to respond to ping  
   - Empty/grey dot: waiting for ping response

2. In the add/edit MCP server dialog, when typing a URL:
   - Debounce URL input (300ms)
   - When a valid URL is entered, send a ping to check reachability
   - Show status feedback beneath the URL field (reachable/unreachable/checking)

Implementation approach:
- Use raw HTTP POST with JSON-RPC ping method (like McpOAuthService.checkAuthRequired does)
- This avoids needing a full MCP client connection just for health checks
- Add a static ping utility method that can be reused

## Checklist
- [x] Create a static MCP ping utility service/method
- [x] Add ping status tracking to McpServersScreen (server list)
- [x] Add status dots to each server in the list
- [x] Add debounced URL ping in the add/edit dialog
- [x] Show ping status feedback below URL field in dialog
- [x] Run flutter analyze to verify no errors