---
# joey_mcp_client_flutter-u2x5
title: Allow manual input focus during iOS streaming
status: completed
type: bug
priority: normal
created_at: 2026-06-29T04:43:45Z
updated_at: 2026-06-29T04:44:14Z
---

Revise the iOS keyboard streaming fix so the app does not disable input focus during loading. It should only avoid automatically keeping/reopening the keyboard; users must still be able to tap and type while streaming.