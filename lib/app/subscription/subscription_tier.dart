/// Subscription tiers for the app's freemium model.
enum SubscriptionTier {
  /// Free tier with limited features:
  /// - 1 book in library
  /// - 3 voices (one per engine)
  /// - Real-time synthesis only
  free,

  /// Premium tier with all features:
  /// - Unlimited books
  /// - All voices (20+)
  /// - Pre-synthesis
  /// - Unlimited storage
  /// - Priority processing
  premium,
}

/// Subscription status information.
class SubscriptionStatus {
  final SubscriptionTier tier;
  final DateTime? expirationDate;
  final bool isInTrial;
  final int trialDaysRemaining;

  const SubscriptionStatus({
    required this.tier,
    this.expirationDate,
    this.isInTrial = false,
    this.trialDaysRemaining = 0,
  });

  bool get isPremium => tier == SubscriptionTier.premium;
  bool get isFree => tier == SubscriptionTier.free;

  /// Default free status.
  static const free = SubscriptionStatus(tier: SubscriptionTier.free);
}

/// Product IDs for Google Play / App Store subscriptions.
class SubscriptionProducts {
  static const String monthlyId = 'premium_monthly';
  static const String annualId = 'premium_annual';
  
  // Entitlement ID for RevenueCat
  static const String premiumEntitlement = 'premium';
}
