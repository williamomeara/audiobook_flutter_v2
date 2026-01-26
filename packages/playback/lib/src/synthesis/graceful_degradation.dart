import 'device_capabilities.dart';
import 'rtf_monitor.dart';

/// Playback mode chosen by or suggested to the user.
///
/// These modes represent user preferences, not requirements.
/// Users can ALWAYS choose to play immediately regardless of mode.
enum PlaybackMode {
  /// Default: Start playback immediately, synthesize on-demand.
  /// Buffer status shown in UI but playback is never blocked.
  realtime,

  /// User chose to wait for buffer before playing.
  /// Completely optional - user can cancel and play anytime.
  buffered,

  /// User chose to pre-synthesize chapter.
  /// Completely optional - user can play immediately instead.
  preSynthesized,
}

/// Device synthesis capability assessment.
enum SynthesisCapability {
  /// Device can synthesize faster than realtime with most voices.
  capable,

  /// Device barely keeps up - may struggle at higher speeds.
  marginal,

  /// Device cannot achieve realtime with any voice.
  /// But user can STILL play - just may experience pauses.
  incapable,
}

/// A recommendation for playback experience.
///
/// **Important: Recommendations are suggestions, not requirements.**
/// Users can ALWAYS choose to play immediately regardless of what
/// this recommends. The `canPlayImmediately` is always true.
class PlaybackRecommendation {
  /// Suggested playback mode based on device capability.
  final PlaybackMode suggested;

  /// Optional reason/warning to display (dismissible).
  /// Null if no warning needed.
  final String? reason;

  /// Whether to show buffer indicator in player UI.
  final bool showBufferStatus;

  /// Whether to offer "Wait for buffer" option.
  final bool offerWaitForBuffer;

  /// Whether to offer pre-synthesis in chapter view.
  final bool offerPreSynthesis;

  /// Assessed device capability.
  final SynthesisCapability capability;

  /// Current observed RTF (if known).
  final double? observedRTF;

  const PlaybackRecommendation({
    required this.suggested,
    this.reason,
    this.showBufferStatus = false,
    this.offerWaitForBuffer = false,
    this.offerPreSynthesis = false,
    required this.capability,
    this.observedRTF,
  });

  /// User can ALWAYS choose to play immediately.
  /// This is always true - recommendations never block playback.
  bool get canPlayImmediately => true;

  /// Whether this recommendation includes a warning/reason.
  bool get hasWarning => reason != null;

  /// No recommendation needed - everything is fine.
  static const none = PlaybackRecommendation(
    suggested: PlaybackMode.realtime,
    reason: null,
    showBufferStatus: false,
    offerWaitForBuffer: false,
    offerPreSynthesis: false,
    capability: SynthesisCapability.capable,
  );

  Map<String, dynamic> toJson() => {
        'suggested': suggested.name,
        'reason': reason,
        'showBufferStatus': showBufferStatus,
        'offerWaitForBuffer': offerWaitForBuffer,
        'offerPreSynthesis': offerPreSynthesis,
        'capability': capability.name,
        'observedRTF': observedRTF,
        'canPlayImmediately': canPlayImmediately,
      };
}

/// Provides playback recommendations based on device capability.
///
/// **Philosophy: Suggest, Don't Force**
///
/// This class assesses device capability and makes recommendations,
/// but NEVER blocks playback or forces users to wait. All suggestions
/// are optional.
///
/// ## Usage
///
/// ```dart
/// final degradation = GracefulDegradation(
///   rtfMonitor: monitor,
///   deviceCapabilities: capabilities,
/// );
///
/// final recommendation = degradation.getRecommendation(playbackRate: 1.5);
///
/// if (recommendation.hasWarning) {
///   // Show dismissible warning in UI
///   showDismissibleWarning(recommendation.reason);
/// }
///
/// // User can ALWAYS tap Play regardless of recommendation
/// if (recommendation.showBufferStatus) {
///   showBufferIndicator();
/// }
/// ```
class GracefulDegradation {
  final RTFMonitor? rtfMonitor;
  final DeviceCapabilities deviceCapabilities;

  GracefulDegradation({
    this.rtfMonitor,
    required this.deviceCapabilities,
  });

  /// Assess device synthesis capability.
  ///
  /// Returns capability based on observed RTF or device profile.
  SynthesisCapability assessCapability({double? rtf}) {
    final effectiveRTF = rtf ?? rtfMonitor?.statistics.p95;

    if (effectiveRTF == null) {
      // No RTF data - assess based on device
      final cores = deviceCapabilities.recommendedMaxConcurrency;
      if (cores >= 3) return SynthesisCapability.capable;
      if (cores >= 2) return SynthesisCapability.marginal;
      return SynthesisCapability.incapable;
    }

    // RTF < 0.8 means synthesis is faster than realtime with margin
    if (effectiveRTF < 0.8) return SynthesisCapability.capable;
    // RTF < 1.2 means roughly keeping up
    if (effectiveRTF < 1.2) return SynthesisCapability.marginal;
    // RTF > 1.2 means falling behind
    return SynthesisCapability.incapable;
  }

  /// Get playback recommendation based on device capability.
  ///
  /// **Note: User can ALWAYS ignore recommendation and play immediately.**
  PlaybackRecommendation getRecommendation({
    double playbackRate = 1.0,
    double? observedRTF,
  }) {
    final rtf = observedRTF ?? rtfMonitor?.statistics.p95;
    final capability = assessCapability(rtf: rtf);

    switch (capability) {
      case SynthesisCapability.capable:
        return PlaybackRecommendation(
          suggested: PlaybackMode.realtime,
          reason: null,
          showBufferStatus: false,
          offerWaitForBuffer: false,
          offerPreSynthesis: false,
          capability: capability,
          observedRTF: rtf,
        );

      case SynthesisCapability.marginal:
        String? reason;
        if (playbackRate > 1.5) {
          reason = 'Buffer may run low at ${playbackRate}x playback speed';
        }
        return PlaybackRecommendation(
          suggested: PlaybackMode.realtime, // Still default to play
          reason: reason,
          showBufferStatus: true, // Show buffer indicator
          offerWaitForBuffer: true, // Offer as option
          offerPreSynthesis: false,
          capability: capability,
          observedRTF: rtf,
        );

      case SynthesisCapability.incapable:
        return PlaybackRecommendation(
          suggested: PlaybackMode.realtime, // STILL default to play!
          reason: 'Brief pauses may occur while synthesizing',
          showBufferStatus: true,
          offerWaitForBuffer: true,
          offerPreSynthesis: true, // Offer in chapter view
          capability: capability,
          observedRTF: rtf,
        );
    }
  }

  /// Get minimum recommended buffer for smooth playback.
  ///
  /// This is a suggestion, not a requirement.
  Duration recommendedMinimumBuffer(SynthesisCapability capability) {
    switch (capability) {
      case SynthesisCapability.capable:
        return Duration.zero; // No minimum needed
      case SynthesisCapability.marginal:
        return const Duration(seconds: 30); // Some buffer helps
      case SynthesisCapability.incapable:
        return const Duration(minutes: 2); // More buffer if user chooses
    }
  }
}
