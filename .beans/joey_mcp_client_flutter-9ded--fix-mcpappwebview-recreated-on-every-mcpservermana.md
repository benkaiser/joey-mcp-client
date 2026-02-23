---
# joey_mcp_client_flutter-9ded
title: Fix McpAppWebView recreated on every McpServerManager notifyListeners
status: in-progress
type: bug
created_at: 2026-02-23T03:45:05Z
updated_at: 2026-02-23T03:45:05Z
---

McpServerManager.loadMcpServers() fires notifyListeners() multiple times during init (line 46 before connect, line 212 after connect), each triggering setState on ChatScreen which fully reconstructs MessageList (StatelessWidget). Even with ValueKey(message.id), the WebView's Element tree is replaced because MessageList is a new widget instance each time. Fix: use GlobalKey per message ID to preserve McpAppWebView state across parent reconstructions.