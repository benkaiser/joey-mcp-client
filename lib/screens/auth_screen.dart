import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import '../services/openrouter_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final OpenRouterService _openRouterService = OpenRouterService();
  final AppLinks _appLinks = AppLinks();
  StreamSubscription? _deepLinkSubscription;
  bool _isAuthenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initDeepLinkListener();
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  /// Initialize deep link listener for OAuth callback
  void _initDeepLinkListener() {
    _deepLinkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        // Listen to both custom scheme (joey://auth) and HTTPS URL
        final isCustomScheme = uri.scheme == 'joey' && uri.host == 'auth';
        final isHttpsCallback = uri.scheme == 'https' &&
            uri.host == 'openrouterauth.benkaiser.dev' &&
            uri.path == '/api/auth';

        if (isCustomScheme || isHttpsCallback) {
          _handleAuthCallback(uri);
        }
      },
      onError: (err) {
        setState(() {
          _errorMessage = 'Deep link error: $err';
          _isAuthenticating = false;
        });
      },
    );
  }

  /// Handle OAuth callback with authorization code
  Future<void> _handleAuthCallback(Uri uri) async {
    final code = uri.queryParameters['code'];

    if (code == null) {
      setState(() {
        _errorMessage = 'No authorization code received';
        _isAuthenticating = false;
      });
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    try {
      await _openRouterService.exchangeCodeForKey(code);

      if (mounted) {
        // Navigate to conversation list
        Navigator.of(context).pushReplacementNamed('/conversations');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Authentication failed: ${e.toString()}';
        _isAuthenticating = false;
      });
    }
  }

  /// Start OAuth flow by opening OpenRouter in browser
  Future<void> _startAuth() async {
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    try {
      final authUrl = _openRouterService.startAuthFlow();
      final uri = Uri.parse(authUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch browser');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to start authentication: ${e.toString()}';
        _isAuthenticating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.chat_rounded,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome to Joey',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Connect with OpenRouter to start chatting with AI models',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Error message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Connect button
              FilledButton.icon(
                onPressed: _isAuthenticating ? null : _startAuth,
                icon: _isAuthenticating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.login),
                label: Text(
                  _isAuthenticating
                      ? 'Connecting...'
                      : 'Connect with OpenRouter',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),

              const SizedBox(height: 24),

              // Info text
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue[700],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'What is OpenRouter?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'OpenRouter provides access to multiple AI models through a single API. You\'ll be redirected to their website to authorize this app.',
                      style: TextStyle(fontSize: 13, color: Colors.blue[900]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
