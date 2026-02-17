---
# joey_mcp_client_flutter-jp0b
title: Fix MCP server dialog showing 'New Conversation' when editing existing conversation
status: completed
type: bug
priority: normal
created_at: 2026-02-17T03:31:00Z
updated_at: 2026-02-17T03:33:11Z
---

The McpServerSelectionDialog always shows 'New Conversation' as its title and 'Start Chat' as the confirm button, even when opened from the command palette to change MCP servers on an existing conversation. Fix by adding a parameter to distinguish new conversation vs editing mode, and show appropriate text ('MCP Servers' / 'Update' for editing).