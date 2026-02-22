# Joey MCP Client

A cross-platform chat application built with Flutter that connects to AI models via [OpenRouter](https://openrouter.ai/) and remote [MCP](https://modelcontextprotocol.io/) (Model Context Protocol) servers over Streamable HTTP.

## Key Features

- 🔌 **Full MCP Support** — Connect to remote MCP servers with tool calling, sampling, elicitation, OAuth, session resumption, and progress notifications
- 🤖 **Hundreds of AI Models** — Access any model on OpenRouter, switch models mid-conversation, and track per-message token usage and costs
- 🔄 **Agentic Tool Use** — Automatic agentic loop that executes MCP tools and feeds results back to the LLM until the task is complete
- 📎 **Image & Audio Attachments** — Attach images from gallery/camera/clipboard or record audio inline, with inline display of media returned by tools
- 📱 **Cross-Platform** — Runs natively on iOS, Android, macOS, Windows, and Linux

## All Features

### Chat
- Multiple conversations with persistent local storage (SQLite)
- Real-time streaming responses with reasoning/thinking display
- Full markdown rendering including code blocks, Mermaid diagrams, and links
- Edit & resend messages, regenerate responses, delete individual messages
- Share conversations as Markdown via clipboard or native share sheet
- Full-text search across conversation titles and message content
- Auto-generated conversation titles

### AI Models
- OpenRouter integration with OAuth PKCE authentication
- Model picker with search, modality filters (text/image/audio), and sorting by price, context length, or name
- Switch models mid-conversation with visual indicators
- Set a default model to skip the picker for new conversations
- Per-message and per-conversation usage tracking (token counts, cost breakdowns, reasoning tokens)

### MCP (Model Context Protocol)
- Connect to remote MCP servers via Streamable HTTP
- Use tools from multiple MCP servers simultaneously in a single conversation
- Browse and use server-provided prompt templates with argument filling
- Session resumption — persists and reuses MCP session IDs across app restarts
- Sampling — handles server-initiated LLM requests with user approval
- Elicitation — dynamic JSON Schema forms and URL-based elicitation from servers
- OAuth support for authenticated MCP servers (RFC 9728 / RFC 8414 discovery)
- Real-time progress notifications from long-running MCP operations
- Debug screen to inspect servers, view tool schemas, and connection status

### Media
- Attach images from gallery, camera, or clipboard paste (with model compatibility checks)
- Record audio inline with microphone on iOS/Android, or attach audio files
- Inline display of images and audio returned by MCP tools, with full-screen pinch-to-zoom for images

### Settings & Configuration
- Customizable global system prompt
- Configurable max tool calls per message (5–100, or unlimited)
- MCP server management — add, edit, delete, enable/disable servers with custom headers

### Platform & UX
- Native builds for iOS, Android, macOS, Windows, and Linux
- Keyboard shortcuts — Enter to send, Cmd/Ctrl+F to search, Cmd/Ctrl+V to paste images
- In-app browser (SFSafariViewController / Chrome Custom Tabs) on mobile
- Explicit data-sharing consent flows before connecting to OpenRouter or MCP servers

## Getting Started

### Prerequisites

- Flutter SDK 3.10.7 or later
- Dart SDK
- iOS/Android development environment (for mobile)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/benkaiser/joey-mcp-client.git
cd joey-mcp-client
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

## Tech Stack

- **Framework**: Flutter
- **State Management**: Provider
- **Database**: SQLite (sqflite)
- **HTTP Client**: Dio
- **LLM Provider**: OpenRouter (OAuth PKCE, SSE streaming)
- **MCP Client**: mcp_dart (Streamable HTTP)

## Roadmap

- [ ] MCP resource browsing UI (list and read server-provided resources)
- [ ] Third-party OpenAI-compatible API support (use your own endpoint as an alternative to OpenRouter)
- [ ] Conversation import/export (JSON backup and restore)
- [ ] Model parameters (temperature, top_p, etc.)
- [ ] Document & file attachments (PDFs, text files, etc.)
- [ ] Per-conversation system prompts
- [ ] Theme switching (light mode / custom themes)

## Finding MCP Servers

Looking for MCP servers to connect to? Check out:
- [Remote MCP Servers Directory](https://mcpservers.org/remote-mcp-servers) - A curated list of available remote MCP servers

## License

This project is licensed under the [Functional Source License, Version 1.1, MIT Future License (FSL-1.1-MIT)](https://fsl.software/FSL-1.1-MIT.template.md).

- **Non-competing use is allowed** — you can use, copy, modify, and redistribute the Software for any purpose that isn't a Competing Use
- **After 2 years**, each version automatically converts to the standard **MIT License** with no restrictions

See [LICENSE](LICENSE) for full details.
