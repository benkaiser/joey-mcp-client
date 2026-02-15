---
# joey_mcp_client_flutter-q7ob
title: Add audio input support (file picker + inline recording)
status: completed
type: feature
priority: normal
created_at: 2026-02-15T09:41:21Z
updated_at: 2026-02-15T09:44:38Z
---

Add two ways for users to attach audio to messages:

1. **Pick audio from local files** - via file_picker package, select audio files from device storage
2. **Record audio inline** - a recording UI with start, stop, delete/cancel controls

## Architecture
- Create `PendingAudio` model (like PendingImage: bytes + mimeType + optional filename + duration)
- Create `AudioAttachmentHandler` (like ImageAttachmentHandler) to handle file picking and recording
- Update `MessageInput` widget to show pending audio chips with playback/delete, recording controls
- Update `Message.toApiMessage()` to include audio data as `input_audio` content parts
- Update `_sendMessage()` in ChatScreen to encode pending audio as base64 JSON into `audioData`
- Update `MessageBubble` to show audio players in user message bubbles
- Update `ChatService` to inject user audio data (same pattern as user images)
- The attachment button popup menu gets new options: 'Audio File' and 'Record Audio'

## Checklist
- [x] Add `record` and `file_picker` packages to pubspec.yaml
- [x] Create `PendingAudio` model class
- [x] Create `AudioAttachmentHandler` with file picker + recording logic
- [x] Update `MessageInput` widget with audio attachment UI (pending audio chips, recording controls)
- [x] Update `ChatScreen._sendMessage()` to encode pending audio into audioData
- [x] Update `Message.toApiMessage()` to include user audio as `input_audio` content parts
- [x] Update `ChatService.runAgenticLoop()` - user audio already handled via toApiMessage() multipart
- [x] Update `MessageBubble` to render audio in user bubbles
- [x] Wire up AudioAttachmentHandler in ChatScreen and pass callbacks to MessageInput
- [x] Run flutter analyze to ensure zero new errors