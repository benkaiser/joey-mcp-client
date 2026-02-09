**IMPORTANT**: before you do anything else, run the `beans prime` command and heed its output.
**IMPORTANT**: Read files in their entirety, do not read portions of files unless the contents are longer than 2000 lines.

## Project Overview

**joey-mcp-client-flutter** is a cross-platform chat application built with Flutter that enables users to interact with AI models via OpenRouter while connecting to remote MCP (Model Context Protocol) servers over Streamable HTTP. It supports multiple simultaneous MCP servers per conversation, tool calling, sampling, elicitation, and OAuth authentication.

### Key Features
- Multi-conversation chat interface with per-conversation model selection
- Connect to remote MCP servers via Streamable HTTP (with session resumption)
- Support multiple MCP servers simultaneously in the same conversation
- OpenRouter integration for LLM responses (OAuth-based auth)
- Agentic tool-calling loop (configurable max iterations)
- MCP sampling support (server-initiated LLM calls)
- MCP elicitation support (form-based and URL-based user prompts from servers)
- MCP OAuth 2.1 authentication for protected servers
- Image and audio attachment support (camera, gallery, clipboard paste)
- Conversation search, sharing/export as markdown, auto-title generation
- Dark theme with Material 3

### Technical Stack
- **Framework**: Flutter (iOS, Android, macOS, Windows, Linux)
- **Language**: Dart (SDK ^3.10.7)
- **State Management**: Provider (`ChangeNotifierProvider`)
- **LLM Provider**: OpenRouter (OAuth PKCE flow, streaming via SSE)
- **MCP Client**: `mcp_dart` package (Streamable HTTP transport)
- **Database**: sqflite (local SQLite, schema version 14)
- **HTTP Client**: Dio
- **Markdown Rendering**: `flutter_markdown`
- **Audio Playback**: `just_audio`

---

## Architecture

### Navigation Flow

```
main.dart (AuthCheckScreen)
  ├── AuthScreen          — OpenRouter OAuth login
  └── ConversationListScreen — List of conversations
        └── ChatScreen    — Main chat interface (per-conversation)
              ├── McpDebugScreen   — MCP server/tool inspector
              ├── McpPromptsScreen — Browse MCP server prompts
              ├── ModelPickerScreen — Switch LLM model
              └── SettingsScreen   — App preferences
```

### Data Flow

```
User input → ChatScreen._sendMessage()
  → ChatService.runAgenticLoop()
    → OpenRouterService.chatCompletionStream()  (streaming SSE)
    → _executeToolCalls() → McpClientService.callTool()  (if tool calls detected)
    → loops until no more tool calls or max iterations reached
  ← ChatEvent stream → ChatEventHandlerMixin.handleChatEvent()
    → ConversationProvider.addMessage()  (persists to SQLite)
    → setState() to update UI
```

### Provider Setup (main.dart)

Two providers at the app root:
- `ConversationProvider` — manages conversations and messages (ChangeNotifier)
- `OpenRouterService` — singleton for OpenRouter API calls (plain Provider)

---

## Directory Structure

