import 'device_capabilities.dart';
import 'model_catalog.dart';
import 'rtf_monitor.dart';

/// Type of performance suggestion.
///
/// These are SUGGESTIONS shown to the user, never forced requirements.
/// Users can always ignore suggestions and play immediately.
enum RecommendationType {
  /// Suggest switching to a faster voice/model.
  switchModel,

  /// Suggest reducing playback speed for smoother experience.
  reduceSpeed,

  /// Offer pre-synthesis as an optional convenience.
  /// This is NEVER required - user can always play immediately.
  offerPreSynthesis,

  /// Offer waiting for buffer to build as an option.
  /// This is NEVER required - user can always play immediately.
  offerBuffering,

  /// No suggestion needed - performance is fine.
  none,
}

/// A suggestion for improving synthesis performance.
///
/// **Important: These are suggestions, not requirements.**
/// Users can ALWAYS ignore suggestions and play immediately.
/// The UI should present these as options, not gates.
class PerformanceRecommendation {
  /// Type of suggestion.
  final RecommendationType type;

  /// Human-readable reason for the suggestion.
  final String reason;

  /// Faster alternative voices (for switchModel).
  final List<VoiceInfo> alternatives;

  /// Current measured RTF.
  final double currentRTF;

  /// Maximum sustainable playback speed.
  final double maxSustainableSpeed;

  /// Whether this suggestion is strongly encouraged.
  /// Even when true, user can still dismiss and play immediately.
  final bool isStrongSuggestion;

  const PerformanceRecommendation({
    required this.type,
    required this.reason,
    this.alternatives = const [],
    required this.currentRTF,
    required this.maxSustainableSpeed,
    this.isStrongSuggestion = false,
  });

  /// No suggestion needed.
  static const none = PerformanceRecommendation(
    type: RecommendationType.none,
    reason: 'Performance is adequate',
    currentRTF: 0,
    maxSustainableSpeed: 3.0,
  );

  /// User can ALWAYS choose to play immediately regardless of suggestion.
  bool get canPlayImmediately => true;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'reason': reason,
        'alternativeCount': alternatives.length,
        'currentRTF': currentRTF.toStringAsFixed(3),
        'maxSustainableSpeed': maxSustainableSpeed.toStringAsFixed(1),
        'isStrongSuggestion': isStrongSuggestion,
        'canPlayImmediately': canPlayImmediately,
      };
}

/// Advises on synthesis performance based on RTF monitoring.
///
/// Checks RTF statistics and makes recommendations when:
/// - Current voice is too slow for device
/// - Playback speed exceeds sustainable rate
/// - Device is struggling despite max concurrency
///
/// ## When to Show Recommendations
///
/// - Only after 10+ samples (reliable data)
/// - Only when already at max concurrency (can't scale up)
/// - Only if user hasn't dismissed in current session
///
/// ## Example
/// ```dart
/// final advisor = PerformanceAdvisor(
///   rtfMonitor: monitor,
///   deviceCapabilities: capabilities,
///   currentEngineType: 'kokoro',
///   currentVoiceId: 'kokoro_af_bella',
/// );
///
/// final recommendation = advisor.checkPerformance(
///   playbackRate: 1.5,
///   currentConcurrency: 4,
/// );
///
/// if (recommendation.type != RecommendationType.none) {
///   showPerformanceDialog(recommendation);
/// }
/// ```
class PerformanceAdvisor {
  final RTFMonitor rtfMonitor;
  final DeviceCapabilities deviceCapabilities;
  final String currentEngineType;
  final String currentVoiceId;

  PerformanceAdvisor({
    required this.rtfMonitor,
    required this.deviceCapabilities,
    required this.currentEngineType,
    required this.currentVoiceId,
  });

  /// Check if performance recommendation is needed.
  ///
  /// Returns a recommendation if:
  /// - Have enough samples (10+)
  /// - Already at max concurrency
  /// - P95 RTF indicates unsustainable performance
  PerformanceRecommendation checkPerformance({
    required double playbackRate,
    required int currentConcurrency,
  }) {
    // Need enough data for reliable assessment
    if (!rtfMonitor.hasReliableData) {
      return PerformanceRecommendation.none;
    }

    final stats = rtfMonitor.statistics;

    // Check if we can maintain current playback rate
    if (stats.canMaintainRealtime(playbackRate)) {
      return PerformanceRecommendation.none;
    }

    // Check if we still have room to scale concurrency
    final maxConcurrency = deviceCapabilities.recommendedMaxConcurrency;
    if (currentConcurrency < maxConcurrency) {
      // Let DemandController handle scaling
      return PerformanceRecommendation.none;
    }

    // We're at max concurrency and still struggling
    final isStrongSuggestion = stats.p95 > 1.2;

    // Check for faster alternatives
    final alternatives = ModelCatalog.getFasterAlternatives(
      currentEngineType,
      currentVoiceId,
    );

    if (alternatives.isNotEmpty) {
      return PerformanceRecommendation(
        type: RecommendationType.switchModel,
        reason: _buildSwitchModelReason(stats, playbackRate),
        alternatives: alternatives,
        currentRTF: stats.p95,
        maxSustainableSpeed: stats.maxSustainableRate,
        isStrongSuggestion: isStrongSuggestion,
      );
    }

    // No faster alternatives - suggest reducing speed
    if (playbackRate > 1.0) {
      return PerformanceRecommendation(
        type: RecommendationType.reduceSpeed,
        reason: _buildReduceSpeedReason(stats, playbackRate),
        currentRTF: stats.p95,
        maxSustainableSpeed: stats.maxSustainableRate,
        isStrongSuggestion: isStrongSuggestion,
      );
    }

    // Already at 1x and fastest voice - offer pre-synthesis as option
    return PerformanceRecommendation(
      type: RecommendationType.offerPreSynthesis,
      reason: _buildOfferPreSynthesisReason(stats),
      currentRTF: stats.p95,
      maxSustainableSpeed: stats.maxSustainableRate,
      isStrongSuggestion: isStrongSuggestion,
    );
  }

