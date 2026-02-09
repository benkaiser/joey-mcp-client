---
# joey_mcp_client_flutter-u3ox
title: Add MCP Prompts button and screen
status: completed
type: feature
priority: normal
created_at: 2026-02-09T04:37:29Z
updated_at: 2026-02-09T04:41:08Z
---

Add a Prompts button before MCP Servers in the chat screen command palette. Clicking it opens a screen listing prompts from connected MCP servers. Users can select a prompt, fill in arguments, and inject the prompt messages into the chat.

## Checklist
- [ ] Explore existing MCP client service for prompt methods
- [ ] Add listPrompts and getPrompt methods to McpClientService if missing
- [ ] Create MCP Prompts screen (similar to debug screen)
- [ ] Add Prompts button to chat screen command palette
- [ ] Wire up prompt selection to inject messages into chat