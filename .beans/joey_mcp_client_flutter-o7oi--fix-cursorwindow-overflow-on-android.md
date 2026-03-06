---
# joey_mcp_client_flutter-o7oi
title: Fix CursorWindow overflow on Android
status: in-progress
type: bug
created_at: 2026-03-01T23:28:44Z
updated_at: 2026-03-01T23:28:44Z
---

SELECT * FROM messages fails on Android when a message row contains large base64-encoded imageData/audioData that exceeds the 2MB CursorWindow limit. This crashes the entire app initialization, preventing any conversations from being shown.

Root cause: ConversationProvider.initialize() loads ALL messages for ALL conversations using SELECT *, which pulls in the imageData and audioData TEXT columns containing base64-encoded binary data. A single large image can exceed Android's 2MB CursorWindow limit per row.

## Fix approach
Use a two-phase loading strategy:
1. Load messages WITHOUT the large blob columns (imageData, audioData) during initialization — these are only needed for display in MessageBubble and for API calls.
2. Add a method to lazy-load the large columns when needed, and update Message.fromMap to handle null blob fields gracefully.

## Checklist
- [ ] Add getMessagesForConversation that excludes imageData and audioData columns
- [ ] Add method to lazily load blob data for a specific message
- [ ] Update ConversationProvider to use the lightweight query for init
- [ ] Add lazy-loading in ConversationProvider for blob data on-demand
- [ ] Ensure blob data is loaded before sending API messages that need it
- [ ] Make sure the initialize() method handles errors gracefully for individual conversations
- [ ] Run flutter analyze