```
lib/
├── main.dart                          — App entry point, theme, auth check, provider setup
│
├── models/
│   ├── conversation.dart              — Conversation model (id, title, model, timestamps)
│   ├── message.dart                   — Message model with MessageRole enum and toApiMessage()
│   ├── elicitation.dart               — Elicitation models (request, form fields, validation)
│   ├── mcp_server.dart                — McpServer model with OAuth tokens and status
│   ├── pending_image.dart             — PendingImage model for image attachments
│   └── url_elicitation_error.dart     — URL elicitation error model
│
├── providers/
│   └── conversation_provider.dart     — ChangeNotifier managing conversations + messages in memory and SQLite
│
├── screens/
│   ├── auth_screen.dart               — OpenRouter OAuth login screen
│   ├── chat_screen.dart               — Main chat screen (composes widgets, manages ChatService lifecycle)
│   ├── chat_event_handler.dart        — Mixin: handles ChatEvent stream → UI state updates
│   ├── conversation_actions.dart      — Mixin: share, rename, new conversation, model switch, title generation
│   ├── conversation_list_screen.dart  — Conversation list with search (Cmd+F)
│   ├── mcp_debug_screen.dart          — MCP server/tool/resource inspector
│   ├── mcp_prompts_screen.dart        — Browse and select MCP server prompts
│   ├── mcp_servers_screen.dart        — Global MCP server configuration (add/edit/delete)
│   ├── model_picker_screen.dart       — Model selection with search and pricing info
│   └── settings_screen.dart           — App settings (default model, system prompt, max tool calls, etc.)
│
├── services/
│   ├── chat_service.dart              — Agentic loop: streaming, tool calls, event emission, cancellation
│   ├── chat_events.dart               — ChatEvent class hierarchy (streaming, messages, tools, errors, MCP notifications)
│   ├── sampling_processor.dart        — Processes MCP sampling requests (mini agentic loop with OpenRouter)
│   ├── openrouter_service.dart        — OpenRouter API: OAuth PKCE, chat completion, streaming, model listing
│   ├── mcp_client_service.dart        — MCP client wrapper: initialize, call tools, list tools/resources, handle notifications
│   ├── mcp_models.dart                — MCP data classes (McpTool, McpToolResult, McpResource, etc.)
│   ├── mcp_oauth_service.dart         — MCP OAuth 2.1 service (discovery, PKCE, token exchange, deep links)
│   ├── mcp_oauth_manager.dart         — Manages OAuth state for multiple MCP servers (deep link listener, banner UI coordination)
│   ├── mcp_server_manager.dart        — MCP server lifecycle: load, initialize, refresh tools, session resumption
│   ├── database_service.dart          — SQLite database (sqflite): conversations, messages, MCP servers, sessions
│   └── default_model_service.dart     — SharedPreferences wrapper for default model, system prompt, settings
│
├── utils/
│   ├── date_formatter.dart            — Date formatting utilities
│   └── image_attachment_handler.dart   — Image picking (gallery, camera, clipboard paste), pending image management
│
└── widgets/
    ├── message_list.dart              — Message list with filtering, index mapping, per-type rendering (reversed ListView)
    ├── message_bubble.dart            — Single message bubble (markdown rendering, copy, delete, edit, regenerate actions)
    ├── message_input.dart             — Text input with image thumbnails, send/stop buttons
    ├── command_palette.dart           — Quick-action buttons (prompts, servers, debug)
    ├── thinking_indicator.dart        — Compact tool call / notification indicator (collapsed view)
    ├── loading_status_indicator.dart   — Loading bar showing current tool execution + progress
    ├── tool_result_media.dart         — Displays images and audio from tool results
    ├── auth_required_card.dart        — "Authentication required" card shown in chat
    ├── elicitation_url_card.dart      — URL-mode elicitation card (accept/decline)
    ├── elicitation_form_card.dart     — Form-mode elicitation card (renders JSON schema as form)
    ├── elicitation_form_screen.dart   — Full-screen form for complex elicitation schemas
    ├── sampling_request_dialog.dart   — Dialog for approving/rejecting MCP sampling requests
    ├── mcp_oauth_card.dart            — OAuth authentication banner for MCP servers
    ├── mcp_server_selection_dialog.dart — Dialog for selecting which MCP servers to use in a conversation
    └── rename_dialog.dart             — Simple rename dialog for conversation titles

test/
├── elicitation_test.dart              — Unit tests for elicitation models
├── sampling_request_test.dart         — Unit tests for sampling processor via ChatService
├── sampling_request_test.mocks.dart   — Generated mocks (mockito)
└── widget_test.dart                   — Basic widget test

integration_test/
├── main.dart                          — Integration test runner
├── test_driver.dart                   — Test driver
├── chat_integration_test.dart         — Chat flow integration test
└── mcp_integration_test.dart          — MCP client integration test
```

---

## Key Components in Detail

### ChatService (`services/chat_service.dart`)
The core engine. Manages the agentic loop:
1. Builds API messages from conversation history (including system prompt)
2. Streams LLM responses via `OpenRouterService.chatCompletionStream()`
3. Detects tool calls in the response
4. Executes tool calls against MCP servers via `_executeToolCalls()`
5. Loops until no tool calls remain or max iterations reached
6. Emits `ChatEvent`s throughout for UI updates

Also handles:
- Request cancellation with partial message preservation
- MCP notification queuing during streaming (flushed after each response)
- MCP sampling/elicitation request delegation
- Server hot-swapping via `updateServers()`

### ChatEvent System (`services/chat_events.dart`)
Event hierarchy emitted by `ChatService`:
- `StreamingStarted` — new iteration beginning
- `ContentChunk` / `ReasoningChunk` — streaming text updates
- `MessageCreated` — complete message ready to persist
- `ToolExecutionStarted` / `ToolExecutionCompleted` — tool call lifecycle
- `ConversationComplete` / `MaxIterationsReached` — loop termination
- `ErrorOccurred` / `AuthenticationRequired` — error states
- `SamplingRequestReceived` / `ElicitationRequestReceived` — MCP server requests
- `McpProgressNotificationReceived` / `McpGenericNotificationReceived` — MCP notifications
- `McpToolsListChanged` / `McpResourcesListChanged` — dynamic tool/resource updates
- `McpAuthRequiredForServer` — OAuth needed for a server

