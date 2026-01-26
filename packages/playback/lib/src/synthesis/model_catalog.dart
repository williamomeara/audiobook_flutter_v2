/// Speed tier for a TTS model/voice.
///
/// Used to categorize voices by expected performance and
/// recommend alternatives when performance is insufficient.
enum ModelSpeedTier {
  /// Fastest models (Piper small/low quality).
  /// Typical RTF < 0.3 on modern devices.
  fast,

  /// Medium speed models (Piper medium, Kokoro compact).
  /// Typical RTF 0.3-0.6 on modern devices.
  medium,

  /// Slower models (Kokoro full quality).
  /// Typical RTF 0.5-1.0 on modern devices.
  slow,

  /// Premium quality, slowest (Supertonic).
  /// Typical RTF 0.8-1.5+ on modern devices.
  premium,
}

/// Extension for ModelSpeedTier properties.
extension ModelSpeedTierProperties on ModelSpeedTier {
  /// Display name for UI.
  String get displayName => switch (this) {
        ModelSpeedTier.fast => 'Fast',
        ModelSpeedTier.medium => 'Balanced',
        ModelSpeedTier.slow => 'Quality',
        ModelSpeedTier.premium => 'Premium',
      };

  /// Typical RTF range description.
  String get rtfRange => switch (this) {
        ModelSpeedTier.fast => '< 0.3x',
        ModelSpeedTier.medium => '0.3-0.6x',
        ModelSpeedTier.slow => '0.5-1.0x',
        ModelSpeedTier.premium => '0.8-1.5x',
      };

  /// Expected typical RTF (midpoint of range).
  double get expectedRTF => switch (this) {
        ModelSpeedTier.fast => 0.2,
        ModelSpeedTier.medium => 0.45,
        ModelSpeedTier.slow => 0.75,
        ModelSpeedTier.premium => 1.1,
      };

  /// Maximum recommended playback speed for this tier.
  double get maxRecommendedSpeed => switch (this) {
        ModelSpeedTier.fast => 3.0,
        ModelSpeedTier.medium => 2.0,
        ModelSpeedTier.slow => 1.5,
        ModelSpeedTier.premium => 1.0,
      };

  /// Sort order (faster = lower).
  int get sortOrder => switch (this) {
        ModelSpeedTier.fast => 0,
        ModelSpeedTier.medium => 1,
        ModelSpeedTier.slow => 2,
        ModelSpeedTier.premium => 3,
      };
}

/// Voice information for the catalog.
class VoiceInfo {
  final String voiceId;
  final String engineType;
  final String displayName;
  final ModelSpeedTier tier;
  final String language;
  final String? accent;
  final String? gender;

  const VoiceInfo({
    required this.voiceId,
    required this.engineType,
    required this.displayName,
    required this.tier,
    required this.language,
    this.accent,
    this.gender,
  });

  Map<String, dynamic> toJson() => {
        'voiceId': voiceId,
        'engineType': engineType,
        'displayName': displayName,
        'tier': tier.name,
        'language': language,
        'accent': accent,
        'gender': gender,
      };
}

/// Catalog of known TTS models/voices with speed tier information.
///
/// Provides:
/// - Speed tier classification for voices
/// - Faster alternative recommendations
/// - Voice metadata for UI display
///
/// ## Example
/// ```dart
/// final tier = ModelCatalog.getTier('kokoro', 'kokoro_af_bella');
/// // Returns ModelSpeedTier.slow
///
/// final alternatives = ModelCatalog.getFasterAlternatives('kokoro', 'kokoro_af_bella');
/// // Returns list of faster voices
/// ```
class ModelCatalog {
  ModelCatalog._();

  /// Get the speed tier for a voice.
  static ModelSpeedTier getTier(String engineType, String voiceId) {
    final engine = engineType.toLowerCase();
    final voice = voiceId.toLowerCase();

    // Piper voices
    if (engine == 'piper') {
      if (voice.contains('-low') ||
          voice.contains('-small') ||
          voice.contains('_low') ||
          voice.contains('_small')) {
        return ModelSpeedTier.fast;
      }
      // Medium is default for Piper
      return ModelSpeedTier.medium;
    }

    // Kokoro voices
    if (engine == 'kokoro') {
      // All Kokoro voices are considered "slow" (high quality)
      return ModelSpeedTier.slow;
    }

    // Supertonic voices
    if (engine == 'supertonic') {
      return ModelSpeedTier.premium;
    }

    // Unknown engine - assume medium
    return ModelSpeedTier.medium;
  }

