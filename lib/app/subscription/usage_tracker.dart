import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'subscription_tier.dart';

/// Tracks user activity for freemium enforcement.
///
/// Tracks:
/// - Number of books in library
/// - Voices used
/// - First app launch date (for trial calculation)
class UsageTracker {
  static const String _firstLaunchKey = 'first_launch_date';
  static const String _usedVoicesKey = 'used_voices';

  final SharedPreferences _prefs;

  UsageTracker(this._prefs);

  /// Get the date of first app launch.
  DateTime? get firstLaunchDate {
    final timestamp = _prefs.getInt(_firstLaunchKey);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Record the first launch if not already recorded.
  Future<void> recordFirstLaunch() async {
    if (firstLaunchDate != null) return;
    await _prefs.setInt(
      _firstLaunchKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Calculate days remaining in free trial (90 days from first launch).
  int get trialDaysRemaining {
    final first = firstLaunchDate;
    if (first == null) return 90; // Trial not started yet
    
    final trialEnd = first.add(const Duration(days: 90));
    final remaining = trialEnd.difference(DateTime.now()).inDays;
    return remaining > 0 ? remaining : 0;
  }

  /// Check if user is still in trial period.
  bool get isInTrialPeriod => trialDaysRemaining > 0;

  /// Get list of voice IDs the user has used (for free tier limit).
  Set<String> get usedVoices {
    final list = _prefs.getStringList(_usedVoicesKey) ?? [];
    return list.toSet();
  }

  /// Record that a voice was used.
  Future<void> recordVoiceUsed(String voiceId) async {
    final voices = usedVoices.toList();
    if (!voices.contains(voiceId)) {
      voices.add(voiceId);
      await _prefs.setStringList(_usedVoicesKey, voices);
    }
  }

  /// Check if user can use a voice (free tier: max 3 unique voices).
  bool canUseVoice(String voiceId, SubscriptionTier tier) {
    if (tier == SubscriptionTier.premium) return true;
    
    final used = usedVoices;
    // Already used this voice, or haven't hit limit yet
    return used.contains(voiceId) || used.length < 3;
  }

  /// Check if user can add another book (free tier: max 1 book).
  bool canAddBook(int currentBookCount, SubscriptionTier tier) {
    if (tier == SubscriptionTier.premium) return true;
    return currentBookCount < 1;
  }
}

/// Provider for usage tracker.
final usageTrackerProvider = Provider<UsageTracker>((ref) {
  throw UnimplementedError(
    'usageTrackerProvider must be overridden with SharedPreferences',
  );
});