### SamplingProcessor (`services/sampling_processor.dart`)
Handles MCP sampling requests (when an MCP server asks the client to make an LLM call):
- Converts MCP message format to OpenRouter format
- Runs up to 10 iterations with tool calling
- Shares the same `executeToolCalls` callback as `ChatService`

### ChatScreen (`screens/chat_screen.dart`)
The main chat UI. Composed of:
- **ChatEventHandlerMixin** — processes `ChatEvent` stream into `setState()` calls
- **ConversationActionsMixin** — conversation-level actions (share, rename, model switch, etc.)
- **McpServerManager** — manages MCP server lifecycle
- **McpOAuthManager** — manages OAuth flows for MCP servers
- **ImageAttachmentHandler** — image picking and clipboard paste

The screen delegates message rendering to `MessageList` and input to `MessageInput`.

### McpClientService (`services/mcp_client_service.dart`)
Wraps the `mcp_dart` library:
- Connects via `StreamableHttpClientTransport`
- Supports session resumption (stores session IDs in SQLite)
- Handles sampling and elicitation callbacks from MCP servers
- Tool execution with timeout management
- OAuth token injection via `McpOAuthClientProvider`
- Automatic session re-establishment when server restarts

### Message Model (`models/message.dart`)
Messages use a `MessageRole` enum with special roles:
- `user`, `assistant`, `system` — standard chat roles
- `tool` — tool result messages (with `toolCallId`, `toolName`)
- `elicitation` — inline elicitation cards (local display only, not sent to LLM)
- `mcpNotification` — MCP server notifications (sent to LLM as context)
- `modelChange` — model switch indicators (local display only)

The `toApiMessage()` method handles conversion to OpenRouter format, including skipping local-only roles.

### MessageList Widget (`widgets/message_list.dart`)
Renders the conversation message list:
- Uses a reversed `ListView.builder` (anchored to bottom, grows upward)
- Filters messages based on visibility rules
- Maps indices accounting for command palette, auth card, and streaming bubble
- Renders different widget types per `MessageRole` (bubbles, indicators, cards)
- Handles elicitation response callbacks

### Database (`services/database_service.dart`)
SQLite via sqflite (schema version 14). Tables:
- `conversations` — id, title, model, timestamps
- `messages` — all message fields including tool data, elicitation data, media
- `mcp_servers` — server config with OAuth tokens
- `conversation_mcp_servers` — many-to-many join table
- `mcp_sessions` — stored session IDs for session resumption
- Full-text search support for conversations

---

## Development Guidelines

### Commands
- **Analyze**: `flutter analyze` — must pass with zero new errors before committing
- **Test**: `flutter test` — run unit tests
- **Integration test**: `flutter test integration_test/`
- **Build**: `flutter build apk` / `flutter build ios` / `flutter build macos`

### Conventions
- Follow Flutter best practices and Material Design 3 guidelines
- Use Provider for state management (not Riverpod)
- Prefer sqflite for local storage
- Use Dio for HTTP requests
- All MCP server communication uses Streamable HTTP (not stdio/SSE)
- Print statements are used for debug logging (existing pattern, not yet migrated to a logger)
- Models use `toMap()`/`fromMap()` for SQLite serialization and `copyWith()` for immutability
- Services are instantiated per-conversation (ChatService, McpClientService) not as singletons
- Widgets receive data and callbacks as constructor parameters (no global state access in widgets)

### Architecture Patterns
- **Mixins for screen decomposition**: `ChatEventHandlerMixin` and `ConversationActionsMixin` split `ChatScreen` logic into focused concerns
- **Delegate classes for subsystems**: `McpServerManager`, `McpOAuthManager`, `ImageAttachmentHandler` encapsulate complex lifecycle management
- **Event-driven communication**: `ChatService` emits `ChatEvent`s consumed by the UI via stream subscription
- **Callback injection**: `SamplingProcessor` and `MessageList` receive behavior via callbacks rather than holding service references

### Key Gotchas
- `ChatService` queues MCP notifications during streaming and flushes them after each LLM response (prevents notification UI from interfering with streaming)
- The message list is **reversed** (`ListView` with `reverse: true`) — index 0 is the bottom/newest item
- Elicitation messages are stored in the database but filtered out from API messages (`toApiMessage()` returns null)
- MCP session IDs are persisted per conversation+server pair and used for session resumption
- `OpenRouterService` uses PKCE OAuth flow — the API key is stored in SharedPreferences
- Tool calls from the streaming response come as a special `TOOL_CALLS:` prefixed chunk, not inline in the streamed text
- Reasoning/thinking content comes as `REASONING:` prefixed chunks in the stream
