# OpenRouter OAuth Integration

## Overview
This implementation provides secure OAuth 2.0 PKCE authentication with OpenRouter, allowing users to connect their OpenRouter account to use AI models in the Joey MCP Client.

## Features

### 1. **Secure PKCE Flow**
- Uses SHA-256 code challenge method for maximum security
- Generates cryptographically secure random code verifiers (128 characters)
- Implements proper state management during OAuth flow

### 2. **Custom URL Scheme**
- Uses `joey://auth` as the callback URL
- Configured for both iOS and Android platforms
- Seamless deep link handling with app_links package

### 3. **Onboarding Flow**
- Users must authenticate before creating conversations
- Beautiful onboarding screen with clear instructions
- Error handling and feedback for failed authentication

### 4. **Persistent Authentication**
- API key stored securely in SharedPreferences
- Automatic authentication check on app launch
- Logout functionality to clear credentials

## Implementation Details

### Files Created/Modified

#### New Files:
1. **lib/services/openrouter_service.dart**
   - PKCE code generation and verification
   - OAuth token exchange
   - API key storage and retrieval
   - Chat completion API wrapper

2. **lib/screens/auth_screen.dart**
   - Beautiful onboarding UI
   - Deep link handling for OAuth callback
   - Error states and loading indicators
   - User-friendly messaging

#### Modified Files:
1. **lib/main.dart**
   - Added authentication check on startup
   - Routes to auth screen if not authenticated
   - Named routes for navigation

2. **lib/screens/conversation_list_screen.dart**
   - Added logout button in app bar
   - Logout confirmation dialog

3. **android/app/src/main/AndroidManifest.xml**
   - Deep link intent filter for `joey://auth`

4. **ios/Runner/Info.plist**
   - URL scheme configuration for `joey://`

5. **pubspec.yaml**
   - Added dependencies:
     - `app_links`: Deep link handling
     - `crypto`: SHA-256 hashing
     - `shared_preferences`: Secure storage
     - `url_launcher`: Open browser for OAuth

## Usage Flow

1. **First Launch**
   - App checks authentication status
   - If not authenticated, shows auth screen
   - User clicks "Connect with OpenRouter"

2. **OAuth Flow**
   - App generates code verifier and challenge
   - Opens OpenRouter in browser with callback URL
   - User logs in and authorizes the app
   - OpenRouter redirects to `joey://auth?code=...`

3. **Callback Handling**
   - App receives deep link
   - Exchanges authorization code for API key
   - Stores API key in SharedPreferences
   - Navigates to conversation list

4. **Authenticated State**
   - User can create and manage conversations
   - API key used for all OpenRouter API calls
   - Logout option available in app bar

## Security Considerations

- **Code Verifier**: 128 characters, cryptographically secure random
- **Code Challenge**: SHA-256 hash, base64url encoded
- **API Key Storage**: Stored in SharedPreferences (encrypted on iOS)
- **No Credential Exposure**: API key never logged or displayed

## Testing

### iOS Testing:
```bash
flutter run -d iphone
```

### Android Testing:
```bash
flutter run -d android
```

### Deep Link Testing:
```bash
# iOS Simulator
xcrun simctl openurl booted "joey://auth?code=test_code"

# Android
adb shell am start -W -a android.intent.action.VIEW -d "joey://auth?code=test_code" com.example.joey_mcp_client_flutter
```

## API Reference

### OpenRouterService

```dart
// Check authentication status
await openRouterService.isAuthenticated()

// Get stored API key
await openRouterService.getApiKey()

// Start OAuth flow (returns auth URL)
String authUrl = openRouterService.startAuthFlow()

// Exchange code for API key
await openRouterService.exchangeCodeForKey(code)

// Logout (clear API key)
await openRouterService.logout()

// Make chat completion request
await openRouterService.chatCompletion(
  model: 'openai/gpt-4',
  messages: [
    {'role': 'user', 'content': 'Hello!'}
  ],
)
```

## Future Enhancements

- [ ] Implement token refresh mechanism
- [ ] Add biometric authentication for app access
- [ ] Support multiple account switching
- [ ] Cache model list from OpenRouter
- [ ] Add usage tracking and limits display
- [ ] Implement streaming responses

## Troubleshooting

### Deep Links Not Working (iOS)
- Ensure URL scheme is properly configured in Info.plist
- Check that app is built with correct bundle identifier
- Clean build folder: `flutter clean && flutter pub get`

### Deep Links Not Working (Android)
- Verify intent filter in AndroidManifest.xml
- Check package name matches
- Use `adb logcat` to debug deep link reception

### OAuth Fails
- Check internet connection
- Verify OpenRouter service is accessible
- Ensure code verifier is properly stored during flow
- Check for error messages in auth screen

## Resources

- [OpenRouter OAuth Documentation](https://openrouter.ai/docs/oauth)
- [Flutter Deep Linking](https://docs.flutter.dev/ui/navigation/deep-linking)
- [app_links Package](https://pub.dev/packages/app_links)
- [OAuth 2.0 PKCE](https://oauth.net/2/pkce/)
