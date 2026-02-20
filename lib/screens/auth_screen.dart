import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../services/openrouter_service.dart';
import '../utils/in_app_browser.dart';
import '../utils/privacy_constants.dart';

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
  bool _consentGiven = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initDeepLinkListener();
    _loadConsentState();
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadConsentState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _consentGiven = prefs.getBool('privacy_consent_given') ?? false;
      });
    }
  }

  Future<void> _saveConsentState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_consent_given', true);
  }

  /// Initialize deep link listener for OAuth callback
  void _initDeepLinkListener() {
    _deepLinkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        // Listen to both custom scheme (joey://auth) and HTTPS URL
        final isCustomScheme = uri.scheme == 'joey' && uri.host == 'auth';
        final isHttpsCallback =
            uri.scheme == 'https' &&
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
    // Dismiss the in-app browser (SFSafariViewController / Chrome Custom Tab)
    // so the user sees the app immediately after authenticating.
    await closeInAppBrowser();

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
      await _saveConsentState();

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
      _errorMessage = null;
    });

    try {
      final authUrl = _openRouterService.startAuthFlow();
      final uri = Uri.parse(authUrl);
      await launchInAppBrowser(uri, context: context);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to start authentication: ${e.toString()}';
      });
    }
  }

  void _openPrivacyPolicy() {
    launchInAppBrowser(Uri.parse(PrivacyConstants.privacyPolicyUrl), context: context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
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
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Data sharing disclosure
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Data Sharing Notice',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'By connecting, your conversation messages will be sent to OpenRouter for AI processing, and to any MCP servers you configure for tool execution. Your data is stored locally on your device and is not collected by Joey.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _openPrivacyPolicy,
                      child: Text(
                        'Read our Privacy Policy',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                          decorationColor: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Consent checkbox
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _consentGiven,
                      onChanged: _isAuthenticating
                          ? null
                          : (bool? value) {
                              setState(() {
                                _consentGiven = value ?? false;
                              });
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _isAuthenticating
                          ? null
                          : () {
                              setState(() {
                                _consentGiven = !_consentGiven;
                              });
                            },
                      child: Text(
                        'I understand and agree to the data sharing described above',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

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
                onPressed: (_isAuthenticating || !_consentGiven) ? null : _startAuth,
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
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'What is OpenRouter?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'OpenRouter provides access to multiple AI models through a single API. You\'ll be redirected to their website to authorize this app.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
