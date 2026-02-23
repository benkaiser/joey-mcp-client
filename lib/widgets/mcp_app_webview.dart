import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mcp_dart/mcp_dart.dart' show TextResourceContents;
import 'package:url_launcher/url_launcher.dart';
import '../models/mcp_app_ui.dart';
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
  final void Function(String message)? onUiMessage;

  const McpAppWebView({
    super.key,
    required this.uiData,
    required this.messageId,
    this.mcpClient,
    this.uiService,
    this.appOnlyTools,
    this.onUiMessage,
  });

  @override
  State<McpAppWebView> createState() => _McpAppWebViewState();
}

class _McpAppWebViewState extends State<McpAppWebView>
    with AutomaticKeepAliveClientMixin {
  InAppWebViewController? _controller;
  double _height = 300.0;
  bool _initialized = false;
  bool _viewReady = false;
  bool _disposed = false;
  static const double _minHeight = 50.0;
  static const double _maxHeight = 800.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
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
    // This intercepts postMessage calls and routes them through flutter_inappwebview's handler
    const jsBridge = r'''
<script>
(function() {
  // JSON-RPC request ID counter
  let _rpcId = 0;
  const _pendingRequests = {};

  // The MCP bridge object exposed to the View
  window.__mcpBridge = {
    // Send a JSON-RPC request to the host and return a promise
    sendRequest: function(method, params) {
      return new Promise(function(resolve, reject) {
        const id = ++_rpcId;
        _pendingRequests[id] = { resolve: resolve, reject: reject };
        window.flutter_inappwebview.callHandler('mcpBridge', JSON.stringify({
          jsonrpc: '2.0',
          method: method,
          params: params || {},
          id: id
        }));
      });
    },
    // Send a JSON-RPC notification to the host (no response expected)
    sendNotification: function(method, params) {
      window.flutter_inappwebview.callHandler('mcpBridge', JSON.stringify({
        jsonrpc: '2.0',
        method: method,
        params: params || {}
      }));
    }
  };

  // Handle responses from the host
  window.__mcpBridgeResponse = function(responseJson) {
    try {
      const response = JSON.parse(responseJson);
      if (response.id && _pendingRequests[response.id]) {
        const pending = _pendingRequests[response.id];
        delete _pendingRequests[response.id];
        if (response.error) {
          pending.reject(new Error(response.error.message || 'Unknown error'));
        } else {
          pending.resolve(response.result);
        }
      }
    } catch(e) {
      console.error('MCP Bridge response error:', e);
    }
  };

  // Handle notifications from the host to the View
  window.__mcpBridgeNotification = function(notificationJson) {
    try {
      const notification = JSON.parse(notificationJson);
      if (window.__mcpViewHandler) {
        window.__mcpViewHandler(notification);
      }
    } catch(e) {
      console.error('MCP Bridge notification error:', e);
    }
  };

  // Intercept window.parent.postMessage for compatibility
  const originalPostMessage = window.postMessage.bind(window);
  window.postMessage = function(message, targetOrigin) {
    if (typeof message === 'object' && message.jsonrpc === '2.0') {
      if (message.id) {
        window.__mcpBridge.sendRequest(message.method, message.params)
          .then(function(result) {
            window.dispatchEvent(new MessageEvent('message', {
              data: { jsonrpc: '2.0', result: result, id: message.id }
            }));
          })
          .catch(function(err) {
            window.dispatchEvent(new MessageEvent('message', {
              data: { jsonrpc: '2.0', error: { code: -1, message: err.message }, id: message.id }
            }));
          });
      } else {
        window.__mcpBridge.sendNotification(message.method, message.params);
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
        if (height is num) {
          setState(() {
            _height = height.toDouble().clamp(_minHeight, _maxHeight);
          });
        }
        break;

      case 'ui/notifications/initialized':
        debugPrint('MCP WebView: View initialized');
        _viewReady = true;
        _sendToolInput();
        _sendToolResult();
        break;

      case 'ui/initialize':
        // View is announcing it's ready — respond with host capabilities.
        // Some views send this as a notification, others as a request.
        debugPrint('MCP WebView: View sent ui/initialize notification, sending host init');
        if (!_initialized) {
          _sendInitialize();
        }
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
        // View is sending ui/initialize as a request expecting host capabilities back.
        debugPrint('MCP WebView: View sent ui/initialize request, returning host capabilities');
        _initialized = true;
        return {
          'hostContext': {
            'theme': 'dark',
            'locale': 'en',
          },
          'hostCapabilities': {
            'tools/call': true,
            'resources/read': true,
            'ui/open-link': true,
            'ui/message': true,
            'ui/update-model-context': true,
          },
          'hostInfo': {
            'name': 'joey-mcp-client-flutter',
            'version': '1.0.0',
          },
        };

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
        final message = params['message'] as String?;
        if (message != null) {
          widget.onUiMessage?.call(message);
        }
        return {'success': true};

      case 'ui/update-model-context':
        // Store context for future turns — for now just acknowledge
        debugPrint('MCP WebView: Model context update: $params');
        return {'success': true};

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

  /// Send the ui/initialize handshake to the View
  void _sendInitialize() {
    if (_controller == null) return;

    final initResult = {
      'jsonrpc': '2.0',
      'method': 'ui/initialize',
      'params': {
        'hostContext': {
          'theme': 'dark',
          'locale': 'en',
        },
        'hostCapabilities': {
          'tools/call': true,
          'resources/read': true,
          'ui/open-link': true,
          'ui/message': true,
          'ui/update-model-context': true,
        },
        'hostInfo': {
          'name': 'joey-mcp-client-flutter',
          'version': '1.0.0',
        },
      },
    };

    final json = jsonEncode(initResult);
    _safeEvaluateJavascript(
      'if(window.__mcpBridgeNotification) window.__mcpBridgeNotification(\'${_escapeJs(json)}\');',
    );
    _initialized = true;
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    return Container(
      height: _height,
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        border: Border.all(
          color:
              Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InAppWebView(
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          transparentBackground: true,
          disableHorizontalScroll: true,
          supportZoom: false,
          useHybridComposition: true,
          allowsInlineMediaPlayback: true,
          mediaPlaybackRequiresUserGesture: false,
        ),
        onWebViewCreated: (controller) {
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
          controller.loadData(
            data: html,
            mimeType: 'text/html',
            encoding: 'utf-8',
            baseUrl: WebUri('about:blank'),
          );
        },
        onLoadStop: (controller, url) {
          if (!_initialized) {
            _sendInitialize();
          }
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
      ),
    );
  }
}
