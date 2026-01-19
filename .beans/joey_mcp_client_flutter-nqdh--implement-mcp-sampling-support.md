---
# joey_mcp_client_flutter-nqdh
title: Implement MCP sampling support
status: completed
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
- [x] Test sampling flow end-to-end

## Implementation Notes

All components have been implemented and tested:
- MCP client now declares sampling capability
- Sampling request handler registered with all MCP clients
- SamplingRequestDialog provides human-in-the-loop approval
- Message format conversion between MCP and OpenRouter
- Model selection based on preferences
- Comprehensive documentation added

The implementation follows the MCP spec 2025-06-18 and includes human review for all sampling requests as required for security.