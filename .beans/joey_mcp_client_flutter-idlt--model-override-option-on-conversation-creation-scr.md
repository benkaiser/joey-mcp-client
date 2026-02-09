---
# joey_mcp_client_flutter-idlt
title: Model override option on conversation creation screen
status: completed
type: feature
priority: normal
created_at: 2026-02-08T11:08:16Z
updated_at: 2026-02-09T09:28:33Z
---

When creating a new conversation, allow the user to override the default model and manually choose a specific model. This gives users more control over which LLM is used for each conversation instead of always relying on the global default.

## Checklist
- [ ] Add a model selection dropdown/picker to the conversation creation screen
- [ ] Populate it with available models from OpenRouter
- [ ] Default to the global default model but allow override
- [ ] Store the per-conversation model override in the database
- [ ] Use the overridden model when sending requests for that conversation