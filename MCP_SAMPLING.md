# MCP Sampling Implementation

This document describes the implementation of MCP sampling support in Joey MCP Client Flutter, including support for multi-turn tool use loops as specified in the MCP protocol.

## Overview

MCP Sampling allows MCP servers to request LLM completions from the client. This enables servers to implement agentic behaviors by nesting LLM calls inside their tools. The implementation supports:

- Basic text-based sampling
- Multi-turn tool use loops
- Tool result processing
- Multiple content types (text, tool_use, tool_result)

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

### Basic Sampling Flow

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

### Multi-Turn Tool Loop Flow

```
1. MCP Server → Client: sampling/createMessage (with tools array)
2. Client → OpenRouter: Request with tools
3. OpenRouter → Client: Response with tool_use (stopReason: "toolUse")
4. Client → MCP Server: Return tool_use response
5. MCP Server executes tools locally
6. MCP Server → Client: New sampling/createMessage (with tool results)
7. Client → OpenRouter: Request with conversation history + tool results
8. OpenRouter → Client: Final text response (stopReason: "endTurn")
9. Client → MCP Server: Return final response
```

The MCP server is responsible for managing the loop and deciding when to stop (e.g., by setting a maximum iteration count or forcing `toolChoice: {mode: "none"}` on the final request).

## Human-in-the-Loop Safety

Per the MCP specification, sampling requests **MUST** include human review:

1. All sampling requests trigger a dialog for user approval
2. Users can view and edit the prompt before sending
3. Users can view model preferences and parameters
4. Users can reject sampling requests
5. Dialog is non-dismissible (must approve or reject)

## Message Format Conversion

### MCP → OpenRouter

#### Basic Text Request

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
  "maxTokens": 1000
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

#### Request with Tools

MCP format with tools:
```json
{
  "messages": [...],
  "tools": [
    {
      "name": "get_weather",
      "description": "Get weather for a city",
      "inputSchema": {
        "type": "object",
        "properties": {
          "city": {"type": "string"}
        }
      }
    }
  ]
}
```

Converted to OpenRouter format:
```json
{
  "messages": [...],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get weather for a city",
        "parameters": {
          "type": "object",
          "properties": {
            "city": {"type": "string"}
          }
        }
      }
    }
  ]
}
```

#### Messages with Tool Results

MCP format:
```json
{
  "role": "user",
  "content": [
    {
      "type": "tool_result",
      "toolUseId": "call_123",
      "content": [
        {"type": "text", "text": "Weather: 18°C"}
      ]
    }
  ]
}
```

Converted to OpenRouter format:
```json
{
  "role": "tool",
  "tool_call_id": "call_123",
  "content": "Weather: 18°C"
}
```

### OpenRouter → MCP

#### Text Response

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

#### Tool Use Response

OpenRouter tool_calls:
```json
{
  "choices": [{
    "message": {
      "tool_calls": [
        {
          "id": "call_123",
          "type": "function",
          "function": {
            "name": "get_weather",
            "arguments": "{\"city\": \"Paris\"}"
          }
        }
      ]
    },
    "finish_reason": "tool_calls"
  }]
}
```

Converted to MCP format:
```json
{
  "role": "assistant",
  "content": [
    {
      "type": "tool_use",
      "id": "call_123",
      "name": "get_weather",
      "input": {"city": "Paris"}
    }
  ],
  "model": "anthropic/claude-3-5-sonnet",
  "stopReason": "toolUse"
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
- Tool use content (`type: "tool_use"`)
- Tool result content (`type: "tool_result"`)

Not yet supported:
- Image content (`type: "image"`)
- Audio content (`type: "audio"`)

## Stop Reason Mapping

OpenRouter → MCP stop reason mappings:
- `stop` → `endTurn` (normal completion)
- `length` → `maxTokens` (hit token limit)
- `tool_calls` → `toolUse` (model wants to use tools)
- Unknown/null → `endTurn` (default)

## Error Handling

Errors can occur at several points:

1. **User rejection**: Returns error to MCP server with "rejected by user" message
2. **OpenRouter API error**: Caught and displayed to user, rejection sent to server
3. **Format conversion error**: Logged and returns error to server

## Testing

To test the sampling implementation:

### Basic Sampling
1. Connect to an MCP server that implements sampling requests
2. Trigger a tool that requests sampling
3. Verify the approval dialog appears
4. Review the request details
5. Approve or edit and approve
6. Verify the response is returned correctly
7. Test rejection flow

### Tool Use Sampling
1. Connect to an MCP server that supports tool use in sampling
2. Trigger a sampling request that includes tools
3. Verify the LLM returns tool_use requests
4. Verify the MCP server receives the tool_use response
5. Verify the server sends a follow-up request with tool results
6. Verify the final text response is returned

The test suite in `test/sampling_request_test.dart` includes comprehensive tests for both basic and tool-enabled sampling.

## Future Enhancements

- [ ] Support for image and audio content types
- [ ] Streaming support for sampling responses
- [ ] More sophisticated model selection based on priorities
- [ ] Rate limiting for sampling requests
- [ ] Sampling request history/logging
- [ ] Response preview before returning to server
- [ ] Caching of sampling results
- [x] ~~Support for tool use in sampling~~ (Implemented)
- [x] ~~Multi-turn tool loops~~ (Implemented)
