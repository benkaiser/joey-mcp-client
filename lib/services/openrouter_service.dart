import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'dart:math';

class OpenRouterService {
  static const String _apiKeyKey = 'openrouter_api_key';
  static const String _authUrl = 'https://openrouter.ai/auth';
  static const String _keysUrl = 'https://openrouter.ai/api/v1/auth/keys';
  static const String _callbackUrl =
      'https://openrouterauth.benkaiser.dev/api/auth';

  final Dio _dio = Dio();
  String? _codeVerifier;

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(_apiKeyKey);
    return apiKey != null && apiKey.isNotEmpty;
  }

  /// Get the stored API key
  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey);
  }

  /// Clear the stored API key (logout)
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyKey);
  }

  /// Generate a random code verifier (43-128 characters)
  String _generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      128,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  /// Generate SHA-256 code challenge from code verifier
  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    // Convert to base64url (RFC 4648)
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Start the OAuth flow and return the authorization URL
  String startAuthFlow() {
    // Generate and store code verifier
    _codeVerifier = _generateCodeVerifier();

    // Generate code challenge
    final codeChallenge = _generateCodeChallenge(_codeVerifier!);

    // Build authorization URL
    final encodedCallbackUrl = Uri.encodeComponent(_callbackUrl);
    final url =
        '$_authUrl?callback_url=$encodedCallbackUrl&code_challenge=$codeChallenge&code_challenge_method=S256';

    return url;
  }

  /// Exchange authorization code for API key
  Future<String> exchangeCodeForKey(String code) async {
    if (_codeVerifier == null) {
      throw Exception('Code verifier not found. Please restart the auth flow.');
    }

    try {
      final response = await _dio.post(
        _keysUrl,
        data: {
          'code': code,
          'code_verifier': _codeVerifier,
          'code_challenge_method': 'S256',
        },
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      if (response.statusCode == 200 && response.data != null) {
        final key = response.data['key'] as String?;
        if (key == null || key.isEmpty) {
          throw Exception('Invalid response: API key not found');
        }

        // Store the API key
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_apiKeyKey, key);

        // Clear the code verifier
        _codeVerifier = null;

        return key;
      } else {
        throw Exception('Failed to exchange code: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error exchanging code for key: $e');
    }
  }

  /// Make a chat completion request to OpenRouter
  Future<Map<String, dynamic>> chatCompletion({
    required String model,
    required List<Map<String, dynamic>> messages,
    bool stream = false,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      throw Exception('Not authenticated. Please log in first.');
    }

    try {
      final response = await _dio.post(
        'https://openrouter.ai/api/v1/chat/completions',
        data: {'model': model, 'messages': messages, 'stream': stream},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'HTTP-Referer':
                'https://github.com/benkaiser/joey-mcp-client-flutter',
            'X-Title': 'Joey MCP Client',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      } else {
        throw Exception('Chat completion failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error making chat completion request: $e');
    }
  }

  /// Make a streaming chat completion request to OpenRouter
  Stream<String> chatCompletionStream({
    required String model,
    required List<Map<String, dynamic>> messages,
  }) async* {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      throw Exception('Not authenticated. Please log in first.');
    }

    try {
      final response = await _dio.post<ResponseBody>(
        'https://openrouter.ai/api/v1/chat/completions',
        data: {'model': model, 'messages': messages, 'stream': true},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'HTTP-Referer':
                'https://github.com/benkaiser/joey-mcp-client-flutter',
            'X-Title': 'Joey MCP Client',
          },
          responseType: ResponseType.stream,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final stream = response.data!.stream;
        String buffer = '';

        await for (final chunk in stream) {
          final text = utf8.decode(chunk);
          buffer += text;

          // Process complete lines
          final lines = buffer.split('\n');
          buffer = lines.last; // Keep incomplete line in buffer

          for (int i = 0; i < lines.length - 1; i++) {
            final line = lines[i].trim();
            if (line.isEmpty || !line.startsWith('data: ')) continue;

            final data = line.substring(6); // Remove 'data: ' prefix
            if (data == '[DONE]') continue;

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final choices = json['choices'] as List<dynamic>?;
              if (choices != null && choices.isNotEmpty) {
                final delta = choices[0]['delta'] as Map<String, dynamic>?;
                final content = delta?['content'] as String?;
                if (content != null && content.isNotEmpty) {
                  yield content;
                }
              }
            } catch (e) {
              // Skip invalid JSON lines
              continue;
            }
          }
        }
      } else {
        throw Exception('Chat completion failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error making streaming chat completion request: $e');
    }
  }

  /// Fetch available models from OpenRouter
  Future<List<Map<String, dynamic>>> getModels() async {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      throw Exception('Not authenticated. Please log in first.');
    }

    try {
      final response = await _dio.get(
        'https://openrouter.ai/api/v1/models',
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data['data'] as List<dynamic>;
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to fetch models: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching models: $e');
    }
  }
}
