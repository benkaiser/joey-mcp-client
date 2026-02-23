import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mcp_dart/mcp_dart.dart' show TextResourceContents;
import 'package:url_launcher/url_launcher.dart';
import '../models/mcp_app_ui.dart';
import '../models/pending_image.dart';
import '../services/mcp_app_ui_service.dart';
import '../services/mcp_client_service.dart';

/// Widget that renders MCP App HTML UI in a sandboxed WebView.
/// Provides a JSON-RPC bridge for bidirectional communication
/// between the MCP App View and the host (this Flutter app).
class McpAppWebView extends StatefulWidget {
  final McpAppUiData uiData;
  final String messageId;
  final McpClientService? mcpClient;
  final McpAppUiService? uiService;
  final Map<String, McpTool>? appOnlyTools;
  final void Function(String message, {List<PendingImage> images})? onUiMessage;
  final void Function(String messageId, List<dynamic> content, Map<String, dynamic>? structuredContent)? onUpdateModelContext;
  final String displayMode;
  final List<String> hostAvailableDisplayModes;
  final void Function(String messageId, String requestedMode)? onRequestDisplayMode;
  final void Function(String messageId, List<String> modes)? onViewCapabilitiesReceived;
  final void Function(String messageId, double height)? onHeightChanged;

  const McpAppWebView({
    super.key,
    required this.uiData,
    required this.messageId,
    this.mcpClient,
    this.uiService,
    this.appOnlyTools,
    this.onUiMessage,
    this.onUpdateModelContext,
    this.displayMode = 'inline',
    this.hostAvailableDisplayModes = const ['inline', 'fullscreen', 'pip'],
    this.onRequestDisplayMode,
    this.onViewCapabilitiesReceived,
    this.onHeightChanged,
  });

  @override
  State<McpAppWebView> createState() => _McpAppWebViewState();
}

