import 'package:shared_preferences/shared_preferences.dart';

class DefaultModelService {
  static const String _defaultModelKey = 'default_model';
  static const String _autoTitleKey = 'auto_title_enabled';

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
}
