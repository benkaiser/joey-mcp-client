import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Compile-time freemium flag.
///
/// Only official "Joey Free" store release builds pass
/// `--dart-define=JOEY_FREEMIUM=true`. Anyone building from source, and the
/// full "pro" flavor, leave this at its default of `false`, which unlocks
/// every feature. This keeps the open-source build fully functional while
/// still allowing the published free build to gate premium features behind an
/// in-app purchase.
const bool kFreemiumEnabled = bool.fromEnvironment(
  'JOEY_FREEMIUM',
  defaultValue: false,
);

/// Effectively-unlimited sentinel for premium limits.
const int _unlimited = 1 << 30;

/// Tracks whether the current build/user has access to premium features.
///
/// In a non-freemium build ([kFreemiumEnabled] == false) everything is
/// unlocked. In a freemium build, premium features unlock once the user has
/// purchased (or restored) the non-consumable premium product.
class EntitlementService extends ChangeNotifier {
  static const String premiumProductId = 'com.kaiserapps.joey.free.premium';
  static const String _premiumPurchasedKey = 'premium_purchased';

  /// Whether this build gates features behind a purchase. Defaults to the
  /// compile-time [kFreemiumEnabled]; overridable for tests.
  final bool _freemium;

  bool _hasPurchasedPremium = false;

  EntitlementService({bool? freemiumOverride})
    : _freemium = freemiumOverride ?? kFreemiumEnabled;

  /// Whether this build gates features behind a purchase at all.
  bool get isFreemiumBuild => _freemium;

  /// True when premium features are available (always true for source/pro
  /// builds; requires a purchase for freemium builds).
  bool get isPremium => !_freemium || _hasPurchasedPremium;

  /// Whether the user has actually purchased premium (independent of build
  /// type). Used by the paywall/settings UI.
  bool get hasPurchasedPremium => _hasPurchasedPremium;

  /// Conversation history beyond the single current conversation.
  bool get historyEnabled => isPremium;

  /// On-device local tools (time, location, contacts, etc.).
  bool get localToolsEnabled => isPremium;

  /// Maximum number of MCP servers that can be connected per conversation.
  int get maxMcpServers => isPremium ? _unlimited : 1;

  /// Maximum number of conversations retained on the device.
  int get maxStoredConversations => isPremium ? _unlimited : 1;

  /// Load persisted purchase state. No-op for non-freemium builds.
  Future<void> initialize() async {
    if (!_freemium) return;
    final prefs = await SharedPreferences.getInstance();
    _hasPurchasedPremium = prefs.getBool(_premiumPurchasedKey) ?? false;
    notifyListeners();
  }

  /// Update and persist the premium purchase state.
  Future<void> setPurchased(bool purchased) async {
    if (_hasPurchasedPremium == purchased) return;
    _hasPurchasedPremium = purchased;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_premiumPurchasedKey, purchased);
    notifyListeners();
  }
}
