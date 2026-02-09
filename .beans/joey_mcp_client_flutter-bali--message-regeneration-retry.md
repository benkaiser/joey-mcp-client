---
# joey_mcp_client_flutter-bali
title: Message regeneration (retry)
status: completed
type: feature
priority: normal
created_at: 2026-02-09T09:55:40Z
updated_at: 2026-02-09T10:33:24Z
---

Add a 'regenerate last response' button so users can retry the AI's response without editing or deleting messages. This is one of the most-used features in ChatGPT/Claude.

## Checklist
- [x] Add regenerate button on the last assistant message (e.g. refresh icon in action buttons)
- [x] Delete the last assistant message (and any associated tool call/result messages from that turn)
- [x] Re-send the conversation to get a new response
- [x] Optionally allow regenerating with a different model (deferred to joey_mcp_client_flutter-95e8)
- [x] Disable regenerate while a response is currently streaming