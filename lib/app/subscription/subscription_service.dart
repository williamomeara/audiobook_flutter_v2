import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'subscription_tier.dart';

/// Service for managing subscriptions.
///
/// This is a skeleton implementation. The actual implementation requires:
/// - RevenueCat SDK integration (purchases_flutter package)
/// - Google Play Console subscription products setup
/// - RevenueCat dashboard configuration
///
/// See: docs/deployment/google_play_release_plan.md for setup instructions.
class SubscriptionService {
  // RevenueCat API key - replace with your actual key
  // Get this from: https://app.revenuecat.com -> Your Project -> API Keys
  static const String _revenueCatApiKey = 'YOUR_REVENUECAT_PUBLIC_API_KEY';

  bool _initialized = false;
  SubscriptionStatus _status = SubscriptionStatus.free;

  /// Initialize the subscription service.
  ///
  /// Call this early in app startup (main.dart).
  Future<void> initialize() async {
    if (_initialized) return;

    // TODO: Uncomment when purchases_flutter is added to pubspec.yaml
    // await Purchases.configure(
    //   PurchasesConfiguration(_revenueCatApiKey)
    //     ..appUserID = null // Anonymous user (no account required)
    // );

    _initialized = true;
    await refreshStatus();
  }

  /// Get the current subscription status.
  SubscriptionStatus get status => _status;

  /// Check if user has premium access.
  bool get isPremium => _status.isPremium;

  /// Refresh subscription status from RevenueCat.
  Future<void> refreshStatus() async {
    // TODO: Uncomment when purchases_flutter is added
    // try {
    //   final customerInfo = await Purchases.getCustomerInfo();
    //   final hasPremium = customerInfo.entitlements.active
    //       .containsKey(SubscriptionProducts.premiumEntitlement);
    //
    //   if (hasPremium) {
    //     final entitlement = customerInfo.entitlements.active[
    //         SubscriptionProducts.premiumEntitlement]!;
    //     _status = SubscriptionStatus(
    //       tier: SubscriptionTier.premium,
    //       expirationDate: entitlement.expirationDate != null
    //           ? DateTime.parse(entitlement.expirationDate!)
    //           : null,
    //     );
    //   } else {
    //     _status = SubscriptionStatus.free;
    //   }
    // } catch (e) {
    //   // On error, assume free tier
    //   _status = SubscriptionStatus.free;
    // }

    // Placeholder: Always free until RevenueCat is integrated
    _status = SubscriptionStatus.free;
  }

  /// Purchase monthly subscription.
  Future<bool> purchaseMonthly() async {
    // TODO: Uncomment when purchases_flutter is added
    // try {
    //   final offerings = await Purchases.getOfferings();
    //   final package = offerings.current?.monthly;
    //   if (package != null) {
    //     await Purchases.purchasePackage(package);
    //     await refreshStatus();
    //     return _status.isPremium;
    //   }
    // } catch (e) {
    //   // Purchase failed or cancelled
    // }
    return false;
  }

  /// Purchase annual subscription.
  Future<bool> purchaseAnnual() async {
    // TODO: Uncomment when purchases_flutter is added
    // try {
    //   final offerings = await Purchases.getOfferings();
    //   final package = offerings.current?.annual;
    //   if (package != null) {
    //     await Purchases.purchasePackage(package);
    //     await refreshStatus();
    //     return _status.isPremium;
    //   }
    // } catch (e) {
    //   // Purchase failed or cancelled
    // }
    return false;
  }

  /// Restore previous purchases.
  Future<bool> restorePurchases() async {
    // TODO: Uncomment when purchases_flutter is added
    // try {
    //   await Purchases.restorePurchases();
    //   await refreshStatus();
    //   return _status.isPremium;
    // } catch (e) {
    //   // Restore failed
    // }
    return false;
  }

  /// Get available subscription offerings.
  Future<SubscriptionOfferings?> getOfferings() async {
    // TODO: Uncomment when purchases_flutter is added
    // try {
    //   final offerings = await Purchases.getOfferings();
    //   final current = offerings.current;
    //   if (current == null) return null;
    //
    //   return SubscriptionOfferings(
    //     monthlyPrice: current.monthly?.storeProduct.priceString,
    //     annualPrice: current.annual?.storeProduct.priceString,
    //   );
    // } catch (e) {
    //   return null;
    // }
    
    // Placeholder prices
    return const SubscriptionOfferings(
      monthlyPrice: '\$5.00/month',
      annualPrice: '\$50.00/year',
    );
  }
}

/// Available subscription offerings with prices.
class SubscriptionOfferings {
  final String? monthlyPrice;
  final String? annualPrice;

  const SubscriptionOfferings({
    this.monthlyPrice,
    this.annualPrice,
  });
}

/// Provider for subscription service.
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService();
});

/// Provider for current subscription status.
final subscriptionStatusProvider = Provider<SubscriptionStatus>((ref) {
  return ref.watch(subscriptionServiceProvider).status;
});
