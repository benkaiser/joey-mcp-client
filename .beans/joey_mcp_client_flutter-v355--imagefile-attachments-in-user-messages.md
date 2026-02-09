---
# joey_mcp_client_flutter-v355
title: Image attachments in user messages
status: completed
type: feature
priority: normal
created_at: 2026-02-09T09:55:29Z
updated_at: 2026-02-09T10:27:41Z
---

Allow users to attach images or paste screenshots into their messages. The app can currently display images returned by MCP tools, but users cannot send visual input. This is essential for multimodal model usage.

## Checklist
- [x] Add image attachment button to chat input bar
- [x] Support image picker (gallery and camera) for mobile
- [x] Support paste from clipboard (especially screenshots)
- [x] Encode images as base64 and include in API messages with proper MIME types
- [x] Display attached images as thumbnails in the user message bubble
- [x] Respect model capability flags (modelSupportsImages) and show warning if model doesn't support it