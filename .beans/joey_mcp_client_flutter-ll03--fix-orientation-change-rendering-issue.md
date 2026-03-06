---
# joey_mcp_client_flutter-ll03
title: Fix orientation change rendering issue
status: completed
type: bug
priority: normal
created_at: 2026-03-01T23:24:21Z
updated_at: 2026-03-01T23:24:49Z
---

The Flutter app doesn't properly re-render when switching between portrait and landscape on Android. The user has to switch back and forth for it to render correctly.

Root cause: SmoothMarkdown widget uses RepaintBoundary by default which can prevent proper relayout when constraints change during orientation changes. Combined with a reversed ListView, this causes stale width constraints to be used on the first rotation.

## Fix
Wrap SmoothMarkdown in a LayoutBuilder and give it a key that includes the available width, forcing Flutter to create a new element (and thus a fresh layout) whenever the constraints change.

## Checklist
- [ ] Add LayoutBuilder wrapper around SmoothMarkdown in MessageBubble
- [ ] Use width-based ValueKey on SmoothMarkdown to force rebuild on constraint changes
- [ ] Run flutter analyze to verify no new errors