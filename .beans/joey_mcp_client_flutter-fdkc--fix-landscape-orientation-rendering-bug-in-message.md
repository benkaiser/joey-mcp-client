---
# joey_mcp_client_flutter-fdkc
title: Fix landscape orientation rendering bug in message bubbles
status: completed
type: bug
priority: normal
created_at: 2026-03-01T23:43:16Z
updated_at: 2026-03-01T23:54:15Z
---

The orientation rendering bug affects the ENTIRE app (not just message bubbles) because InAppWebView uses useHybridComposition: true, which embeds native Android views directly into the Flutter view hierarchy. This causes rendering corruption on orientation changes that persists even after leaving the screen with the WebView. The fix is to switch to texture-based composition (useHybridComposition: false) and also disable the internal RepaintBoundary in SmoothMarkdown for good measure.