**IMPORTANT**: before you do anything else, run the `beans prime` command and heed its output.

## Project Overview

**joey-mcp-client-flutter** is a mobile chat application built with Flutter that enables users to interact with remote MCP (Model Context Protocol) servers over Streamable HTTP.

### Key Features
- Local chat interface with multiple conversations
- Connect to remote MCP servers via Streamable HTTP
- Support multiple MCP servers simultaneously in the same chat
- OpenRouter integration for LLM responses (requires OAuth)
- Manual MCP server configuration

### Technical Stack
- **Framework**: Flutter
- **State Management**: Provider or Riverpod
- **LLM Provider**: OpenRouter (OAuth-based)
- **MCP Transport**: Streamable HTTP
- **Storage**: sqflite for local database persistence
- **HTTP Client**: dio or http package

### Architecture Notes
- Users manually configure MCP servers (URL, headers, auth)
- OpenRouter handles LLM inference with multiple round-trips (known trade-off)
- Multi-server support: aggregate tools from all enabled servers
- Chat interface supports multiple separate conversations
- Use Flutter's built-in navigation (Navigator 2.0 or go_router)

### Development Guidelines
- Follow Flutter best practices and Material Design guidelines
- Use Flutter's built-in packages when possible
- Prefer sqflite for local storage (compatible with both iOS and Android)
- Use dio or http for HTTP requests
- Implement proper state management (Provider/Riverpod recommended)
- Ensure cross-platform compatibility (iOS and Android)
