# Joey MCP Client

A mobile chat application built with Flutter that enables users to interact with remote MCP (Model Context Protocol) servers over Streamable HTTP.

## Features

- 💬 **Local Chat Interface** - Multiple conversations with persistent storage
- 🔌 **MCP Server Support** - Connect to remote MCP servers via Streamable HTTP
- 🤖 **OpenRouter Integration** - LLM responses powered by OpenRouter (OAuth-based)
- 💾 **Data Persistence** - Conversations and messages stored locally with SQLite
- 🎨 **Material Design 3** - Modern, vibrant UI with smooth animations
- 📱 **Cross-Platform** - Runs on iOS, Android, macOS, and web

## Tech Stack

- **Framework**: Flutter
- **State Management**: Provider
- **Database**: SQLite (sqflite)
- **HTTP Client**: Dio
- **LLM Provider**: OpenRouter (planned)
- **MCP Transport**: Streamable HTTP (planned)

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

## Project Structure

```
lib/
├── models/          # Data models (Conversation, Message)
├── providers/       # State management (ConversationProvider)
├── screens/         # UI screens (Chat, ConversationList)
├── services/        # Backend services (DatabaseService)
├── widgets/         # Reusable UI components (MessageBubble)
└── main.dart        # App entry point
```

## Finding MCP Servers

Looking for MCP servers to connect to? Check out:
- [Remote MCP Servers Directory](https://mcpservers.org/remote-mcp-servers) - A curated list of available remote MCP servers

## Roadmap

- [ ] OpenRouter OAuth integration
- [ ] MCP server configuration UI
- [ ] Support for multiple MCP servers simultaneously
- [ ] Tool execution from MCP servers
- [ ] Server management and authentication

## License

This project is licensed under the [Functional Source License, Version 1.1, MIT Future License (FSL-1.1-MIT)](https://fsl.software/FSL-1.1-MIT.template.md).

- **Non-competing use is allowed** — you can use, copy, modify, and redistribute the Software for any purpose that isn't a Competing Use
- **After 2 years**, each version automatically converts to the standard **MIT License** with no restrictions

See [LICENSE](LICENSE) for full details.
