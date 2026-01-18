---
# joey_mcp_client_flutter-l8il
title: Implement Complete MCP Integration
status: completed
type: feature
priority: normal
created_at: 2026-01-18T11:24:14Z
updated_at: 2026-01-18T11:30:46Z
---

Implement full MCP client integration into the Flutter app, including:
- Settings UI for managing remote MCP servers
- Conversation-level MCP server selection
- Tool listing, execution, and LLM integration during chat

## Checklist
- [x] Create MCP server configuration model and database schema
- [x] Implement MCP Streamable HTTP client service
- [x] Create settings screen for managing MCP servers
- [x] Update conversation model to track enabled MCP servers
- [x] Update conversation creation to allow selecting MCP servers
- [x] Update chat logic to fetch and send tools to LLM
- [x] Implement tool call handling and execution
- [x] Add UI indicators for tool usage in chat
- [ ] Test end-to-end flow with a sample MCP server