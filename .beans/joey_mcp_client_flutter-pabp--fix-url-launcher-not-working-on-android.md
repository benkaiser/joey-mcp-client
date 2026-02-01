---
# joey_mcp_client_flutter-pabp
title: Fix URL launcher not working on Android
status: completed
type: bug
priority: normal
created_at: 2026-02-01T23:23:49Z
updated_at: 2026-02-01T23:24:00Z
---

On Android 11+, url_launcher cannot find a browser to handle URLs because the AndroidManifest.xml is missing the required queries for browsable intents. The error 'component name for ... is null' indicates that the package visibility restrictions are blocking the url_launcher from finding browsers.

## Fix
Add the required queries for browsable intents in AndroidManifest.xml so that url_launcher can properly detect and launch browsers.