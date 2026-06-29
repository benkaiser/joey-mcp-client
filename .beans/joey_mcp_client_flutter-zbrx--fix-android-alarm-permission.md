---
# joey_mcp_client_flutter-zbrx
title: Fix Android alarm permission
status: completed
type: bug
priority: normal
created_at: 2026-06-29T03:40:20Z
updated_at: 2026-06-29T03:41:09Z
---

The local Android alarm tool fails when launching ACTION_SET_ALARM because the app is missing com.android.alarm.permission.SET_ALARM. Add the required manifest permission and validate the Android build.