---
# joey_mcp_client_flutter-j1fd
title: Fix McpAppWebView blank iframe and about:blank dialog on macOS
status: completed
type: bug
priority: normal
created_at: 2026-02-23T03:38:18Z
updated_at: 2026-02-23T03:38:39Z
---

shouldOverrideUrlLoading intercepts the initial about:blank base URL navigation from loadData(), which causes macOS to try to open about:blank in an external app (showing Finder dialog) and prevents the HTML from loading. Fix: allow about:blank navigations to proceed.