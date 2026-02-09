---
# joey_mcp_client_flutter-qlfw
title: Export/share conversations
status: todo
type: feature
created_at: 2026-02-09T09:55:32Z
updated_at: 2026-02-09T09:55:32Z
---

Add the ability to export or share conversations. Currently users can only copy individual messages. They should be able to export full conversations in useful formats.

## Checklist
- [ ] Add export button to chat screen app bar or conversation list context menu
- [ ] Support export as Markdown (.md) format
- [ ] Support export as JSON format (for re-import or archival)
- [ ] Use platform share sheet for mobile (share_plus package)
- [ ] Include conversation metadata (model, timestamps, MCP servers) in export
- [ ] Handle tool call/result messages gracefully in exported format