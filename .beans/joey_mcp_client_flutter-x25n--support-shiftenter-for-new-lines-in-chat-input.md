---
# joey_mcp_client_flutter-x25n
title: Support Shift+Enter for new lines in chat input
status: completed
type: task
priority: normal
created_at: 2026-02-09T09:31:09Z
updated_at: 2026-02-09T09:31:28Z
---

Change chat input to send on Enter but insert newline on Shift+Enter. Use FocusNode.onKeyEvent to intercept key events.