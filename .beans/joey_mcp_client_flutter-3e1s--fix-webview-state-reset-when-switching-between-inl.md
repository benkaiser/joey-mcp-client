---
# joey_mcp_client_flutter-3e1s
title: Fix WebView state reset when switching between inline/fullscreen/pip modes
status: completed
type: bug
priority: normal
created_at: 2026-02-23T13:29:44Z
updated_at: 2026-02-23T13:33:24Z
---

When switching between inline conversation mode and fullscreen/pip modes, the WebView state is lost because Flutter destroys and recreates the platform view. The _WebViewHost widget wraps the content in different parent widget types (Positioned.fill/Material/SafeArea for fullscreen, PipOverlay for PIP, Positioned/CompositedTransformFollower for inline), which causes Flutter to unmount and remount the child. Fix: always use the same parent widget structure and control visibility/positioning without changing the WebView's ancestor chain.