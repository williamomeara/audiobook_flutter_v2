/// Configuration constants for playback.
class PlaybackConfig {
  PlaybackConfig._();

  // Playback rate limits
  static const double minPlaybackRate = 0.5;
  static const double maxPlaybackRate = 3.0;
  static const double defaultPlaybackRate = 1.0;

  // Buffer thresholds
  /// Target buffer size in milliseconds of audio.
  static const int bufferTargetMs = 30000; // 30 seconds

  /// Low watermark - start prefetching when buffer falls below this.
  static const int lowWatermarkMs = 10000; // 10 seconds

  /// High watermark - stop prefetching when buffer exceeds this.
  static const int highWatermarkMs = 60000; // 60 seconds

  // Prefetch configuration
  /// Maximum number of tracks to prefetch ahead.
  static const int maxPrefetchTracks = 10;

  /// Delay before resuming prefetch after user interaction.
  static const Duration prefetchResumeDelay = Duration(milliseconds: 500);

  /// Debounce delay for seek operations with AI synthesis.
  static const Duration seekDebounce = Duration(milliseconds: 200);

  /// Timeout for individual synthesis operations.
  /// If synthesis takes longer than this, it's considered hung and is cancelled.
  /// Default is 120 seconds which is generous for most segments.
  static const Duration synthesisTimeout = Duration(seconds: 120);

  // Rate-independent synthesis
  /// When true, synthesis is always done at 1.0x and playback rate
  /// is adjusted in the audio player. This maximizes cache hits.
  static const bool rateIndependentSynthesis = true;

  // Engine-specific concurrency (can be tuned per device)
  static const int kokoroConcurrency = 2;
  static const int supertonicConcurrency = 2;
  static const int piperConcurrency = 2;

  // Thread limits per engine
  static const int kokoroThreads = 4;
  static const int supertonicThreads = 4;
  static const int piperThreads = 2;

  // ═══════════════════════════════════════════════════════════════════
  // PHASE 2: Extended Prefetch Configuration
  // ═══════════════════════════════════════════════════════════════════

  /// Aggressive prefetch window - used when battery is sufficient (>30%)
  /// Pre-synthesizes more segments to ensure smooth playback
  static const int aggressivePrefetchTracks = 15;

  /// Conservative prefetch window - used when battery is low (<20%)
  static const int conservativePrefetchTracks = 5;

  /// Full chapter prefetch threshold - battery percentage above which
  /// we synthesize the entire chapter in background
  static const int fullChapterPrefetchBatteryThreshold = 50;

  /// Minimum battery level to allow any prefetch (below this, only JIT)
  static const int minimumPrefetchBatteryLevel = 10;

  /// Target buffer for aggressive mode (90 seconds)
  static const int aggressiveBufferTargetMs = 90000;

  /// Immediately start prefetching on chapter load (Phase 2 enhancement)
  static const bool immediatePrefetchOnLoad = true;
  
  // ═══════════════════════════════════════════════════════════════════
  // GAPLESS PLAYBACK Configuration
  // ═══════════════════════════════════════════════════════════════════
  
  /// Feature flag for gapless playback.
  /// When enabled, audio segments are queued in a playlist and played
  /// sequentially without gaps between them.
  /// Disabled by default - enable after testing.
  static const bool gaplessPlaybackEnabled = false;

  // ═══════════════════════════════════════════════════════════════════
  // PHASE 4: Parallel Synthesis Configuration
  // ═══════════════════════════════════════════════════════════════════

  /// Feature flag for parallel synthesis.
  /// When enabled and device has sufficient memory, multiple segments
  /// can be synthesized concurrently.
  /// Disabled by default - enable after testing on target devices.
  static const bool parallelSynthesisEnabled = true;

  /// Get concurrency limit for a specific engine type.
  /// Returns 1 if parallel synthesis is disabled.
  static int getConcurrencyForEngine(String engineType) {
    if (!parallelSynthesisEnabled) return 1;
    return switch (engineType.toLowerCase()) {
      'kokoro' => kokoroConcurrency,
      'supertonic' => supertonicConcurrency,
      'piper' => piperConcurrency,
      _ => 1,
    };
  }

  /// Memory threshold below which parallel synthesis is paused (bytes).
  static const int parallelSynthesisMemoryThreshold = 200 * 1024 * 1024; // 200 MB
}

/// Synthesis mode based on resource constraints
enum SynthesisMode {
  /// Maximum prefetch - charging or high battery (>50%)
  aggressive,

  /// Balanced prefetch - normal battery (20-50%)
  balanced,

  /// Conservative prefetch - low battery (10-20%)
  conservative,

  /// JIT only - very low battery (<10%) or disabled
  jitOnly,
}

/// Extension to determine prefetch parameters based on mode
extension SynthesisModeConfig on SynthesisMode {
  /// Maximum tracks to prefetch in this mode
  int get maxPrefetchTracks {
    switch (this) {
      case SynthesisMode.aggressive:
        return PlaybackConfig.aggressivePrefetchTracks;
      case SynthesisMode.balanced:
        return PlaybackConfig.maxPrefetchTracks;
      case SynthesisMode.conservative:
        return PlaybackConfig.conservativePrefetchTracks;
      case SynthesisMode.jitOnly:
        return 0;
    }
  }

  /// Target buffer in milliseconds
  int get bufferTargetMs {
    switch (this) {
      case SynthesisMode.aggressive:
        return PlaybackConfig.aggressiveBufferTargetMs;
      case SynthesisMode.balanced:
        return PlaybackConfig.bufferTargetMs;
      case SynthesisMode.conservative:
        return PlaybackConfig.lowWatermarkMs;
      case SynthesisMode.jitOnly:
        return 0;
    }
  }

  /// Whether to enable full chapter prefetch
  bool get enableFullChapterPrefetch {
    return this == SynthesisMode.aggressive;
  }

  /// Concurrency limit for parallel synthesis
  int get concurrencyLimit {
    switch (this) {
      case SynthesisMode.aggressive:
        return 2;
      case SynthesisMode.balanced:
        return 1;
      case SynthesisMode.conservative:
        return 1;
      case SynthesisMode.jitOnly:
        return 0;
    }
  }
}
