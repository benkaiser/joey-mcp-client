---
# joey_mcp_client_flutter-vis0
title: 'Implement MCP Apps (SEP-1865): Interactive UI for MCP tool results'
status: completed
type: feature
priority: normal
created_at: 2026-02-23T00:45:47Z
updated_at: 2026-02-23T12:26:48Z
---

Implement the MCP Apps extension (SEP-1865) to render interactive HTML UIs returned by MCP servers as tool results.

## Spec Reference

The full specification lives at `ai_docs/mcp-spec.md` in this repo (SEP-1865: MCP Apps: Interactive User Interfaces for MCP).

## Background

MCP Apps allows servers to declare UI resources (`ui://` scheme) and link them to tools via `_meta.ui.resourceUri`. When a tool with UI metadata is called, the host renders the server-provided HTML in a sandboxed container and facilitates bidirectional JSON-RPC communication between the UI and the host.

Our fork of `mcp_dart` (github.com/benkaiser/mcp_dart) already supports the necessary primitives: `extensions` capability negotiation, `_meta` on tools, `resources/read`, and `structuredContent` on tool results.

## Implementation Approach

### 1. Capability Negotiation
- During `initialize`, advertise `extensions["io.modelcontextprotocol/ui"]` with `mimeTypes: ["text/html;profile=mcp-app"]` in `ClientCapabilities`
- Update `McpClientService` to set this when connecting to servers

### 2. Tool Discovery & UI Detection
- After `tools/list`, check each tool's `_meta.ui.resourceUri` for UI associations
- Prefetch UI resources via `resources/read` for `ui://` URIs and cache them
- Respect `_meta.ui.visibility` — filter tools with `visibility: ["app"]` from the LLM's tool list

### 3. UI Rendering (the core work)
- When a tool call returns and has `_meta.ui.resourceUri`, render the associated HTML resource
- Use Flutter's `webview_flutter` (or `InAppWebView`) to display the HTML in a sandboxed WebView
- Build CSP headers from the resource's `_meta.ui.csp` metadata
- Implement the `postMessage` bridge between the WebView and Dart for JSON-RPC communication

### 4. Host ↔ View Communication Protocol
- Implement the `ui/initialize` → `McpUiInitializeResult` handshake
- Send `ui/notifications/tool-input` (tool arguments) and `ui/notifications/tool-result` after tool execution
- Handle View → Host requests: `tools/call`, `resources/read`, `ui/open-link`, `ui/message`, `ui/update-model-context`
- Handle View → Host notifications: `ui/notifications/size-changed`, `notifications/message`
- Send Host → View notifications: `ui/notifications/host-context-changed`, `ui/notifications/tool-cancelled`, `ui/resource-teardown`

### 5. Theming & Display
- Pass theme info (light/dark) and CSS variables via `HostContext.styles.variables` in the initialize result
- Support `containerDimensions` for sizing the WebView
- Support display modes (`inline`, `fullscreen`) — `pip` can be deferred

### 6. Integration Points
- `ChatService` / `ChatEventHandlerMixin` — detect UI tools and trigger rendering after tool calls
- `McpClientService` — capability negotiation, resource prefetching, proxying `tools/call` from View
- `MessageList` — render the WebView inline within the message flow where tool results appear
- New widget/service for managing the WebView lifecycle and the JSON-RPC bridge

### Key Considerations
- Security: enforce CSP, sandbox the WebView, validate all incoming JSON-RPC from the View
- Graceful degradation: tools must still work as text-only if no UI resource is present (the `content` array in tool results is always the text fallback)
- Platform differences: WebView behavior varies across iOS/Android/macOS/desktop — test thoroughly
- The spec uses iframes (web context) but we're Flutter, so the equivalent is a sandboxed WebView with `postMessage` bridged via JavaScript channels