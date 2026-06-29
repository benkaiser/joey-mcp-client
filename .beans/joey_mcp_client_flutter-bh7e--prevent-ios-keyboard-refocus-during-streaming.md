---
# joey_mcp_client_flutter-bh7e
title: Prevent iOS keyboard refocus during streaming
status: completed
type: bug
priority: normal
created_at: 2026-06-29T04:40:13Z
updated_at: 2026-06-29T04:41:30Z
---

On iOS, the chat input keeps focus while messages stream, causing the keyboard to pop up. Suppress automatic input focus/refocus during active streaming/loading without breaking normal send/edit behavior.