---
# joey_mcp_client_flutter-abcx
title: Fix iOS reminders method channel
status: completed
type: bug
priority: normal
created_at: 2026-06-29T03:58:07Z
updated_at: 2026-06-29T04:00:14Z
---

Enabling the local Reminders tools on iOS throws MissingPluginException for com.kaiserapps.joey/local_reminders requestPermission. Fix method-channel registration so reminders permission and operations are available on the Flutter engine used by the app.