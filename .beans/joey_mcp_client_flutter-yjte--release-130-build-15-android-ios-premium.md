---
# joey_mcp_client_flutter-yjte
title: Release 1.3.0 (build 15) — Android + iOS premium
status: in-progress
type: task
created_at: 2026-08-10T01:27:00Z
updated_at: 2026-08-10T01:27:00Z
---

Cut and deploy premium (pro) builds for Android and iOS at 1.3.0+15. Ships: mcp_dart 2.4.0 upgrade + OAuth DCR, per-MCP-server custom system prompts, plus in-flight working-tree changes. Deploy via fastlane deploy lanes.

## Checklist
- [ ] Bump pubspec version to 1.3.0+15
- [ ] Add Android changelog 15.txt (pro-focused)
- [ ] Update iOS release_notes.txt (pro-focused)
- [ ] Commit entire working tree as release
- [ ] flutter build appbundle --release --flavor pro
- [ ] cd android && fastlane deploy
- [ ] flutter build ipa --release
- [ ] cd ios && fastlane deploy