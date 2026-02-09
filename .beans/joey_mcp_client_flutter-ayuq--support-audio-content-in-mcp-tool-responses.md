---
# joey_mcp_client_flutter-ayuq
title: Support audio content in MCP tool responses
status: completed
type: task
priority: normal
created_at: 2026-02-09T00:53:12Z
updated_at: 2026-02-09T01:02:53Z
---

Following the same approach as image content support, add audio content handling from MCP servers. Extract AudioContent from tool results, store in DB, render audio player in UI, and forward to LLMs supporting audio input modality.

## Checklist
- [ ] Update McpContent to handle AudioContent from mcp_dart
- [ ] Add audioData field to Message model
- [ ] Add DB migration for audioData column
- [ ] Extract audio data in ChatService._executeToolCalls()
- [ ] Render audio player in tool_result_images.dart (rename to tool_result_media.dart)
- [ ] Show audio in thinking-hidden mode (chat_screen.dart)
- [ ] Forward audio to LLMs supporting audio input modality
- [ ] Verify compilation with flutter analyze