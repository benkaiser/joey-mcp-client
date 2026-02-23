---
# joey_mcp_client_flutter-cjnx
title: Fix McpAppWebView being destroyed/recreated during streaming
status: in-progress
type: bug
created_at: 2026-02-23T03:40:45Z
updated_at: 2026-02-23T03:40:45Z
---

McpAppWebView has no stable Key in the reversed ListView.builder, so every setState during streaming shifts indices and causes Flutter to dispose and recreate the WebView. The evaluateJavascript MissingPluginException occurs because the native WebView is deallocated mid-call. Fix: add ValueKey(message.id) to itemBuilder returns, add AutomaticKeepAliveClientMixin to McpAppWebView.