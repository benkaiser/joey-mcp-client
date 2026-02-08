---
# joey_mcp_client_flutter-mac5
title: MCP support image content in responses
status: completed
type: feature
priority: normal
created_at: 2026-02-05T13:55:42Z
updated_at: 2026-02-08T10:36:49Z
---

Add support for rendering image content in MCP tool responses and messages.

## MCP Image Content Spec
```json
{
  "type": "image",
  "data": "base64-encoded-image-data",
  "mimeType": "image/png"
}
```

The image data is base64-encoded and includes a valid MIME type. This enables multi-modal interactions where visual context is important.

## Implementation
1. Parse image content type from MCP responses
2. Decode base64 image data
3. Render images inline in the chat message widgets
4. Support common image MIME types (image/png, image/jpeg, image/gif, image/webp)
5. Handle image loading states and errors gracefully

## LLM Modality Support
If the selected LLM from OpenRouter does not support image inputs (vision capability), we need to:
1. Check the model's capabilities via OpenRouter API/metadata
2. Still render the image in the conversation UI for the user to see
3. Display an info indicator to the user that the LLM cannot see/process this image because it does not support image inputs
4. Consider suggesting the user switch to a vision-capable model if they want the LLM to understand the image