---
id: joey_mcp_client_flutter-9fc1
title: Implement MCP elicitation support
status: completed
type: feature
priority: normal
created: 2026-01-26
updated: 2026-01-26
---

Add support for MCP elicitation protocol with form and URL modes.

## Checklist
- [x] Update MCP client to declare elicitation capability
- [x] Add elicitation message model
- [x] Handle elicitation/create requests in MCP client
- [x] Handle notifications/elicitation/complete
- [x] Handle URLElicitationRequiredError errors
- [x] Create UI for URL mode elicitation (card with button)
- [x] Create UI for form mode elicitation (full-screen form)
- [x] Add form validation based on JSON schema
- [x] Update chat screen to display elicitation messages
- [x] Test form and URL elicitation flows
