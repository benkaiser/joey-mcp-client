---
# joey_mcp_client_flutter-81ez
title: Add golden_screenshot tests for Google Play Store submission
status: completed
type: feature
priority: normal
created_at: 2026-02-12T08:54:27Z
updated_at: 2026-02-12T08:56:33Z
---

Add the golden_screenshot pub library and create 5 Play Store screenshots with mock data:
1. Conversation list screen with multiple mock conversations
2. Chat with tool uses (showing MCP tool calls and results)
3. Chat with code blocks (showing syntax-highlighted code)
4. Chat with mermaid chart rendering
5. Empty new conversation screen showing command palette

## Checklist
- [ ] Add golden_screenshot as dev dependency
- [ ] Create screenshot test file with mock data
- [ ] Screenshot 1: Conversation list with mock conversations
- [ ] Screenshot 2: Chat showing tool calls and results
- [ ] Screenshot 3: Chat with code blocks in markdown
- [ ] Screenshot 4: Chat with mermaid diagram
- [ ] Screenshot 5: New conversation / command palette view
- [ ] Generate golden screenshots