---
# joey_mcp_client_flutter-wcyn
title: Fix MCP sampling request dialog issues
status: completed
type: bug
priority: normal
created_at: 2026-02-01T12:09:20Z
updated_at: 2026-02-01T12:12:19Z
---

Two issues with sampling request approval:
1. Empty prompt field - the prompt from the server isn't displayed in the dialog
2. Dialog doesn't disappear correctly when approving with empty prompt

## Root Cause
The `_contentToMap` function was checking for `TextContent` and `ImageContent` types, but sampling messages use `SamplingTextContent` and `SamplingImageContent` types instead.

## Checklist
- [x] Fix prompt field to show server-provided prompt (added SamplingTextContent/SamplingImageContent handling in _contentToMap)
- [x] Fix dialog dismissal on approval (moved Navigator.pop() to finally block)