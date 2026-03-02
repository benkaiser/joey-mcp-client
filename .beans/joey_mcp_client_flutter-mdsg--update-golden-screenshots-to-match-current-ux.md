---
# joey_mcp_client_flutter-mdsg
title: Update golden screenshots to match current UX
status: completed
type: task
priority: normal
created_at: 2026-03-02T00:45:13Z
updated_at: 2026-03-02T00:47:39Z
---

The mock screens in test/screenshots_test.dart have drifted from the real UI. Key differences to fix:

## Checklist
- [ ] AppBar: Replace MCP server count with pricing text, add usage (bar_chart) button, make share a PopupMenuButton, fix tooltip
- [ ] Message input: Change icon to attach_file, set maxLines:4/minLines:1, add send/stop toggle  
- [ ] Command palette: Use SingleChildScrollView+Row instead of Wrap, add status dots
- [ ] Conversation list: Match date format to DateFormatter
- [ ] Regenerate goldens with --update-goldens