import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'entitlement_service.dart';

/// Wraps the platform in-app purchase flow for the single non-consumable
/// premium product. Updates [EntitlementService] when a purchase completes or
/// is restored. Only does anything in a freemium build.
class IapService extends ChangeNotifier {
  final EntitlementService _entitlement;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool _available = false;
  bool _loading = false;
  bool _purchaseInProgress = false;
  ProductDetails? _premiumProduct;
  String? _lastError;

  IapService(this._entitlement);

  bool get isStoreAvailable => _available;
  bool get isLoading => _loading;
  bool get isPurchaseInProgress => _purchaseInProgress;
  ProductDetails? get premiumProduct => _premiumProduct;

  /// Localized price string from the store (e.g. "$4.99"), if loaded.
  String? get priceString => _premiumProduct?.price;
  String? get lastError => _lastError;

  Future<void> initialize() async {
    if (!kFreemiumEnabled) return;
    _available = await _iap.isAvailable();
    if (!_available) {
      notifyListeners();
      return;
    }
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object error) {
        _lastError = error.toString();
        notifyListeners();
      },
    );
    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    _loading = true;
    notifyListeners();
    try {
      final response = await _iap.queryProductDetails({
        EntitlementService.premiumProductId,
      });
      if (response.productDetails.isNotEmpty) {
        _premiumProduct = response.productDetails.first;
      } else {
        _lastError = 'Premium product not found in the store.';
      }
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Start the purchase flow for the premium product.
  Future<void> buyPremium() async {
    if (_premiumProduct == null) {
      _lastError = 'Premium product is not available yet. Please try again.';
      notifyListeners();
      return;
    }
    _purchaseInProgress = true;
    _lastError = null;
    notifyListeners();
    final param = PurchaseParam(productDetails: _premiumProduct!);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Restore a previously-purchased premium unlock.
  Future<void> restorePurchases() async {
    _lastError = null;
    await _iap.restorePurchases();
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != EntitlementService.premiumProductId) {
        continue;
      }
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _entitlement.setPurchased(true);
          _purchaseInProgress = false;
          notifyListeners();
          break;
        case PurchaseStatus.error:
          _lastError = purchase.error?.message ?? 'Purchase failed.';
          _purchaseInProgress = false;
          notifyListeners();
          break;
        case PurchaseStatus.canceled:
          _purchaseInProgress = false;
          notifyListeners();
          break;
        case PurchaseStatus.pending:
          break;
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
