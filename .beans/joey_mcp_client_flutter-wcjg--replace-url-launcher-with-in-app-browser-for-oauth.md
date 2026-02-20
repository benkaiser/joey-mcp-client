---
# joey_mcp_client_flutter-wcjg
title: Replace url_launcher with in-app browser for OAuth flows
status: completed
type: task
priority: normal
created_at: 2026-02-20T09:58:43Z
updated_at: 2026-02-20T09:59:40Z
---

Apple rejected the app because OAuth uses external browser (LaunchMode.externalApplication). Need to use SFSafariViewController on iOS, Chrome Custom Tabs on Android, and appropriate WebView on macOS.

## Checklist
- [ ] Add flutter_custom_tabs or equivalent package to pubspec.yaml
- [ ] Update auth_screen.dart to use in-app browser instead of url_launcher for OpenRouter OAuth
- [ ] Update mcp_oauth_manager.dart to use in-app browser instead of url_launcher for MCP OAuth
- [ ] Verify deep link callback still works with in-app browser
- [ ] Run flutter analyze to verify no errors