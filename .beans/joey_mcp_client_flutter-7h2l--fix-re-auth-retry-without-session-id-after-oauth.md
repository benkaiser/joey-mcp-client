---
# joey_mcp_client_flutter-7h2l
title: 'Fix re-auth: retry without session ID after OAuth'
status: completed
type: bug
priority: normal
created_at: 2026-02-09T03:05:04Z
updated_at: 2026-02-09T03:05:41Z
---

After re-authenticating OAuth for an MCP server, the re-initialization resumes with the old session ID which the server rejects (400: No valid session). Need to clear old session and reinitialize fresh after OAuth completes.