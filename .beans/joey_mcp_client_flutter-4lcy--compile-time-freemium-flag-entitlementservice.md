---
# joey_mcp_client_flutter-4lcy
title: Compile-time freemium flag + EntitlementService
status: completed
type: task
priority: normal
created_at: 2026-07-26T23:30:58Z
updated_at: 2026-07-26T23:41:53Z
parent: joey_mcp_client_flutter-xt6q
---

Add const kFreemiumEnabled = bool.fromEnvironment('JOEY_FREEMIUM', default false). Add EntitlementService (ChangeNotifier) exposing isPremium (= !kFreemiumEnabled || hasPurchased), maxMcpServers, historyEnabled, localToolsEnabled. Wire into MultiProvider in main.dart. Persist purchase flag in SharedPreferences.