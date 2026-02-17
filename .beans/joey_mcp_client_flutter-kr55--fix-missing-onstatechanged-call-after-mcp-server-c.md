---
# joey_mcp_client_flutter-kr55
title: Fix missing onStateChanged call after MCP server connect
status: completed
type: bug
priority: normal
created_at: 2026-02-16T04:50:56Z
updated_at: 2026-02-16T04:51:14Z
---

McpServerManager.initializeMcpServer adds the client to mcpClients on line 158 but doesn't call onStateChanged unless OAuth status needs updating. This means ChatScreen never rebuilds and the command palette status dots stay stale (red).