import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'dart:math';

/// Exception thrown when authentication fails (e.g., expired token)
class OpenRouterAuthException implements Exception {
  final String message;
  OpenRouterAuthException(this.message);

  @override
  String toString() => 'OpenRouterAuthException: $message';
}

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
          print(
            'OpenRouter: exchangeCodeForKey failed - no key in response: ${response.data}',
          );
          throw Exception('Invalid response: API key not found');
        }

        // Store the API key
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_apiKeyKey, key);

        // Clear the code verifier
        _codeVerifier = null;

        return key;
      } else {
        print(
          'OpenRouter: exchangeCodeForKey failed with status ${response.statusCode}: ${response.data}',
        );
        throw Exception('Failed to exchange code: ${response.statusCode}');
      }
    } on DioException catch (e) {
      print('OpenRouter: exchangeCodeForKey DioException:');
      print('  Status: ${e.response?.statusCode}');
      print('  Response: ${e.response?.data}');
      print('  Message: ${e.message}');
      throw Exception('Error exchanging code for key: ${e.message}');
    } catch (e) {
      print('OpenRouter: exchangeCodeForKey unexpected error: $e');
      throw Exception('Error exchanging code for key: $e');
    }
  }

  /// Make a chat completion request to OpenRouter
  Future<Map<String, dynamic>> chatCompletion({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    bool stream = false,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      throw Exception('Not authenticated. Please log in first.');
    }

    try {
      final requestData = {
        'model': model,
        'messages': messages,
        'stream': stream,
      };

      if (tools != null && tools.isNotEmpty) {
        requestData['tools'] = tools;
      }

      final response = await _dio.post(
        'https://openrouter.ai/api/v1/chat/completions',
        data: requestData,
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
        print(
          'OpenRouter: chatCompletion failed with status ${response.statusCode}: ${response.data}',
        );
        throw Exception('Chat completion failed: ${response.statusCode}');
      }
    } on DioException catch (e) {
      print('OpenRouter: chatCompletion DioException:');
      print('  Status: ${e.response?.statusCode}');
      print('  Response: ${e.response?.data}');
      print('  Message: ${e.message}');
      if (e.response?.statusCode == 401) {
        // Token expired or invalid - clear it and prompt re-auth
        print('OpenRouter: 401 Unauthorized - clearing token');
        await logout();
        throw OpenRouterAuthException(
          'Authentication expired. Please log in again.',
        );
      }
      throw Exception('Error making chat completion request: ${e.message}');
    } catch (e) {
      print('OpenRouter: chatCompletion unexpected error: $e');
      throw Exception('Error making chat completion request: $e');
    }
  }

  /// Make a streaming chat completion request to OpenRouter
  Stream<String> chatCompletionStream({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
  }) async* {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      throw Exception('Not authenticated. Please log in first.');
    }

    try {
      final requestData = {
        'model': model,
        'messages': messages,
        'stream': true,
      };

      if (tools != null && tools.isNotEmpty) {
        requestData['tools'] = tools;
      }

      final response = await _dio.post<ResponseBody>(
        'https://openrouter.ai/api/v1/chat/completions',
        data: requestData,
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
        int chunkCount = 0;

        await for (final chunk in stream) {
          chunkCount++;
          final text = utf8.decode(chunk);
          print(
            'OpenRouter: Received chunk #$chunkCount: ${text.substring(0, text.length > 100 ? 100 : text.length)}...',
          );
          buffer += text;

          // Process complete lines
          final lines = buffer.split('\n');
          buffer = lines.last; // Keep incomplete line in buffer

          for (int i = 0; i < lines.length - 1; i++) {
            final line = lines[i].trim();
            if (line.isEmpty || !line.startsWith('data: ')) continue;

            final data = line.substring(6); // Remove 'data: ' prefix
            if (data == '[DONE]') {
              print('OpenRouter: Stream completed with [DONE]');
              continue;
            }

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;

              // Check for errors in the chunk
              final error = json['error'];
              if (error != null) {
                print('OpenRouter: ERROR in stream chunk:');
                print('  Full error object: ${jsonEncode(error)}');
                throw Exception('Provider error: ${jsonEncode(error)}');
              }

              final choices = json['choices'] as List<dynamic>?;
              if (choices != null && choices.isNotEmpty) {
                final delta = choices[0]['delta'] as Map<String, dynamic>?;

                // Check for reasoning_details array (OpenRouter's structured format)
                final reasoningDetails =
                    delta?['reasoning_details'] as List<dynamic>?;
                if (reasoningDetails != null && reasoningDetails.isNotEmpty) {
                  for (final detail in reasoningDetails) {
                    final detailMap = detail as Map<String, dynamic>;
                    final type = detailMap['type'] as String?;

                    // Extract text from different reasoning types
                    String? reasoningText;
                    if (type == 'reasoning.text') {
                      reasoningText = detailMap['text'] as String?;
                    } else if (type == 'reasoning.summary') {
                      reasoningText = detailMap['summary'] as String?;
                    }

                    if (reasoningText != null && reasoningText.isNotEmpty) {
                      print(
                        'OpenRouter: Yielding reasoning ($type): "$reasoningText"',
                      );
                      yield 'REASONING:$reasoningText';
                    }
                  }
                }

                // Also check for regular content
                final content = delta?['content'] as String?;
                if (content != null && content.isNotEmpty) {
                  print('OpenRouter: Yielding content: "$content"');
                  yield content;
                }

                // Log the full delta for debugging
                if (delta != null && delta.isNotEmpty) {
                  print('OpenRouter: Full delta keys: ${delta.keys.toList()}');
                }
              }
            } catch (e) {
              print('OpenRouter: Failed to parse JSON line: $line');
              // Skip invalid JSON lines
              continue;
            }
          }
        }
        print('OpenRouter: Stream ended after $chunkCount chunks');
      } else {
        print(
          'OpenRouter: chatCompletionStream failed with status ${response.statusCode}',
        );
        throw Exception('Chat completion failed: ${response.statusCode}');
      }
    } on DioException catch (e) {
      print('OpenRouter: chatCompletionStream DioException:');
      print('  Status: ${e.response?.statusCode}');
      print('  Response type: ${e.response?.data.runtimeType}');

      // Try to read the response body if it's a stream
      if (e.response?.data is ResponseBody) {
        try {
          final responseBody = e.response!.data as ResponseBody;
          final chunks = await responseBody.stream.toList();
          final bytes = chunks.expand((chunk) => chunk).toList();
          final errorText = utf8.decode(bytes);
          print('  Response body: $errorText');
        } catch (readError) {
          print('  Failed to read response body: $readError');
        }
      } else {
        print('  Response data: ${e.response?.data}');
      }

      print('  Message: ${e.message}');
      print('  Request data: ${e.requestOptions.data}');

      if (e.response?.statusCode == 401) {
        // Token expired or invalid - clear it and prompt re-auth
        print('OpenRouter: 401 Unauthorized - clearing token');
        await logout();
        throw OpenRouterAuthException(
          'Authentication expired. Please log in again.',
        );
      }
      throw Exception(
        'Error making streaming chat completion request: ${e.message}',
      );
    } catch (e) {
      print('OpenRouter: chatCompletionStream unexpected error: $e');
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
        print(
          'OpenRouter: getModels failed with status ${response.statusCode}: ${response.data}',
        );
        throw Exception('Failed to fetch models: ${response.statusCode}');
      }
    } on DioException catch (e) {
      print('OpenRouter: getModels DioException:');
      print('  Status: ${e.response?.statusCode}');
      print('  Response: ${e.response?.data}');
      print('  Message: ${e.message}');
      if (e.response?.statusCode == 401) {
        // Token expired or invalid - clear it and prompt re-auth
        print('OpenRouter: 401 Unauthorized - clearing token');
        await logout();
        throw OpenRouterAuthException(
          'Authentication expired. Please log in again.',
        );
      }
      throw Exception('Error fetching models: ${e.message}');
    } catch (e) {
      print('OpenRouter: getModels unexpected error: $e');
      throw Exception('Error fetching models: $e');
    }
  }
}
