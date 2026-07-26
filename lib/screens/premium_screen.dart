import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/entitlement_service.dart';
import '../services/iap_service.dart';

/// Premium upsell / paywall screen for the free build.
class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  static const _features = <(IconData, String, String)>[
    (
      Icons.history,
      'Unlimited conversation history',
      'Keep every chat instead of just the current one.',
    ),
    (
      Icons.dns_outlined,
      'Unlimited MCP servers',
      'Connect as many remote MCP servers per chat as you like.',
    ),
    (
      Icons.phone_iphone,
      'On-device tools',
      'Time, location, contacts, messages, calls, email, calendar, reminders, and more.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Joey Premium')),
      body: Consumer2<EntitlementService, IapService>(
        builder: (context, entitlement, iap, _) {
          if (entitlement.isPremium) {
            return _buildUnlocked(context);
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 8),
              Icon(
                Icons.workspace_premium,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Unlock Joey Premium',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A one-time purchase — yours forever.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              ..._features.map(
                (f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(f.$1, color: theme.colorScheme.primary),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.$2,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              f.$3,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (iap.lastError != null) ...[
                Text(
                  iap.lastError!,
                  style: TextStyle(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed:
                    (!iap.isStoreAvailable ||
                        iap.premiumProduct == null ||
                        iap.isPurchaseInProgress)
                    ? null
                    : () => iap.buyPremium(),
                icon: iap.isPurchaseInProgress
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open),
                label: Text(
                  iap.premiumProduct != null
                      ? 'Upgrade — ${iap.priceString}'
                      : iap.isStoreAvailable
                      ? 'Loading price…'
                      : 'Store unavailable',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: iap.isStoreAvailable
                    ? () => iap.restorePurchases()
                    : null,
                child: const Text('Restore Purchase'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUnlocked(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Premium unlocked',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Thanks for supporting Joey! All premium features are enabled.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
