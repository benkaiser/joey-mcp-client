---
# joey_mcp_client_flutter-pzau
title: Implement MCP server notification support
status: completed
type: feature
priority: normal
created_at: 2026-02-05T09:44:48Z
updated_at: 2026-02-05T09:52:11Z
---

Add support for receiving MCP server notifications (e.g., progress notifications) and plumbing them through to the UI.

## Implementation

Added notification support to the MCP client that handles:
- **Progress notifications**: Displayed in the loading indicator with percentage/progress info
- **Logging notifications**: Warning/error levels shown as snackbars
- **Tools list changed**: Auto-refreshes tools when server notifies of changes
- **Resources list changed**: Logged for future use

### Changes Made

1. **McpClientService** ([mcp_client_service.dart](lib/services/mcp_client_service.dart)):
   - Added `McpProgressNotification` and `McpLoggingNotification` types
   - Added callbacks: `onProgressNotification`, `onLoggingNotification`, `onToolsListChanged`, `onResourcesListChanged`
   - Set up notification handlers after connecting via `setNotificationHandler`
   - Wired up `onprogress` callback   - Wired up `onprogress` callback   - Wired up `onprogress` callback   - Wired up `onprogress` callback   - Wired up `onprogress` callback   - Wired up `onprogress` callback   - Wired up `onprogress` cstChanged`, `McpReso   - Wired up `onprogress` callback   - Wired up `onpr callbacks to emit events

3. **ChatScreen** ([chat_screen.dart](lib/screens/chat_screen.dart)):
3. **ChatScreen** ([chat_screen.dart](lib/screens/chat_screen.dart) E3. **ChatScreen** ([chat_screen.dart](lib/screens/chat_screen.dart)e
   - Added   - Added   - Added   - Added   - Added   - Adatus t   - Added   - r f   - Added   - Added   - Added   - Added   - Added   - Adatus t   - Added   - r f   - Ast changed (refreshes tools)

## Checklist
- [x] Research mcp_dart library for notification handling
- [x] Add notification listener to McpClientService
- [x] Create notification event types for ChatService
- [x] Update chat_screen.dart to display notifications
- [x] Test with progress notifications