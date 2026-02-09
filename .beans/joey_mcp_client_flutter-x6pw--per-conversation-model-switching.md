---
# joey_mcp_client_flutter-x6pw
title: Per-conversation model switching
status: todo
type: feature
created_at: 2026-02-09T09:55:37Z
updated_at: 2026-02-09T09:55:37Z
---

Allow users to change the model mid-conversation without starting a new chat. Currently once a conversation is created with a model, it cannot be changed.

## Checklist
- [ ] Add model switcher to chat screen (e.g. tap on model name in app bar)
- [ ] Open model picker screen and allow selection
- [ ] Update conversation model in database when changed
- [ ] Refresh model details (pricing, capabilities) after switch
- [ ] Show a visual indicator in the chat when the model was changed mid-conversation