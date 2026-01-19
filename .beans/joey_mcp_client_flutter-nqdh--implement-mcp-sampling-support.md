---
# joey_mcp_client_flutter-nqdh
title: Implement MCP sampling support
status: in-progress
type: feature
created_at: 2026-01-19T04:55:09Z
updated_at: 2026-01-19T04:55:09Z
---

Add support for MCP sampling/createMessage requests from servers, with human-in-the-loop approval UI.

## Checklist
- [x] Add sampling capability to MCP client initialization
- [x] Implement incoming request handler for sampling/createMessage
- [x] Create SamplingRequestDialog widget for user approval
- [x] Integrate sampling into ChatService
- [x] Update MCP client to handle sampling requests
- [x] Add sampling request/response to UI
- [ ] Test sampling flow end-to-end