class _McpAppWebViewState extends State<McpAppWebView>
    with AutomaticKeepAliveClientMixin {
  InAppWebViewController? _controller;
  bool _viewReady = false;
  bool _disposed = false;
  static const double _minHeight = 50.0;

  /// The InAppWebView widget, created once and reused across rebuilds.
  /// This is critical: platform views are destroyed when their element is
  /// unmounted, so we must return the *same widget instance* from [build]
  /// to guarantee Flutter reuses the element rather than recreating it.
  late final InAppWebView _webViewWidget;

  /// Max height capped at 40% of available screen to prevent
  /// the WebView from consuming the entire scroll view in inline mode.
  double _maxHeight(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return screenHeight * 0.4;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    debugPrint('MCP WebView [${widget.messageId}]: initState (hashCode=$hashCode)');
    _webViewWidget = _createWebView();
  }

  @override
  void didUpdateWidget(covariant McpAppWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.displayMode != widget.displayMode) {
      debugPrint('MCP WebView [${widget.messageId}]: displayMode changed ${oldWidget.displayMode} → ${widget.displayMode} (hashCode=$hashCode)');
      _sendHostContextChanged();
    }
  }

  /// Send ui/notifications/host-context-changed with updated hostContext fields.
  void _sendHostContextChanged() {
    if (_controller == null || !_viewReady) return;

    final notification = {
      'jsonrpc': '2.0',
      'method': 'ui/notifications/host-context-changed',
      'params': {
        'hostContext': {
          'displayMode': widget.displayMode,
          'availableDisplayModes': widget.hostAvailableDisplayModes,
        },
      },
    };

    final json = jsonEncode(notification);
    _safeEvaluateJavascript(
      'if(window.__mcpBridgeNotification) window.__mcpBridgeNotification(\'${_escapeJs(json)}\');',
    );
  }

  @override
  void dispose() {
    debugPrint('MCP WebView [${widget.messageId}]: dispose (hashCode=$hashCode)');
    _disposed = true;
    _sendTeardown();
    super.dispose();
  }

  /// Safely evaluate JavaScript, ignoring errors if the WebView has been disposed.
  Future<void> _safeEvaluateJavascript(String source) async {
    if (_disposed || _controller == null) return;
    try {
      await _controller!.evaluateJavascript(source: source);
    } catch (e) {
      debugPrint('MCP WebView: evaluateJavascript failed (likely disposed): $e');
    }
  }

  /// Build the full HTML with CSP meta tag, theme CSS variables, and JS bridge injected
  String _buildHtml() {
    final csp = widget.uiService?.buildCsp(widget.uiData.cspMeta) ?? '';
    debugPrint('MCP WebView: CSP: $csp');
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Get theme colors as CSS values
    final bgColor = _colorToCss(colorScheme.surface);
    final textColor = _colorToCss(colorScheme.onSurface);
    final primaryColor = _colorToCss(colorScheme.primary);
    final secondaryColor = _colorToCss(colorScheme.secondary);
    final errorColor = _colorToCss(colorScheme.error);
    final borderColor = _colorToCss(colorScheme.outline);

    // JavaScript bridge shim
    // This intercepts postMessage calls and routes them through flutter_inappwebview's handler.
    //
    // The MCP Apps SDK (PostMessageTransport) communicates via:
    //   - Outbound: window.parent.postMessage(jsonRpcMessage, "*")
    //   - Inbound:  window.addEventListener('message', handler) with event.source check
    //
    // In a loadData WebView, window.parent === window, so we intercept postMessage to
    // route outbound messages through Flutter's callHandler bridge. For inbound messages
    // from the host (responses and notifications), we dispatch MessageEvents with
    // source: window so the SDK's event.source === window.parent check passes.
    const jsBridge = r'''
<script>
(function() {
  // JSON-RPC request ID counter for the bridge layer
  let _bridgeId = 0;
  // Map bridge IDs to {originalId, resolve, reject} so we can route responses
  const _pendingRequests = {};

  // Helper: dispatch a MessageEvent that the SDK's PostMessageTransport will accept.
  // The SDK checks event.source === window.parent; in a loadData WebView
  // window.parent === window, so we set source: window.
  function _dispatchToView(data) {
    window.dispatchEvent(new MessageEvent('message', {
      data: data,
      source: window,
    }));
  }

  // Send a JSON-RPC message to Flutter via callHandler.
  // The message is sent as-is (stringified); Flutter will parse and respond.
  function _sendToHost(message) {
    window.flutter_inappwebview.callHandler('mcpBridge', JSON.stringify(message));
  }

  // Handle responses from the host (called via evaluateJavascript)
  window.__mcpBridgeResponse = function(responseJson) {
    try {
      const response = JSON.parse(responseJson);
      const bridgeId = response.id;
      const pending = _pendingRequests[bridgeId];
      if (pending) {
        delete _pendingRequests[bridgeId];
        // Re-map the bridge ID back to the original view ID
        response.id = pending.originalId;
        _dispatchToView(response);
      }
    } catch(e) {
      console.error('MCP Bridge response error:', e);
    }
  };

  // Handle notifications from the host (called via evaluateJavascript)
  window.__mcpBridgeNotification = function(notificationJson) {
    try {
      const notification = JSON.parse(notificationJson);
      _dispatchToView(notification);
    } catch(e) {
      console.error('MCP Bridge notification error:', e);
    }
  };

  // Intercept postMessage to capture outbound JSON-RPC messages from the SDK.
  // The SDK calls window.parent.postMessage(msg, "*"); since window.parent === window
  // in a loadData WebView, this override captures all outbound messages.
  const originalPostMessage = window.postMessage.bind(window);
  window.postMessage = function(message, targetOrigin) {
    if (typeof message === 'object' && message.jsonrpc === '2.0') {
      if (message.id !== undefined && message.id !== null) {
        // JSON-RPC request — assign a bridge ID and track the original ID
        const bridgeId = ++_bridgeId;
        _pendingRequests[bridgeId] = { originalId: message.id };
        _sendToHost({
          jsonrpc: '2.0',
          method: message.method,
          params: message.params || {},
          id: bridgeId,
        });
      } else {
        // JSON-RPC notification — forward as-is
        _sendToHost(message);
      }
    } else {
      originalPostMessage(message, targetOrigin);
    }
  };
})();
</script>
''';

    // Theme CSS variables
    final themeStyle = '''
<style>
:root {
  --mcp-host-bg: $bgColor;
  --mcp-host-text: $textColor;
  --mcp-host-primary: $primaryColor;
  --mcp-host-secondary: $secondaryColor;
  --mcp-host-error: $errorColor;
  --mcp-host-border: $borderColor;
  color-scheme: dark;
}
body {
  background-color: $bgColor;
  color: $textColor;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  margin: 0;
  padding: 8px;
}
</style>
''';

    String html = widget.uiData.html;

    // Inject CSP meta tag, theme styles, and JS bridge into <head>
    final headContent = '''
<meta http-equiv="Content-Security-Policy" content="$csp">
$themeStyle
$jsBridge
''';

    // Try to inject into existing <head>
    final headIndex = html.toLowerCase().indexOf('<head>');
    if (headIndex != -1) {
      final insertPos = headIndex + '<head>'.length;
      html = html.substring(0, insertPos) +
          headContent +
          html.substring(insertPos);
    } else {
      // No <head> tag — wrap the content
      html =
          '<!DOCTYPE html><html><head>$headContent</head><body>$html</body></html>';
    }

    return html;
  }

  String _colorToCss(Color color) {
    return 'rgb(${(color.r * 255).round()}, ${(color.g * 255).round()}, ${(color.b * 255).round()})';
  }

  /// Handle incoming JSON-RPC messages from the View
  Future<String?> _handleBridgeMessage(String messageJson) async {
    try {
      debugPrint('MCP WebView: Bridge message received: $messageJson');
      final message = jsonDecode(messageJson) as Map<String, dynamic>;
      final method = message['method'] as String?;
      final params = message['params'] as Map<String, dynamic>? ?? {};
      final id = message['id'];

      if (method == null) return null;

      // Handle notifications (no id)
      if (id == null) {
        _handleNotification(method, params);
        return null;
      }

      // Handle requests (have id)
      try {
        final result = await _handleRequest(method, params);
        return jsonEncode({
          'jsonrpc': '2.0',
          'result': result,
          'id': id,
        });
      } catch (e) {
        return jsonEncode({
          'jsonrpc': '2.0',
          'error': {
            'code': -32603,
            'message': e.toString(),
          },
          'id': id,
        });
      }
    } catch (e) {
      debugPrint('MCP WebView: Failed to handle bridge message: $e');
      return null;
    }
  }

  /// Handle JSON-RPC notifications from the View
  void _handleNotification(String method, Map<String, dynamic> params) {
    debugPrint('MCP WebView: Received notification: $method');
    switch (method) {
      case 'ui/notifications/size-changed':
        final height = params['height'];
        if (height is num && mounted) {
          final clampedHeight = height.toDouble().clamp(_minHeight, _maxHeight(context));
          widget.onHeightChanged?.call(widget.messageId, clampedHeight);
        }
        break;

      case 'ui/notifications/initialized':
        debugPrint('MCP WebView: View initialized, sending tool data');
        _viewReady = true;
        _sendToolInput();
        _sendToolResult();
        break;

      case 'notifications/message':
        final msg = params['message'] as String?;
        if (msg != null) {
          debugPrint('MCP WebView: View message: $msg');
        }
        break;

      default:
        debugPrint('MCP WebView: Unknown notification: $method');
    }
  }

  /// Handle JSON-RPC requests from the View
  Future<Map<String, dynamic>> _handleRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    switch (method) {
      case 'ui/initialize':
        // View sends ui/initialize request expecting McpUiInitializeResult.
        // After receiving this response, the view will send
        // ui/notifications/initialized, at which point we send tool data.
        debugPrint('MCP WebView: View sent ui/initialize request, returning host capabilities');

        // Read view's declared available display modes from appCapabilities.
        // If the view doesn't declare any, default to all host-supported modes
        // so the user can still switch display modes.
        final appCapabilities = params['appCapabilities'] as Map<String, dynamic>?;
        final viewModes = appCapabilities?['availableDisplayModes'] as List<dynamic>?;
        if (viewModes != null) {
          final modesList = viewModes.map((e) => e.toString()).toList();
          debugPrint('MCP WebView: View declared availableDisplayModes: $modesList');
          widget.onViewCapabilitiesReceived?.call(widget.messageId, modesList);
        } else {
          // View didn't declare display modes — assume it supports all modes
          // the host offers, so the user gets fullscreen/PIP/hide controls.
          debugPrint('MCP WebView: View did not declare availableDisplayModes, '
              'defaulting to host modes: ${widget.hostAvailableDisplayModes}');
          widget.onViewCapabilitiesReceived?.call(
            widget.messageId,
            List<String>.from(widget.hostAvailableDisplayModes),
          );
        }

        return {
          'protocolVersion': '2026-01-26',
          'hostInfo': {
            'name': 'joey-mcp-client-flutter',
            'version': '1.0.0',
          },
          'hostCapabilities': {
            'openLinks': {},
            'serverTools': {},
            'serverResources': {},
            'logging': {},
            'message': {},
            'updateModelContext': {},
          },
          'hostContext': {
            'theme': 'dark',
            'locale': 'en',
            'displayMode': widget.displayMode,
            'availableDisplayModes': widget.hostAvailableDisplayModes,
          },
        };

      case 'ui/request-display-mode':
        final requestedMode = params['mode'] as String?;
        if (requestedMode == null) {
          throw Exception('Missing mode parameter');
        }
        // Delegate to ChatScreen which validates and applies the mode
        widget.onRequestDisplayMode?.call(widget.messageId, requestedMode);
        // Return the current mode — ChatScreen will update the prop which
        // triggers didUpdateWidget → host-context-changed notification
        return {'mode': requestedMode};

      case 'tools/call':
        return _handleToolCall(params);

      case 'resources/read':
        return _handleResourceRead(params);

      case 'ui/open-link':
        final url = params['url'] as String?;
        if (url != null) {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
        return {'success': true};

      case 'ui/message':
        // MCP spec: params has { role, content } where content is
        // either a single content part or an array of content parts.
        // Content parts can be { type: "text", text: "..." } or
        // { type: "image", data: "<base64>", mimeType: "image/png" }
        final content = params['content'];
        final List<Map<dynamic, dynamic>> contentParts;
        if (content is Map) {
          contentParts = [content];
        } else if (content is List) {
          contentParts = content.whereType<Map>().toList();
        } else {
          contentParts = [];
        }

        // Extract text parts
        final textParts = contentParts
            .where((c) => c['type'] == 'text')
            .map((c) => c['text'] as String?)
            .where((t) => t != null && t.isNotEmpty)
            .toList();
        final messageText = textParts.isNotEmpty ? textParts.join('\n') : '';

        // Extract image parts
        final images = <PendingImage>[];
        for (final part in contentParts) {
          if (part['type'] == 'image' && part['data'] is String) {
            try {
              final bytes = base64Decode(part['data'] as String);
              final mimeType = (part['mimeType'] as String?) ?? 'image/png';
              images.add(PendingImage(
                bytes: Uint8List.fromList(bytes),
                mimeType: mimeType,
              ));
            } catch (e) {
              debugPrint('MCP WebView: Failed to decode image: $e');
            }
          }
        }

        if (messageText.isNotEmpty || images.isNotEmpty) {
          widget.onUiMessage?.call(messageText, images: images);
        }
        return {'success': true};

      case 'ui/update-model-context':
        // Store context for future turns
        debugPrint('MCP WebView: Model context update: $params');
        final content = params['content'] as List<dynamic>? ?? [];
        final structuredContent = params['structuredContent'] as Map<String, dynamic>?;
        widget.onUpdateModelContext?.call(widget.messageId, content, structuredContent);
        return {};

      default:
        throw Exception('Unknown method: $method');
    }
  }

  /// Proxy tool call to MCP server
  Future<Map<String, dynamic>> _handleToolCall(
      Map<String, dynamic> params) async {
    final toolName = params['name'] as String?;
    final toolArgs = params['arguments'] as Map<String, dynamic>? ?? {};

    if (toolName == null) {
      throw Exception('Missing tool name');
    }

    if (widget.mcpClient == null) {
      throw Exception('No MCP client available');
    }

    final result = await widget.mcpClient!.callTool(toolName, toolArgs);

    // Convert result to JSON-RPC response format
    final contentList = result.content.map((c) {
      if (c.type == 'text') {
        return {'type': 'text', 'text': c.text};
      } else if (c.type == 'image') {
        return {'type': 'image', 'data': c.data, 'mimeType': c.mimeType};
      }
      return {'type': c.type};
    }).toList();

    return {
      'content': contentList,
      if (result.isError == true) 'isError': true,
    };
  }

  /// Proxy resource read to MCP server
  Future<Map<String, dynamic>> _handleResourceRead(
      Map<String, dynamic> params) async {
    final uri = params['uri'] as String?;

    if (uri == null) {
      throw Exception('Missing resource URI');
    }

    if (widget.mcpClient == null) {
      throw Exception('No MCP client available');
    }

    final result = await widget.mcpClient!.readResource(uri);

    final contentsList = result.contents.map((c) {
      final map = <String, dynamic>{'uri': c.uri};
      if (c.mimeType != null) map['mimeType'] = c.mimeType;
      if (c is TextResourceContents) {
        map['text'] = c.text;
      }
      return map;
    }).toList();

    return {'contents': contentsList};
  }

  /// Send tool input notification to the View
  void _sendToolInput() {
    if (_controller == null || !_viewReady) return;

    final notification = {
      'jsonrpc': '2.0',
      'method': 'ui/notifications/tool-input',
      'params': {
        'toolName': _toolNameFromUri(widget.uiData.resourceUri),
        'arguments': widget.uiData.toolArgs ?? {},
      },
    };

    final json = jsonEncode(notification);
    _safeEvaluateJavascript(
      'if(window.__mcpBridgeNotification) window.__mcpBridgeNotification(\'${_escapeJs(json)}\');',
    );
  }

  /// Send tool result notification to the View
  void _sendToolResult() {
    if (_controller == null || !_viewReady) return;
    if (widget.uiData.toolResultJson == null) return;

    try {
      final resultData = jsonDecode(widget.uiData.toolResultJson!);
      final notification = {
        'jsonrpc': '2.0',
        'method': 'ui/notifications/tool-result',
        'params': resultData,
      };

      final json = jsonEncode(notification);
      _safeEvaluateJavascript(
        'if(window.__mcpBridgeNotification) window.__mcpBridgeNotification(\'${_escapeJs(json)}\');',
      );
    } catch (e) {
      debugPrint('MCP WebView: Failed to send tool result: $e');
    }
  }

  /// Send teardown notification to the View
  void _sendTeardown() {
    if (_controller == null) return;

    final notification = {
      'jsonrpc': '2.0',
      'method': 'ui/notifications/teardown',
      'params': {},
    };

    final json = jsonEncode(notification);
    _safeEvaluateJavascript(
      'if(window.__mcpBridgeNotification) window.__mcpBridgeNotification(\'${_escapeJs(json)}\');',
    );
  }

  String _escapeJs(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }

  String _toolNameFromUri(String uri) {
    // Extract tool name from URI like "ui://server/toolName"
    final parts = Uri.tryParse(uri);
    if (parts != null && parts.pathSegments.isNotEmpty) {
      return parts.pathSegments.last;
    }
    return uri;
  }

  /// Create the InAppWebView widget once. Called from [initState].
  InAppWebView _createWebView() {
    return InAppWebView(
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          transparentBackground: true,
          disableHorizontalScroll: true,
          supportZoom: false,
          useHybridComposition: true,
          allowsInlineMediaPlayback: true,
          mediaPlaybackRequiresUserGesture: false,
          verticalScrollBarEnabled: true,
          horizontalScrollBarEnabled: false,
        ),
        onWebViewCreated: (controller) {
          debugPrint('MCP WebView [${widget.messageId}]: onWebViewCreated (hashCode=$hashCode, controller=${controller.hashCode})');
          _controller = controller;

          // Register the bridge handler
          controller.addJavaScriptHandler(
            handlerName: 'mcpBridge',
            callback: (args) {
              if (args.isNotEmpty) {
                final messageJson = args[0] as String;
                _handleBridgeMessage(messageJson).then((response) {
                  if (response != null) {
                    // Send response back via evaluateJavascript
                    _safeEvaluateJavascript(
                      'if(window.__mcpBridgeResponse) window.__mcpBridgeResponse(\'${_escapeJs(response)}\');',
                    );
                  }
                });
              }
              return null;
            },
          );

          // Load the HTML
          final html = _buildHtml();
          debugPrint('MCP WebView: Loading HTML (${html.length} chars)');
          controller.loadData(
            data: html,
            mimeType: 'text/html',
            encoding: 'utf-8',
            baseUrl: WebUri('about:blank'),
          );
        },
        onLoadStop: (controller, url) {
          debugPrint('MCP WebView: onLoadStop url=$url');
          // The view will initiate the handshake by sending ui/initialize request.
          // We don't need to send anything proactively.
        },
        onReceivedError: (controller, request, error) {
          debugPrint('MCP WebView: onReceivedError: ${error.description} (type: ${error.type}) for ${request.url}');
        },
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          final uri = navigationAction.request.url;
          if (uri == null) {
            return NavigationActionPolicy.ALLOW;
          }

          // Allow the initial about:blank load (used as baseUrl for loadData)
          final scheme = uri.scheme;
          if (scheme == 'about' || scheme.isEmpty) {
            return NavigationActionPolicy.ALLOW;
          }

          // Open all other navigation in external browser
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return NavigationActionPolicy.CANCEL;
        },
        onConsoleMessage: (controller, consoleMessage) {
          debugPrint(
              'MCP WebView Console [${consoleMessage.messageLevel}]: ${consoleMessage.message}');
        },
      );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin

    // IMPORTANT: Always return the same widget with no size-changing wrappers.
    // On macOS, changing the layout size of a platform view (InAppWebView)
    // causes the native WKWebView to be deallocated and recreated, losing all
    // state.  The parent (_WebViewHostState) is responsible for clipping and
    // positioning; this widget just fills whatever space it's given.
    return _webViewWidget;
  }
}
