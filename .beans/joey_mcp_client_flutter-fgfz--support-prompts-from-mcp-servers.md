---
# joey_mcp_client_flutter-fgfz
title: Support prompts from MCP servers
status: completed
type: feature
priority: normal
created_at: 2026-02-08T11:08:20Z
updated_at: 2026-02-09T09:21:01Z
---

Add support for MCP server prompts. MCP servers can expose prompt templates that clients can discover and use. This feature would allow users to browse and invoke prompts provided by their connected MCP servers.

## Checklist
- [ ] Implement the prompts/list MCP method to discover available prompts from connected servers
- [ ] Implement the prompts/get MCP method to retrieve prompt details and arguments
- [ ] Add UI for browsing available prompts from connected MCP servers
- [ ] Allow users to fill in prompt arguments and insert the resulting messages into the chat
- [ ] Handle prompt results that include text, images, or embedded resources