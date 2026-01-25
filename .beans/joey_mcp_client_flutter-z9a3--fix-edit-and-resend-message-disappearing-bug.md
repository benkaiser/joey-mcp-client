---
# joey_mcp_client_flutter-z9a3
title: Fix edit and resend message disappearing bug
status: completed
type: bug
priority: normal
created_at: 2026-01-25T10:15:39Z
updated_at: 2026-01-25T10:16:35Z
---

When using 'edit and resend', the new assistant message streams in but disappears after completion. Need to investigate the event handling and message persistence in the edit and resend flow compared to normal message flow.

## Investigation Notes
- Normal flow: ChatService is reused, events work fine
- Edit/resend flow: New ChatService created, subscription cancelled after loop
- MessageCreated event calls provider.addMessage() but it's not awaited
- Need to verify if the message is actually persisted to DB
- Check timing of events vs subscription cancellation