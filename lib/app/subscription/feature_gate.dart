import 'subscription_tier.dart';
import 'usage_tracker.dart';

/// Features that can be gated behind premium subscription.
enum Feature {
  /// Add multiple books to library (free: 1 book max).
  multipleBooks,

  /// Use premium voices beyond the 3 free voices.
  premiumVoices,

  /// Pre-synthesize chapters for instant playback.
  preSynthesis,

  /// Unlimited cache storage (free: limited).
  unlimitedStorage,

  /// Priority processing in synthesis queue.
  priorityProcessing,
}

/// Gates features based on subscription tier and usage.
class FeatureGate {
  final UsageTracker _usageTracker;
  final SubscriptionStatus Function() _getSubscriptionStatus;

  FeatureGate({
    required UsageTracker usageTracker,
    required SubscriptionStatus Function() getSubscriptionStatus,
  })  : _usageTracker = usageTracker,
        _getSubscriptionStatus = getSubscriptionStatus;

  /// Get the current subscription status.
  SubscriptionStatus get subscriptionStatus => _getSubscriptionStatus();

  /// Check if a feature is available for the current user.
  bool canUseFeature(Feature feature) {
    final status = subscriptionStatus;

    // Premium users can use all features
    if (status.isPremium) return true;

    // Free tier users during trial get premium features
    if (status.isFree && _usageTracker.isInTrialPeriod) return true;

    // Free tier restrictions after trial
    switch (feature) {
      case Feature.multipleBooks:
        // Handled separately via canAddBook
        return false;
      case Feature.premiumVoices:
        // Handled separately via canUseVoice
        return false;
      case Feature.preSynthesis:
        return false; // Premium only
      case Feature.unlimitedStorage:
        return false; // Premium only
      case Feature.priorityProcessing:
        return false; // Premium only
    }
  }

  /// Check if user can add another book.
  bool canAddBook(int currentBookCount) {
    final status = subscriptionStatus;
    
    if (status.isPremium) return true;
    if (_usageTracker.isInTrialPeriod) return true;
    
    return _usageTracker.canAddBook(currentBookCount, status.tier);
  }

  /// Check if user can use a specific voice.
  bool canUseVoice(String voiceId) {
    final status = subscriptionStatus;
    
    if (status.isPremium) return true;
    if (_usageTracker.isInTrialPeriod) return true;
    
    return _usageTracker.canUseVoice(voiceId, status.tier);
  }

  /// Get the reason why a feature is restricted.
  String getRestrictionReason(Feature feature) {
    switch (feature) {
      case Feature.multipleBooks:
        return 'Free tier allows only 1 book. Upgrade to Premium for unlimited books.';
      case Feature.premiumVoices:
        return 'Free tier includes 3 voices. Upgrade to Premium for 20+ voices.';
      case Feature.preSynthesis:
        return 'Pre-synthesis is a Premium feature. Upgrade for instant playback.';
      case Feature.unlimitedStorage:
        return 'Unlimited storage is a Premium feature.';
      case Feature.priorityProcessing:
        return 'Priority processing is a Premium feature.';
    }
  }
}
