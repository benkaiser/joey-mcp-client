---
# joey_mcp_client_flutter-bew8
title: Cap message input height to 4 lines with scroll
status: completed
type: bug
priority: normal
created_at: 2026-02-21T11:52:07Z
updated_at: 2026-02-21T11:52:20Z
---

When users type excessively large text in the message input, a 'bottom overflowed by' warning appears. Fix by setting maxLines to 4 (with minLines: 1) so the TextField grows up to 4 lines then scrolls internally.