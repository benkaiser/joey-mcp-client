---
# joey_mcp_client_flutter-csnf
title: MCP support audio content in responses
status: todo
type: feature
created_at: 2026-02-05T13:55:48Z
updated_at: 2026-02-05T13:55:48Z
---

Add support for rendering and playing audio content in MCP tool responses and messages.

## MCP Audio Content Spec
```json
{
  "type": "audio",
  "data": "base64-encoded-audio-data",
  "mimeType": "audio/wav"
}
```

## Implementation
1. Parse audio content type from MCP responses
2. Decode base64 audio data
3. Create an audio player widget for inline playback in chat messages
4. Support common audio MIME types (audio/wav, audio/mp3, audio/ogg, audio/mpeg)
5. Add play/pause controls and progress indicator
6. Handle audio loading states and errors gracefully
7. Consider using audioplayers or just_audio package for playback

## LLM Modality Support
If the selected LLM from OpenRouter does not support audio inputs, we need to:
1. Check the model's capabilities via OpenRouter API/metadata
2. Still render the audio player in the conversation UI for the user to listen to
3. Display an info indicator to the user that the LLM cannot hear/process this audio because it does not support audio inputs
4. Consider suggesting the user switch to an audio-capable model if they want the LLM to understand the audio