---
# joey_mcp_client_flutter-qlfw
title: Export/share conversations
status: completed
type: feature
priority: normal
created_at: 2026-02-09T09:55:32Z
updated_at: 2026-02-09T11:34:20Z
---

Add the ability to share conversations as markdown. Tapping the share button in the chat app bar triggers the platform share sheet with the full conversation formatted as structured markdown.

## Checklist
- [x] Add share button to chat screen app bar
- [x] Convert conversation to structured markdown (headings for User/Assistant/Tool/System messages)
- [x] Use platform share sheet via share_plus package
- [x] Handle tool call messages gracefully in exported format
- [ ] Support export as JSON format (for re-import or archival)
- [ ] Include conversation metadata (model, timestamps, MCP servers) in export