---
# joey_mcp_client_flutter-47pv
title: Per-MCP-server custom system prompts
status: completed
type: feature
priority: normal
created_at: 2026-08-10T00:02:31Z
updated_at: 2026-08-10T00:06:49Z
---

Allow users to optionally specify a custom system prompt per MCP server. When that server is connected in a conversation, its prompt is appended (joined with a newline) to the global system prompt from Settings. Multiple connected servers append in order.

## Checklist
- [x] Add nullable `systemPrompt` field to `McpServer` model (toMap/fromMap/copyWith, with clearSystemPrompt support)
- [x] DB migration to v18: `ALTER TABLE mcp_servers ADD COLUMN systemPrompt TEXT` + add to CREATE TABLE
- [x] Add system prompt field to the add/edit server dialog in `mcp_servers_screen.dart`
- [x] Expose `serverSystemPrompts` from `McpServerManager` (only connected servers)
- [x] `ChatService` accepts/updates server system prompts and appends them to the base system prompt in `runAgenticLoop`
- [x] Wire through `chat_screen.dart` ChatService construction/updateServers calls
- [x] Update AGENTS.md schema version
- [x] `flutter analyze` + `flutter test` pass