  /// Get faster alternatives for a given voice.
  ///
  /// Returns voices from faster tiers with similar characteristics
  /// (same language, similar style if possible).
  static List<VoiceInfo> getFasterAlternatives(
    String engineType,
    String voiceId, {
    String? preferredLanguage,
  }) {
    final currentTier = getTier(engineType, voiceId);
    final alternatives = <VoiceInfo>[];

    // Get all voices faster than current tier
    final fasterTiers = ModelSpeedTier.values
        .where((t) => t.sortOrder < currentTier.sortOrder)
        .toList();

    if (fasterTiers.isEmpty) return []; // Already at fastest

    // Extract language from voice ID if not specified
    final language = preferredLanguage ?? _extractLanguage(voiceId);

    // Add Piper medium voices (faster than Kokoro/Supertonic)
    if (currentTier == ModelSpeedTier.slow ||
        currentTier == ModelSpeedTier.premium) {
      alternatives.addAll(_piperVoices.where((v) =>
          v.tier == ModelSpeedTier.medium &&
          (language == null || v.language == language)));
    }

    // Add Piper fast voices
    if (currentTier != ModelSpeedTier.fast) {
      alternatives.addAll(_piperVoices.where((v) =>
          v.tier == ModelSpeedTier.fast &&
          (language == null || v.language == language)));
    }

    // Sort by speed (fastest first)
    alternatives.sort((a, b) => a.tier.sortOrder.compareTo(b.tier.sortOrder));

    return alternatives;
  }

  /// Check if a voice exists in the catalog.
  static bool isKnownVoice(String engineType, String voiceId) {
    final engine = engineType.toLowerCase();
    return engine == 'piper' ||
        engine == 'kokoro' ||
        engine == 'supertonic';
  }

  /// Get all voices for an engine type.
  static List<VoiceInfo> getVoicesForEngine(String engineType) {
    final engine = engineType.toLowerCase();
    if (engine == 'piper') return _piperVoices;
    if (engine == 'kokoro') return _kokoroVoices;
    if (engine == 'supertonic') return _supertonicVoices;
    return [];
  }

  static String? _extractLanguage(String voiceId) {
    // Try to extract language code from voice ID
    // e.g., "piper_en_US-lessac-medium" -> "en"
    // e.g., "kokoro_af_bella" -> null (no standard format)
    final match = RegExp(r'[_-](en|de|fr|es|it)[_-]').firstMatch(voiceId);
    return match?.group(1);
  }

  // Known Piper voices (subset for demonstration)
  static const List<VoiceInfo> _piperVoices = [
    VoiceInfo(
      voiceId: 'piper_en_US-lessac-medium',
      engineType: 'piper',
      displayName: 'Lessac (US)',
      tier: ModelSpeedTier.medium,
      language: 'en',
      accent: 'US',
      gender: 'female',
    ),
    VoiceInfo(
      voiceId: 'piper_en_GB-alan-medium',
      engineType: 'piper',
      displayName: 'Alan (UK)',
      tier: ModelSpeedTier.medium,
      language: 'en',
      accent: 'UK',
      gender: 'male',
    ),
    VoiceInfo(
      voiceId: 'piper_en_US-amy-low',
      engineType: 'piper',
      displayName: 'Amy Low (US)',
      tier: ModelSpeedTier.fast,
      language: 'en',
      accent: 'US',
      gender: 'female',
    ),
  ];

  // Known Kokoro voices (subset for demonstration)
  static const List<VoiceInfo> _kokoroVoices = [
    VoiceInfo(
      voiceId: 'kokoro_af_bella',
      engineType: 'kokoro',
      displayName: 'Bella',
      tier: ModelSpeedTier.slow,
      language: 'en',
      accent: 'US',
      gender: 'female',
    ),
    VoiceInfo(
      voiceId: 'kokoro_af_sarah',
      engineType: 'kokoro',
      displayName: 'Sarah',
      tier: ModelSpeedTier.slow,
      language: 'en',
      accent: 'US',
      gender: 'female',
    ),
    VoiceInfo(
      voiceId: 'kokoro_am_adam',
      engineType: 'kokoro',
      displayName: 'Adam',
      tier: ModelSpeedTier.slow,
      language: 'en',
      accent: 'US',
      gender: 'male',
    ),
  ];

  // Known Supertonic voices (placeholder)
  static const List<VoiceInfo> _supertonicVoices = [
    VoiceInfo(
      voiceId: 'supertonic_premium',
      engineType: 'supertonic',
      displayName: 'Premium Voice',
      tier: ModelSpeedTier.premium,
      language: 'en',
    ),
  ];
}
