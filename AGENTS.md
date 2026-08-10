**IMPORTANT**: before you do anything else, run the `beans prime` command and heed its output.
**IMPORTANT**: Read files in their entirety, do not read portions of files unless the contents are longer than 2000 lines.

## Project Overview

**joey-mcp-client-flutter** is a cross-platform Flutter chat app that connects to AI models via OpenRouter and remote MCP servers over Streamable HTTP. Supports multiple MCP servers per conversation, tool calling, sampling, elicitation, OAuth, and image/audio attachments.

### Tech Stack
- **Flutter** (iOS, Android, macOS, Windows, Linux) — Dart SDK ^3.10.7
- **State**: Provider — **DB**: sqflite (schema v18) — **HTTP**: Dio
- **LLM**: OpenRouter (PKCE OAuth, SSE streaming) — **MCP**: `mcp_dart` (Streamable HTTP)

## Architecture

### Data Flow
```
User input → ChatScreen._sendMessage()
  → ChatService.runAgenticLoop()
    → OpenRouterService.chatCompletionStream()  (SSE streaming)
    → _executeToolCalls() → McpClientService.callTool()  (loops until done)
  ← ChatEvent stream → ChatEventHandlerMixin → setState() + ConversationProvider (SQLite)
```

### ChatScreen Composition
`ChatScreen` uses two mixins and three delegate classes:
- **ChatEventHandlerMixin** (`screens/chat_event_handler.dart`) — maps `ChatEvent`s to UI state
- **ConversationActionsMixin** (`screens/conversation_actions.dart`) — share, rename, model switch, title gen, JSON export
- **McpServerManager** (`services/mcp_server_manager.dart`) — MCP server lifecycle + session resumption
- **McpOAuthManager** (`services/mcp_oauth_manager.dart`) — OAuth flows for MCP servers
- **ImageAttachmentHandler** (`utils/image_attachment_handler.dart`) — image picking + clipboard paste

Rendering is delegated to `MessageList` (widget) and `MessageInput` (widget).

### Key Services
- **ChatService** (`services/chat_service.dart`) — agentic loop, tool execution, cancellation, emits `ChatEvent`s
- **SamplingProcessor** (`services/sampling_processor.dart`) — handles MCP sampling requests (server-initiated LLM calls), shares `executeToolCalls` callback with ChatService
- **McpClientService** (`services/mcp_client_service.dart`) — wraps `mcp_dart`: connect, call tools, session resumption, OAuth token injection, sampling/elicitation callbacks
- **OpenRouterService** (`services/openrouter_service.dart`) — OAuth PKCE, chat completion, streaming, model listing
- **DatabaseService** (`services/database_service.dart`) — SQLite tables: `conversations`, `messages`, `mcp_servers`, `conversation_mcp_servers`, `mcp_sessions`
- **ConversationImportExportService** (`services/conversation_import_export_service.dart`) — JSON backup export/import for conversations and messages

### Message Roles (`models/message.dart`)
`MessageRole` enum: `user`, `assistant`, `system`, `tool`, `elicitation` (local-only), `mcpNotification` (sent as context), `modelChange` (local-only). `toApiMessage()` returns null for local-only roles.

## Development

### Commands
- `flutter analyze` — must pass with zero new errors before committing
- `flutter test` — unit tests (`test/`)
- `flutter test integration_test/` — integration tests

