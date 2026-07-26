import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:joey_mcp_client_flutter/services/entitlement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const unlimited = 1 << 30;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Non-freemium build (source / pro)', () {
    test('everything is unlocked regardless of purchase', () async {
      final e = EntitlementService(freemiumOverride: false);
      await e.initialize();
      expect(e.isFreemiumBuild, false);
      expect(e.isPremium, true);
      expect(e.historyEnabled, true);
      expect(e.localToolsEnabled, true);
      expect(e.maxMcpServers, unlimited);
      expect(e.maxStoredConversations, unlimited);
    });
  });

  group('Freemium build without purchase', () {
    test('features are gated', () async {
      final e = EntitlementService(freemiumOverride: true);
      await e.initialize();
      expect(e.isFreemiumBuild, true);
      expect(e.isPremium, false);
      expect(e.historyEnabled, false);
      expect(e.localToolsEnabled, false);
      expect(e.maxMcpServers, 1);
      expect(e.maxStoredConversations, 1);
    });
  });

  group('Freemium build with purchase', () {
    test('purchase unlocks all premium features and persists', () async {
      final e = EntitlementService(freemiumOverride: true);
      await e.initialize();
      expect(e.isPremium, false);

      var notified = 0;
      e.addListener(() => notified++);
      await e.setPurchased(true);

      expect(notified, 1);
      expect(e.hasPurchasedPremium, true);
      expect(e.isPremium, true);
      expect(e.historyEnabled, true);
      expect(e.localToolsEnabled, true);
      expect(e.maxMcpServers, unlimited);

      // Persisted: a fresh instance loads the purchase.
      final e2 = EntitlementService(freemiumOverride: true);
      await e2.initialize();
      expect(e2.isPremium, true);
    });

    test('setPurchased(false) re-locks features', () async {
      SharedPreferences.setMockInitialValues({'premium_purchased': true});
      final e = EntitlementService(freemiumOverride: true);
      await e.initialize();
      expect(e.isPremium, true);

      await e.setPurchased(false);
      expect(e.isPremium, false);
      expect(e.maxMcpServers, 1);
    });
  });
}
