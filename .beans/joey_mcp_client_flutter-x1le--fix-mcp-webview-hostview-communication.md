---
# joey_mcp_client_flutter-x1le
title: Fix MCP WebView host→view communication
status: completed
type: bug
priority: normal
created_at: 2026-02-23T03:59:57Z
updated_at: 2026-02-23T04:06:36Z
---

The MCP App View uses PostMessageTransport which listens via window.addEventListener('message') and checks event.source === window.parent. But our Flutter host sends notifications via evaluateJavascript('__mcpBridgeNotification(...)') which dispatches to __mcpViewHandler — a callback the view never registers. This means ALL host→view messages (ui/initialize response, tool-input, tool-result) are silently dropped. Fix: dispatch host→view messages as MessageEvents on the window instead.