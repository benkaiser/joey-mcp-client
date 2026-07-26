import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/conversation_provider.dart';
import '../services/entitlement_service.dart';
import '../screens/premium_screen.dart';

/// Helpers for showing premium upsell UI from anywhere in the free build.
class PremiumUpsell {
  PremiumUpsell._();

  /// Gate creating a new conversation on the free tier. Returns true if the
  /// caller may proceed to create a new conversation.
  ///
  /// Premium (and non-freemium) builds always proceed. On the free tier, if a
  /// conversation already exists the user is warned it will be discarded; if
  /// they proceed, existing conversations are deleted first so only the new
  /// one remains.
  static Future<bool> gateNewConversation(BuildContext context) async {
    final entitlement = context.read<EntitlementService>();
    if (entitlement.isPremium) return true;
    final provider = context.read<ConversationProvider>();
    if (provider.conversations.isEmpty) return true;
    final proceed = await confirmNewChatWillDiscard(context);
    if (!proceed) return false;
    await provider.deleteAllConversations();
    return true;
  }

  /// Push the full paywall screen.
  static Future<void> openPaywall(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
  }

  /// Generic "this is a premium feature" dialog with Upgrade / Not now.
  static Future<void> showFeatureLocked(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final upgrade = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.workspace_premium, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
    if (upgrade == true && context.mounted) {
      await openPaywall(context);
    }
  }

  /// Confirmation shown before starting a new chat discards the current one
  /// (free tier). Returns true if the user chose to proceed (discard current).
  static Future<bool> confirmNewChatWillDiscard(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new chat?'),
        content: const Text(
          'The free version keeps only your current conversation. Starting a '
          'new chat will remove the current one. Upgrade to Premium to keep '
          'your full history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'upgrade'),
            child: const Text('Upgrade'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'proceed'),
            child: const Text('Start new'),
          ),
        ],
      ),
    );
    if (result == 'upgrade' && context.mounted) {
      await openPaywall(context);
      return false;
    }
    return result == 'proceed';
  }
}
