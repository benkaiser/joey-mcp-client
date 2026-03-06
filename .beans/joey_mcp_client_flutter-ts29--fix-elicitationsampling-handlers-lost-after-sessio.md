---
# joey_mcp_client_flutter-ts29
title: Fix elicitation/sampling handlers lost after session re-initialization
status: completed
type: bug
priority: normal
created_at: 2026-03-06T13:14:44Z
updated_at: 2026-03-06T13:14:57Z
---

When freshClient replaces original in McpServerManager, handlers aren't copied. updateServers() skips re-registration for existing server IDs.