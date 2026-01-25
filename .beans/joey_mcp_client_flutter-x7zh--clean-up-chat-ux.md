---
# joey_mcp_client_flutter-x7zh
title: Clean up chat UX
status: completed
type: task
priority: normal
created_at: 2026-01-25T04:28:09Z
updated_at: 2026-01-25T04:31:06Z
---

Improve chat message UX with better text selection and message actions.

## Checklist

- [x] Fix markdown renderer to allow arbitrary text selection (currently only one line at a time)
- [x] Add message card actions:
  - [x] Copy icon for all messages
  - [x] Delete icon for all messages (removes from chat history)
  - [x] Edit icon for user messages only (opens dialog with 'edit and resend' button that removes all future messages and re-runs from LLM)
