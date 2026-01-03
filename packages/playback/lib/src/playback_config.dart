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

  /// Concurrency limit for parallel synthesis.
  static const int prefetchConcurrency = 1;

  /// Delay before resuming prefetch after user interaction.
  static const Duration prefetchResumeDelay = Duration(milliseconds: 500);

  /// Debounce delay for seek operations with AI synthesis.
  static const Duration seekDebounce = Duration(milliseconds: 200);

  // Rate-independent synthesis
  /// When true, synthesis is always done at 1.0x and playback rate
  /// is adjusted in the audio player. This maximizes cache hits.
  static const bool rateIndependentSynthesis = true;

  // Engine-specific concurrency (can be tuned per device)
  static const int kokoroConcurrency = 1;
  static const int supertonicConcurrency = 2;
  static const int piperConcurrency = 1;

  // Thread limits per engine
  static const int kokoroThreads = 4;
  static const int supertonicThreads = 4;
  static const int piperThreads = 2;
}
