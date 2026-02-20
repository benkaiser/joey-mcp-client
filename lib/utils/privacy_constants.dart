/// Shared constants for privacy-related URLs and preferences keys.
class PrivacyConstants {
  PrivacyConstants._();

  /// URL to the privacy policy hosted on GitHub.
  static const String privacyPolicyUrl =
      'https://github.com/benkaiser/joey-mcp-client-flutter/blob/master/docs/PRIVACY_POLICY.md';

  /// SharedPreferences key for OpenRouter data sharing consent.
  static const String privacyConsentKey = 'privacy_consent_given';

  /// SharedPreferences key for MCP server data sharing consent.
  static const String mcpDataConsentKey = 'mcp_data_consent_given';
}
