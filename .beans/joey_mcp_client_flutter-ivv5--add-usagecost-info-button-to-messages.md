---
# joey_mcp_client_flutter-ivv5
title: Add usage/cost info button to messages
status: completed
type: feature
priority: normal
created_at: 2026-02-17T13:07:13Z
updated_at: 2026-02-17T13:10:14Z
---

Capture OpenRouter streaming usage data (prompt_tokens, completion_tokens, total_tokens, cost) from the last SSE chunk and display it as a button under each assistant response/tool use message. Clicking shows a dialog with token/cost breakdown. Desktop shows tooltip on hover.

## Checklist
- [x] Create a UsageData model to hold token counts and cost info (stored as JSON string in usageData field)
- [x] Modify OpenRouterService.chatCompletionStream() to capture usage from final chunk and yield it as a special USAGE: prefixed message
- [x] Add UsageReceived event to ChatEvents
- [x] Modify ChatService to parse USAGE: prefix and emit UsageReceived event
- [x] Store usage data per-message in Message model (add usageData field)
- [x] Update database schema to support usageData column (v14 -> v15)
- [x] Handle UsageReceived event in ChatEventHandlerMixin (usage data is stored directly on messages via MessageCreated)
- [x] Create UsageInfoButton widget with bar chart icon
- [x] Create UsageDetailsDialog showing token/cost breakdown
- [x] Add tooltip on desktop hover
- [x] Add UsageInfoButton to MessageBubble action bar for assistant messages
- [x] Wire everything together end-to-end
- [x] Preserve usageData in MessageList formatted message for tool call display