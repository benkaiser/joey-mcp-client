---
# joey_mcp_client_flutter-35m2
title: Add command palette above chat input
status: completed
type: feature
priority: normal
created_at: 2026-02-09T03:32:45Z
updated_at: 2026-02-09T03:34:50Z
---

Add a rich command palette area that glues to the bottom of the chat list view (scrolls with content). Initially contains an 'MCP Servers' button that opens the server selector to change servers for the current conversation.

## Checklist
- [ ] Build command palette widget with MCP Servers button
- [ ] Place it at bottom of chat ListView so it scrolls away
- [ ] Wire MCP server selector with pre-populated current selection
- [ ] Handle server changes: update DB, reinitialize clients, refresh tools