/// Core ready state for TTS engine initialization.
enum CoreReadyState {
  /// Core not checked yet.
  notStarted,

  /// Fetching core from CDN.
  downloading,

  /// Unpacking archive (tar.gz).
  extracting,

  /// Checking SHA256 hash.
  verifying,

  /// Model loaded in memory.
  loaded,

  /// Ready to synthesize.
  ready,

  /// Permanent error (user action needed).
  failed,
}

/// Core readiness information for UI display.
class CoreReadiness {
  const CoreReadiness({
    required this.state,
    this.engineId,
    this.errorMessage,
    this.downloadProgress,
    this.downloadedBytes,
    this.totalBytes,
  });

  final CoreReadyState state;
  final String? engineId;
  final String? errorMessage;

  /// Download progress from 0.0 to 1.0.
  final double? downloadProgress;

  /// Bytes downloaded so far.
  final int? downloadedBytes;

  /// Total bytes to download.
  final int? totalBytes;

  bool get isReady => state == CoreReadyState.ready;
  bool get canSynthesizeNow =>
      state == CoreReadyState.loaded || state == CoreReadyState.ready;
  bool get isDownloading => state == CoreReadyState.downloading;
  bool get isFailed => state == CoreReadyState.failed;

  CoreReadiness copyWith({
    CoreReadyState? state,
    String? engineId,
    String? errorMessage,
    double? downloadProgress,
    int? downloadedBytes,
    int? totalBytes,
  }) {
    return CoreReadiness(
      state: state ?? this.state,
      engineId: engineId ?? this.engineId,
      errorMessage: errorMessage ?? this.errorMessage,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }

  @override
  String toString() {
    final progress = downloadProgress != null
        ? ' (${(downloadProgress! * 100).toStringAsFixed(1)}%)'
        : '';
    return 'CoreReadiness($state$progress)';
  }

  /// Factory for initial state.
  static const notStarted = CoreReadiness(state: CoreReadyState.notStarted);

  /// Factory for ready state.
  static CoreReadiness readyFor(String engineId) => CoreReadiness(
        state: CoreReadyState.ready,
        engineId: engineId,
      );

  /// Factory for failed state.
  static CoreReadiness failedWith(String engineId, String error) =>
      CoreReadiness(
        state: CoreReadyState.failed,
        engineId: engineId,
        errorMessage: error,
      );
}

/// Voice ready state for UI display.
enum VoiceReadyState {
  /// Checking if voice is ready.
  checking,

  /// Core must download first.
  coreRequired,

  /// Core is loading.
  coreLoading,

  /// Ready to synthesize.
  voiceReady,

  /// Permanent error.
  error,
}

/// Voice readiness information.
class VoiceReadiness {
  const VoiceReadiness({
    required this.voiceId,
    required this.state,
    this.coreState,
    this.errorMessage,
    this.nextActionUserShouldTake,
  });

  final String voiceId;
  final VoiceReadyState state;
  final CoreReadyState? coreState;
  final String? errorMessage;

  /// User-friendly action hint (e.g., "Download core (250MB)").
  final String? nextActionUserShouldTake;

  bool get isReady => state == VoiceReadyState.voiceReady;

  @override
  String toString() => 'VoiceReadiness($voiceId: $state)';
}

/// Synthesis lifecycle stages.
enum SynthStage {
  /// Waiting for synth pool.
  queued,

  /// Checking voice is loaded.
  voiceReady,

  /// Running model inference.
  inferencing,

  /// Writing WAV to disk.
  writingFile,

  /// Moving from .tmp to final.
  cacheMoving,

  /// Success.
  complete,

  /// Error.
  failed,

  /// User cancelled.
  cancelled,
}

/// Error types from TTS engine.
enum EngineError {
  /// Core not installed.
  modelMissing,

  /// SHA256 mismatch.
  modelCorrupted,

  /// Model inference error (OOM, etc).
  inferenceFailed,

  /// Native runtime crashed.
  runtimeCrash,

  /// User cancelled operation.
  cancelled,

  /// Invalid input (empty text, etc).
  invalidInput,

  /// File write failed.
  fileWriteError,

  /// Unknown error.
  unknown,
}

/// Extended synthesis result with lifecycle info.
class ExtendedSynthResult {
  const ExtendedSynthResult({
    required this.success,
    this.outputFile,
    this.durationMs,
    this.sampleRate = 24000,
    this.errorMessage,
    this.errorCode,
    this.stage,
    this.retryCount = 0,
  });

  final bool success;
  final String? outputFile;
  final int? durationMs;
  final int sampleRate;
  final String? errorMessage;
  final EngineError? errorCode;
  final SynthStage? stage;
  final int retryCount;

  @override
  String toString() {
    if (success) {
      return 'ExtendedSynthResult(success, ${durationMs}ms)';
    }
    return 'ExtendedSynthResult(failed at $stage: $errorMessage)';
  }

  /// Factory for success.
  static ExtendedSynthResult successWith({
    required String outputFile,
    required int durationMs,
    int sampleRate = 24000,
  }) =>
      ExtendedSynthResult(
        success: true,
        outputFile: outputFile,
        durationMs: durationMs,
        sampleRate: sampleRate,
        stage: SynthStage.complete,
      );

  /// Factory for failure.
  static ExtendedSynthResult failedWith({
    required EngineError code,
    required String message,
    SynthStage? stage,
    int retryCount = 0,
  }) =>
      ExtendedSynthResult(
        success: false,
        errorCode: code,
        errorMessage: message,
        stage: stage ?? SynthStage.failed,
        retryCount: retryCount,
      );

  /// Factory for cancelled.
  static const cancelled = ExtendedSynthResult(
    success: false,
    errorCode: EngineError.cancelled,
    stage: SynthStage.cancelled,
  );
}
