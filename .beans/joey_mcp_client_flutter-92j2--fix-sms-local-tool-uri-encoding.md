---
# joey_mcp_client_flutter-92j2
title: Fix SMS local tool URI encoding
status: completed
type: bug
priority: normal
created_at: 2026-06-29T04:46:27Z
updated_at: 2026-06-29T04:46:59Z
---

The local compose SMS tool emits sms: URLs with + characters for spaces in the body on iOS. Update SMS URI construction to percent-encode spaces and message content correctly.