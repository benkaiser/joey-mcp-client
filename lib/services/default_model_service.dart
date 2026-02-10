import 'package:shared_preferences/shared_preferences.dart';

class DefaultModelService {
  static const String _defaultModelKey = 'default_model';
  static const String _autoTitleKey = 'auto_title_enabled';
  static const String _systemPromptKey = 'system_prompt';
  static const String _showThinkingKey = 'show_thinking';
  static const String _maxToolCallsKey = 'max_tool_calls';
  static const int _defaultMaxToolCalls = 10;
  static const String _defaultSystemPrompt = 'You are a helpful assistant.\nUse markdown when rendering your responses.\nYou can use mermaid diagrams in your responses when they help illustrate concepts, workflows, or relationships.';

  static Future<String?> getDefaultModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultModelKey);
  }

  static Future<void> setDefaultModel(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultModelKey, modelId);
  }

  static Future<void> clearDefaultModel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultModelKey);
  }

  static Future<bool> getAutoTitleEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoTitleKey) ?? true; // Default to true
  }

  static Future<void> setAutoTitleEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoTitleKey, enabled);
  }

  static Future<String> getSystemPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_systemPromptKey) ?? _defaultSystemPrompt;
  }

  static Future<void> setSystemPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_systemPromptKey, prompt);
  }

  static Future<void> resetSystemPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_systemPromptKey);
  }

  static Future<bool> getShowThinking() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showThinkingKey) ?? true; // Default to true
  }

  static Future<void> setShowThinking(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showThinkingKey, show);
  }

  /// Get max tool calls per message. 0 means unlimited.
  static Future<int> getMaxToolCalls() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_maxToolCallsKey) ?? _defaultMaxToolCalls;
  }

  /// Set max tool calls per message. 0 means unlimited.
  static Future<void> setMaxToolCalls(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxToolCallsKey, value);
  }
}