### Flavors (free / pro)
- Android has product flavors `pro` (com.kaiserapps.joey, the existing app) and `free` (com.kaiserapps.joey.free, "Joey Free"). Android builds now require a flavor, e.g. `flutter build appbundle --release --flavor pro`.
- The free build gates premium features via a compile-time flag: pass `--dart-define=JOEY_FREEMIUM=true` (only official free-store builds). Source builds and the pro flavor default to unlocked. See `EntitlementService` / `kFreemiumEnabled` in `lib/services/entitlement_service.dart`.
- Free-tier limits: single persisted conversation, single MCP server, no on-device tools. Premium (non-consumable IAP `com.kaiserapps.joey.free.premium`) unlocks all three.
- Free release builds: `flutter build appbundle --release --flavor free --dart-define=JOEY_FREEMIUM=true` (Android) and `flutter build ipa --flavor free --dart-define=JOEY_FREEMIUM=true` (iOS). The iOS `free` flavor uses a shared Xcode `free` scheme + `Debug/Release/Profile-free` build configs that set `PRODUCT_BUNDLE_IDENTIFIER=com.kaiserapps.joey.free` and `APP_DISPLAY_NAME="Joey Free"` (Info.plist reads `CFBundleDisplayName` from `$(APP_DISPLAY_NAME)`). The pro iOS build stays the default `Runner` scheme (`flutter build ipa --release`, no flavor).
- Free-tier MCP limit is enforced globally in `mcp_servers_screen.dart`: free users can configure only ONE MCP server total (adding a 2nd shows the paywall); they must edit/remove the existing one to switch.

### Conventions
- Provider for state (not Riverpod), Dio for HTTP, sqflite for storage
- Models use `toMap()`/`fromMap()` + `copyWith()` for immutability
- Services are per-conversation, not singletons (except OpenRouterService/DatabaseService)
- Widgets receive data and callbacks via constructor — no direct service access

### Gotchas
- The effective system prompt is the global one (Settings, `DefaultModelService.getSystemPrompt()`) plus the optional `systemPrompt` of each *connected* MCP server, joined with newlines — see `ChatService.buildSystemPrompt()`
- `ChatService` queues MCP notifications during streaming, flushes after each LLM response
- `MessageList` uses a **reversed** `ListView` — index 0 is the bottom (newest). Streaming content is frozen when user scrolls up to prevent position shifting.
- Streaming chunks use special prefixes: `TOOL_CALLS:` for tool calls, `REASONING:` for thinking content
- MCP session IDs are persisted per conversation+server and used for session resumption
- OpenRouter API key is stored in SharedPreferences (PKCE OAuth flow)
- **DB migrations affect import/export**: The JSON export format uses `toMap()`/`fromMap()` from the models, which mirror the DB schema. When adding new columns via a migration: (1) keep new model fields nullable so `fromMap()` tolerates older exports missing the key, (2) if a new field is required, bump the export envelope version in `ConversationImportExportService` and handle the old version gracefully, (3) update the schema version number in this file

## Publishing

### Version Bumping
- Version is in `pubspec.yaml` as `version: X.Y.Z+buildNumber` (e.g. `1.2.0+10`)
- Bump both the version name and build number for each release
- iOS version must be higher than the currently live App Store version (currently `1.1`), so use `1.2.0+` or higher
- Build numbers must be strictly increasing across both platforms

### Android (Google Play)
- **Build**: `flutter build appbundle --release`
- **Deploy**: `cd android && fastlane deploy`
- Fastlane config is in `android/fastlane/` with the Appfile and Fastfile
- Google Play service account key is stored at `~/.config/supply/play-store-key.json` (not in repo)
- Changelogs go in `android/fastlane/metadata/android/en-US/changelogs/{buildNumber}.txt`

### iOS (App Store)
- **Build**: `flutter build ipa --release`
- **Deploy**: `cd ios && fastlane deploy`
- **TestFlight only**: `cd ios && fastlane beta`
- Fastlane config is in `ios/fastlane/` with the Appfile and Fastfile
- App Store Connect API key is stored at `~/.config/appstore/AuthKey_L2XRGXQYP6.p8` (not in repo)
- The `deploy` lane uploads to App Store Connect, runs precheck, submits for review, and auto-releases on approval
- The `beta` lane uploads to TestFlight and skips waiting for build processing
- Release notes go in `ios/fastlane/metadata/en-US/release_notes.txt` (required for review submission)

### Desktop (GitHub Release)
- **Trigger**: `gh workflow run release.yml -f version=X.Y.Z` kicks off macOS, Windows, and Linux builds in parallel
- Workflow creates a GitHub release `vX.Y.Z` with all three platform artifacts attached
- Windows and Linux builds are experimental
