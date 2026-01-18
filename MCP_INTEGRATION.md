# MCP Integration Guide

This Flutter app now supports remote MCP (Model Context Protocol) servers via Streamable HTTP. This allows you to augment your AI conversations with tools from external MCP servers.

## Overview

The MCP integration allows you to:
- Configure multiple remote MCP servers
- Select which MCP servers to use for each conversation
- Have the LLM automatically use tools from enabled MCP servers
- Execute tools via HTTP requests to your MCP servers

## Architecture

### Components

1. **Models**
   - `McpServer` - Represents an MCP server configuration
   - `McpTool` - Represents a tool provided by an MCP server
   - `McpToolResult` - Result from executing a tool

2. **Services**
   - `McpClientService` - Handles communication with MCP servers via Streamable HTTP
   - `DatabaseService` - Extended to store MCP server configurations and conversation associations

3. **UI**
   - `McpServersScreen` - Manage MCP server configurations
   - `McpServerSelectionDialog` - Select MCP servers when creating a conversation
   - `ChatScreen` - Updated to fetch tools and handle tool calls

## How to Use

### 1. Configure MCP Servers

1. Open the app and navigate to **Settings**
2. Tap on **Manage MCP Servers**
3. Tap the **+** button to add a new server
4. Enter:
   - **Name**: A friendly name for the server (e.g., "Weather Tools")
   - **URL**: The complete MCP endpoint URL
     - For local development: `http://localhost:3000` (or your port)
     - For production: `https://example.com/mcp/v1`
     - **Important**: Include the full path to the MCP endpoint
   - **Headers** (optional): HTTP headers for authentication
     - Format: `Header-Name: Value` (one per line)
     - Example:
       ```
       Authorization: Bearer your-token-here
       X-API-Key: your-api-key
       ```

### 2. Create a Conversation with MCP Servers

1. From the main screen, tap the **+** button to create a new conversation
2. Select your preferred LLM model
3. A dialog will appear showing available MCP servers
4. Check the servers you want to enable for this conversation
5. Tap **Continue**

The conversation will now have access to all tools from the selected MCP servers.

### 3. Chat with MCP Tools

When chatting:
- The LLM will automatically receive the list of available tools
- If the LLM decides to use a tool, you'll see a message like: `🔧 Calling tool: tool_name`
- The tool will be executed on the MCP server
- The result will be sent back to the LLM
- The LLM will incorporate the tool result into its response

### 4. View Active MCP Servers

In the chat screen, the app bar shows:
- The conversation title
- The LLM model being used
- A badge showing how many MCP servers are active (e.g., "2 MCP")

## MCP Server Requirements

Your MCP server must implement the Streamable HTTP transport and support:

### Required Endpoints

All requests are sent to the configured server URL via POST with JSON-RPC 2.0 format.

**Example**: If your server URL is `http://localhost:3000`, all requests go directly to that URL.

#### 1. Initialize
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "tools": {}
    },
    "clientInfo": {
      "name": "joey-mcp-client-flutter",
      "version": "1.0.0"
    }
  }
}
```

#### 2. List Tools
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list",
  "params": {}
}
```

Expected response:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "get_weather",
        "description": "Get current weather for a location",
        "inputSchema": {
          "type": "object",
          "properties": {
            "location": {
              "type": "string",
              "description": "City name"
            }
          },
          "required": ["location"]
        }
      }
    ]
  }
}
```

#### 3. Call Tool
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "get_weather",
    "arguments": {
      "location": "San Francisco"
    }
  }
}
```

Expected response:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "The weather in San Francisco is sunny, 72°F"
      }
    ]
  }
}
```

## Example MCP Server Setup

Here's a simple example of deploying an MCP server that this app can connect to:

### Option 1: Use an Existing MCP Server

Many MCP servers support Streamable HTTP. You can deploy them on platforms like:
- Vercel
- Railway
- Fly.io
- AWS Lambda with Function URLs

### Option 2: Build Your Own

Refer to the [MCP documentation](https://modelcontextprotocol.io/docs) for building MCP servers in:
- Python
- TypeScript/JavaScript
- Java
- Kotlin
- C#

Then deploy it with an HTTP endpoint that implements the JSON-RPC interface described above.

## Troubleshooting

### Server Not Responding

1. Check that the server URL is correct and accessible
2. Verify any required headers are properly configured
3. Check server logs for errors

### Tools Not Appearing

1. Make sure the MCP server is enabled (toggle in the MCP Servers list)
2. Verify the server is selected for your conversation
3. Check that the server's `tools/list` endpoint returns valid tools

### Tool Execution Fails

1. Check that the tool arguments match the expected schema
2. Verify server authentication headers are correct
3. Check server logs for execution errors

## Security Considerations

- **HTTPS**: Always use HTTPS for MCP server URLs in production
- **Authentication**: Use HTTP headers for API keys/tokens rather than embedding them in URLs
- **Validation**: The app validates MCP responses but your server should validate inputs
- **Rate Limiting**: Consider implementing rate limiting on your MCP servers

## Future Enhancements

Potential improvements to the MCP integration:
- Prompt and resource support (currently only tools are supported)
- Sampling support for multi-step tool orchestration
- Server health monitoring and automatic reconnection
- Tool execution history and debugging
- Server-specific settings and configurations
