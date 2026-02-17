---
# joey_mcp_client_flutter-zw1x
title: Update ChatScreen for new McpDebugScreen API
status: completed
type: task
priority: normal
created_at: 2026-02-16T04:12:22Z
updated_at: 2026-02-16T04:13:26Z
---

Update ChatScreen to pass serverManager and oauthManager to the new McpDebugScreen constructor. Remove now-unused _mcpStateNotifier, _notifyMcpStateChanged, _connectMcpServer, _disconnectMcpServer, _logoutMcpServerOAuth, and _loginMcpServerOAuth from ChatScreen since the debug screen now handles these directly.