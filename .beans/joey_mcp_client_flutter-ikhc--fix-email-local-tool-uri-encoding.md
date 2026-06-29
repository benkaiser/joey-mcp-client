---
# joey_mcp_client_flutter-ikhc
title: Fix email local tool URI encoding
status: completed
type: bug
priority: normal
created_at: 2026-06-29T03:30:39Z
updated_at: 2026-06-29T03:31:46Z
---

The local compose email tool emits mailto URLs with + characters for spaces. Update encoding so email subject/body/cc/bcc render spaces correctly in mail clients.