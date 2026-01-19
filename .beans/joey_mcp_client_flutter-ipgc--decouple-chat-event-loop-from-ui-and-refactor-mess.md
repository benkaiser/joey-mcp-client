---
# joey_mcp_client_flutter-ipgc
title: Decouple chat event loop from UI and refactor message architecture
status: completed
type: task
priority: normal
created_at: 2026-01-19T03:30:21Z
updated_at: 2026-01-19T03:35:13Z
---

1. Create a separate chat service for the event loop
2. Remove displayOnly field from messages
3. Store all messages with proper roles (Assistant, Tool, User)
4. Update UI to mark up thinking messages based on their content/role
5. Keep only tool result messages as client-synthesized

## Checklist
- [x] Create new chat_service.dart for event loop logic
- [x] Update Message model to remove displayOnly field
- [x] Update database schema to remove displayOnly column
- [x] Refactor message creation to use proper roles
- [x] Update UI rendering to handle message markup based on roles
- [x] Update chat_screen.dart to use the new chat service
- [x] Test the refactored architecture

## Summary

Successfully decoupled the chat event loop from the UI and refactored message architecture:

1. **Created ChatService** (`lib/services/chat_service.dart`):
   - Handles agentic loop logic independently of UI
   - Emits events for UI to consume (streaming, message creation, tool execution)
   - Manages tool execution in parallel
   - Provides clean separation of concerns

2. **Removed displayOnly field** from Message model:
   - No more synthetic display messages
   - All messages use proper roles (User, Assistant, Tool)
   - Database schema updated (version 6) to remove the column

3. **UI now handles message markup**:
   - Messages with tool calls are formatted with thinking indicators in the UI layer
   - Tool call information displayed when `_showThinking` is enabled
   - Streaming content shown as temporary message
   - Filter logic based on role and content, not synthetic flags

4. **Benefits**:
   - Cleaner separation between business logic and UI
   - Easier to test the chat loop independently
   - More maintainable message structure
   - Event-driven architecture for better reactivity