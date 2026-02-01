---
# joey_mcp_client_flutter-st0q
title: Migrate MCP implementation to mcp_dart library
status: completed
type: task
priority: normal
created_at: 2026-02-01T11:08:31Z
updated_at: 2026-02-01T11:15:52Z
---

Replace the custom MCP client implementation with the mcp_dart library (v1.2.2).

## Checklist
- [x] Add mcp_dart dependency to pubspec.yaml
- [x] Refactor McpClientService to use mcp_dart's McpClient
- [x] Update tool listing to use mcp_dart's listTools
- [x] Update tool calling to use mcp_dart's callTool
- [x] Handle elicitation using mcp_dart's built-in support
- [x] Handle sampling using mcp_dart's built-in support
- [x] Update ChatService to work with the new MCP client
- [x] Update ChatScreen to work with the refactored services
- [x] Test the integration