---
# joey_mcp_client_flutter-qco0
title: Implement ui/update-model-context for MCP Apps
status: completed
type: feature
priority: normal
created_at: 2026-02-23T12:48:19Z
updated_at: 2026-02-23T12:49:49Z
---

When an MCP App WebView sends ui/update-model-context, store the context and:
1. Persist it as a new mcpAppContext message in the DB (linked to its parent tool result)
2. Render it inline just below the WebView (compact when thinking hidden, full when shown)
3. Send it to the LLM as a user role message on future turns

## Checklist
- [ ] Add mcpAppContext to MessageRole enum and toApiMessage() in message.dart
- [ ] Add mcpAppContext case in thinking_indicator.dart
- [ ] Add onUpdateModelContext callback in mcp_app_webview.dart
- [ ] Filter mcpAppContext messages and render inline in message_list.dart
- [ ] Add _handleUpdateModelContext handler in chat_screen.dart
- [ ] Run flutter analyze
- [ ] Run flutter test