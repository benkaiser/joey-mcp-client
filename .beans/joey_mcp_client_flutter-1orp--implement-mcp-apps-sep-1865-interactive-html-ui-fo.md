---
# joey_mcp_client_flutter-1orp
title: Implement MCP Apps (SEP-1865) - Interactive HTML UI for MCP tool results
status: completed
type: feature
priority: normal
created_at: 2026-02-23T00:59:36Z
updated_at: 2026-02-23T01:12:45Z
---

Add interactive HTML UI rendering for MCP tool results via sandboxed WebViews. When an MCP server declares UI resources (ui:// scheme) linked to tools via _meta.ui.resourceUri, the app renders the HTML in a WebView with a JSON-RPC bridge for bidirectional communication.