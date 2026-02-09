---
# joey_mcp_client_flutter-hr9h
title: Button to inspect MCP server tools in a conversation
status: completed
type: feature
priority: normal
created_at: 2026-02-08T11:08:23Z
updated_at: 2026-02-09T09:21:16Z
---

Add a button in the conversation UI that allows users to manually inspect the tools available from the MCP servers configured for that conversation. This helps with debugging and understanding what capabilities are available.

## Checklist
- [ ] Add an inspect/tools button to the conversation screen (e.g. in the app bar or a menu)
- [ ] When tapped, fetch the tools list from all connected MCP servers for the conversation
- [ ] Display the tools in a readable format showing name, description, and input schema
- [ ] Group tools by their originating MCP server
- [ ] Allow the user to dismiss the tools inspector