  String _buildSwitchModelReason(RTFStatistics stats, double playbackRate) {
    if (playbackRate > 1.0) {
      return 'Your device may have trouble synthesizing "$currentVoiceId" fast enough '
          'for ${playbackRate}x playback. A faster voice could help.';
    }
    return 'Your device is working hard to keep up with "$currentVoiceId". '
        'A faster voice might provide smoother playback.';
  }

  String _buildReduceSpeedReason(RTFStatistics stats, double playbackRate) {
    final maxSpeed = stats.maxSustainableRate;
    return 'This voice works best up to ${maxSpeed.toStringAsFixed(1)}x on your device. '
        'Reducing speed from ${playbackRate}x may help.';
  }

  String _buildOfferPreSynthesisReason(RTFStatistics stats) {
    return 'Brief pauses may occur during playback. '
        'You can optionally pre-synthesize chapters for guaranteed smooth listening.';
  }
}

/// Voice compatibility level for proactive warnings.
enum VoiceCompatibility {
  /// Excellent compatibility - works great even at high speeds.
  excellent,

  /// Good compatibility - works well at normal speeds.
  good,

  /// Marginal compatibility - might struggle at high speeds.
  marginal,

  /// Too slow - cannot maintain realtime at any speed.
  tooSlow,

  /// Unknown - not enough data to assess.
  unknown,
}

/// Extension for VoiceCompatibility display.
extension VoiceCompatibilityDisplay on VoiceCompatibility {
  String get displayIcon => switch (this) {
        VoiceCompatibility.excellent => '⚡⚡',
        VoiceCompatibility.good => '⚡',
        VoiceCompatibility.marginal => '⚠️',
        VoiceCompatibility.tooSlow => '❌',
        VoiceCompatibility.unknown => '❓',
      };

  String get displayLabel => switch (this) {
        VoiceCompatibility.excellent => 'Great for 2x+',
        VoiceCompatibility.good => 'Good for 1.5x',
        VoiceCompatibility.marginal => 'Best at 1x',
        VoiceCompatibility.tooSlow => 'May struggle',
        VoiceCompatibility.unknown => 'Untested',
      };

  String get description => switch (this) {
        VoiceCompatibility.excellent =>
          'Excellent performance, works great even at high speeds',
        VoiceCompatibility.good =>
          'Good performance, works well at normal speeds',
        VoiceCompatibility.marginal =>
          'May struggle at high speeds, best at 1x',
        VoiceCompatibility.tooSlow =>
          'May need pre-synthesis for smooth playback',
        VoiceCompatibility.unknown =>
          'Not enough data to estimate performance',
      };
}

/// Estimates voice compatibility before user starts playing.
///
/// Uses learned performance profiles and device capabilities
/// to predict whether a voice will work well.
class VoiceCompatibilityEstimator {
  final DeviceCapabilities deviceCapabilities;

  /// Optional: Historical RTF data per voice (from PerformanceStore).
  final Map<String, double>? learnedRTFs;

  VoiceCompatibilityEstimator({
    required this.deviceCapabilities,
    this.learnedRTFs,
  });

  /// Estimate compatibility for a voice at intended playback speed.
  VoiceCompatibility estimateCompatibility({
    required String engineType,
    required String voiceId,
    required double intendedPlaybackSpeed,
  }) {
    // Try learned RTF first
    final key = '${engineType}_$voiceId';
    final learnedRTF = learnedRTFs?[key];

    double estimatedRTF;
    if (learnedRTF != null) {
      // Use actual measured data
      estimatedRTF = learnedRTF;
    } else {
      // Estimate from model tier
      final tier = ModelCatalog.getTier(engineType, voiceId);
      estimatedRTF = tier.expectedRTF;
    }

    // Adjust for device capability
    final maxConcurrency = deviceCapabilities.recommendedMaxConcurrency;
    final effectiveRTF = estimatedRTF / maxConcurrency;

    // Required RTF for intended speed
    final required = 1.0 / intendedPlaybackSpeed;

    // Compare with safety margins
    if (effectiveRTF < required * 0.5) return VoiceCompatibility.excellent;
    if (effectiveRTF < required * 0.8) return VoiceCompatibility.good;
    if (effectiveRTF < required * 1.2) return VoiceCompatibility.marginal;
    return VoiceCompatibility.tooSlow;
  }

  /// Get estimated max playback speed for a voice.
  double estimateMaxSpeed(String engineType, String voiceId) {
    final key = '${engineType}_$voiceId';
    final learnedRTF = learnedRTFs?[key];

    double rtf;
    if (learnedRTF != null) {
      rtf = learnedRTF;
    } else {
      final tier = ModelCatalog.getTier(engineType, voiceId);
      rtf = tier.expectedRTF;
    }

    final maxConcurrency = deviceCapabilities.recommendedMaxConcurrency;
    final effectiveRTF = rtf / maxConcurrency;

    // Max speed with 20% safety margin
    if (effectiveRTF <= 0) return 3.0;
    return (1.0 / effectiveRTF) * 0.8;
  }
}
