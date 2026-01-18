# Resources

Helpful resources for developing and extending Joey MCP Client.

## MCP UI Components / Apps

### In-App WebView for Flutter
**URL**: https://inappwebview.dev/docs/webview/in-app-webview

For rendering MCP Apps UI components within the Flutter app. This library provides a full-featured WebView widget that can be used to display interactive web-based UI returned from MCP servers.

**Key Features**:
- Full WebView functionality in Flutter
- JavaScript execution and communication
- Cookie management
- Custom user agents
- Cross-platform support (iOS, Android, macOS, Windows, Linux)

### MCP Apps Extension Specification
**URL**: https://github.com/modelcontextprotocol/ext-apps?tab=readme-ov-file

Official specification for how MCP UI components should be sent and rendered. This extension defines how MCP servers can return interactive UI components (HTML/CSS/JS) that clients can display.

**Key Concepts**:
- Apps as first-class MCP primitives
- HTML-based UI components returned from servers
- Sandboxed execution environment
- Message passing between app and client
- Support for forms, data visualization, and interactive tools

## Implementation Guide

To implement MCP Apps support in this Flutter client:

1. **Install the WebView package**:
   ```yaml
   dependencies:
     flutter_inappwebview: ^6.0.0
   ```

2. **Create an AppViewer widget** to render MCP apps using InAppWebView

3. **Handle app responses** from MCP servers according to the ext-apps spec

4. **Implement message passing** between the WebView and Flutter app for bidirectional communication

5. **Add app management** to show/hide apps in the conversation UI

## Future Enhancements

- [ ] Implement MCP Apps support using flutter_inappwebview
- [ ] Add app viewer UI component
- [ ] Handle app lifecycle (show, hide, update)
- [ ] Implement secure message passing between apps and client
- [ ] Add app permissions and sandboxing
- [ ] Support app state persistence across sessions
