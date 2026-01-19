# MCP Sampling Implementation

This document describes the implementation of MCP sampling support in Joey MCP Client Flutter.

## Overview

MCP Sampling allows MCP servers to request LLM completions from the client. This enables servers to implement agentic behaviors by nesting LLM calls inside their tools.

## Architecture

### Components

1. **MCP Client Service** (`lib/services/mcp_client_service.dart`)
   - Declares `sampling` capability during initialization
   - Provides callback mechanism for handling incoming sampling requests
   - Method: `handleSamplingRequest()`

2. **Chat Service** (`lib/services/chat_service.dart`)
   - Registers sampling handler with all MCP clients
   - Processes sampling requests by calling OpenRouter
   - Converts between MCP and OpenRouter message formats
   - Handles model selection based on preferences
   - Event: `SamplingRequestReceived`

3. **Sampling Request Dialog** (`lib/widgets/sampling_request_dialog.dart`)
   - User interface for reviewing and approving sampling requests
   - Displays model preferences, system prompt, and user prompt
   - Allows editing of request parameters before approval
   - Human-in-the-loop safety control

4. **Chat Screen** (`lib/screens/chat_screen.dart`)
   - Listens for sampling request events
   - Shows approval dialog to user
   - Handles approval/rejection flow

## Flow

```
MCP Server → MCP Client → ChatService → SamplingRequestReceived Event
                                       ↓
                          ChatScreen shows dialog
                                       ↓
                          User approves/edits/rejects
                                       ↓
                          ChatService.processSamplingRequest()
                                       ↓
                          OpenRouter API call
                                       ↓
                          Response returned to MCP Server
```

## Human-in-the-Loop Safety

Per the MCP specification, sampling requests **MUST** include human review:

1. All sampling requests trigger a dialog for user approval
2. Users can view and edit the prompt before sending
3. Users can view model preferences and parameters
4. Users can reject sampling requests
5. Dialog is non-dismissible (must approve or reject)

## Message Format Conversion

### MCP → OpenRouter

MCP sampling requests use this format:
```json
{
  "messages": [
    {
      "role": "user",
      "content": {
        "type": "text",
        "text": "..."
      }
    }
  ],
  "systemPrompt": "...",
  "maxTokens": 1000,
  "modelPreferences": {
    "hints": [{"name": "claude-3-sonnet"}],
    "intelligencePriority": 0.8
  }
}
```

This is converted to OpenRouter format:
```json
{
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."}
  ],
  "max_tokens": 1000
}
```

### OpenRouter → MCP

OpenRouter responses:
```json
{
  "choices": [{
    "message": {"content": "..."},
    "finish_reason": "stop"
  }]
}
```

Are converted to MCP format:
```json
{
  "role": "assistant",
  "content": {
    "type": "text",
    "text": "..."
  },
  "model": "anthropic/claude-3-5-sonnet",
  "stopReason": "endTurn"
}
```

## Model Selection

The implementation uses a simple model selection strategy:

1. If model preferences include hints, try to match them
2. Check if hint looks like a full model ID (contains `/`)
3. Fall back to conversation's default model
4. Default to `anthropic/claude-3-5-sonnet`

Future enhancements could:
- Map hints to equivalent models from different providers
- Use priority scores (cost, speed, intelligence) for selection
- Maintain a model capability database

## Supported Content Types

Currently supported:
- Text content (`type: "text"`)

Not yet supported:
- Image content (`type: "image"`)
- Audio content (`type: "audio"`)

## Error Handling

Errors can occur at several points:

1. **User rejection**: Returns error to MCP server with "rejected by user" message
2. **OpenRouter API error**: Caught and displayed to user, rejection sent to server
3. **Format conversion error**: Logged and returns error to server

## Testing

To test the sampling implementation:

1. Connect to an MCP server that implements sampling requests
2. Trigger a tool that requests sampling
3. Verify the approval dialog appears
4. Review the request details
5. Approve or edit and approve
6. Verify the response is returned correctly
7. Test rejection flow

## Future Enhancements

- [ ] Support for image and audio content types
- [ ] Streaming support for sampling responses
- [ ] More sophisticated model selection based on priorities
- [ ] Rate limiting for sampling requests
- [ ] Sampling request history/logging
- [ ] Response preview before returning to server
- [ ] Caching of sampling results
