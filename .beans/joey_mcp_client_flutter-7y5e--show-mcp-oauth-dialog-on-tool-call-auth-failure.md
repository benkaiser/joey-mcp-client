---
# joey_mcp_client_flutter-7y5e
title: Show MCP OAuth dialog on tool call auth failure
status: completed
type: bug
priority: normal
created_at: 2026-02-09T03:00:32Z
updated_at: 2026-02-09T03:02:22Z
---

When a tool call fails with an unauthorized error, the app should show the MCP OAuth dialog again so the user can re-authenticate, instead of just failing silently.