---
# joey_mcp_client_flutter-x6pw
title: Per-conversation model switching
status: completed
type: feature
priority: normal
created_at: 2026-02-09T09:55:37Z
updated_at: 2026-02-09T10:42:58Z
---

Allow users to change the model mid-conversation without starting a new chat. Currently once a conversation is created with a model, it cannot be changed.

## Checklist
- [x] Add model switcher to chat screen (e.g. tap on model name in app bar)
- [x] Open model picker screen and allow selection
- [x] Update conversation model in database when changed
- [x] Refresh model details (pricing, capabilities) after switch
- [x] Show a visual indicator in the chat when the model was changed mid-conversation