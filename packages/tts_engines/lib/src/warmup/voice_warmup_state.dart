/// Phases of voice warmup initialization.
///
/// This state machine tracks the progressive warmup of TTS voice engines,
/// enabling responsive UI feedback during the potentially slow CoreML
/// compilation on iOS (which can take ~50 seconds on first use).
enum WarmupPhase {
  /// Warmup has not been requested yet.
  notStarted,

  /// Checking if voice files exist locally.
  /// This phase is synchronous and fast (<100ms).
  fileValidation,

  /// Initializing the engine core (CoreML/ONNX runtime).
  /// This is the slow phase on iOS (~50 seconds for CoreML compilation).
  /// On Android (ONNX), this takes 1-3 seconds.
  coreInitializing,

  /// Loading the specific voice model after engine is ready.
  /// Typically fast (<500ms).
  voiceLoading,

  /// Warmup complete, voice is ready for synthesis.
  ready,

  /// Warmup failed at some phase.
  failed,
}

/// State of a voice warmup operation.
///
/// Provides detailed progress information for UI display, allowing
/// the app to show phase-specific messages during the warmup process.
class VoiceWarmupState {
  const VoiceWarmupState({
    required this.voiceId,
    required this.phase,
    this.progress = 0.0,
    this.message,
    this.errorMessage,
    this.startTime,
    this.phaseStartTime,
  });

  /// Voice ID being warmed up.
  final String voiceId;

  /// Current warmup phase.
  final WarmupPhase phase;

  /// Progress within current phase (0.0 to 1.0).
  /// Note: CoreML compilation doesn't report progress, so this may stay at 0.
  final double progress;

  /// Human-readable status message for UI display.
  final String? message;

  /// Error message if phase == failed.
  final String? errorMessage;

  /// When warmup started (for elapsed time calculation).
  final DateTime? startTime;

  /// When current phase started.
  final DateTime? phaseStartTime;

  /// Whether warmup is complete and voice is ready.
  bool get isReady => phase == WarmupPhase.ready;

  /// Whether warmup failed.
  bool get isFailed => phase == WarmupPhase.failed;

  /// Whether warmup is in progress.
  bool get isActive =>
      phase == WarmupPhase.fileValidation ||
      phase == WarmupPhase.coreInitializing ||
      phase == WarmupPhase.voiceLoading;

  /// Elapsed time since warmup started.
  Duration get elapsed =>
      startTime != null ? DateTime.now().difference(startTime!) : Duration.zero;

  /// Elapsed time in current phase.
  Duration get phaseElapsed =>
      phaseStartTime != null
          ? DateTime.now().difference(phaseStartTime!)
          : Duration.zero;

  /// Human-readable status text for UI display.
  String get displayStatus {
    return switch (phase) {
      WarmupPhase.notStarted => '',
      WarmupPhase.fileValidation => 'Checking files...',
      WarmupPhase.coreInitializing => message ?? 'Initializing engine...',
      WarmupPhase.voiceLoading => 'Loading voice...',
      WarmupPhase.ready => 'Ready',
      WarmupPhase.failed => errorMessage ?? 'Warmup failed',
    };
  }

  /// Factory for initial state.
  static VoiceWarmupState initial(String voiceId) => VoiceWarmupState(
        voiceId: voiceId,
        phase: WarmupPhase.notStarted,
      );

  /// Factory for ready state.
  static VoiceWarmupState ready(String voiceId, DateTime startTime) =>
      VoiceWarmupState(
        voiceId: voiceId,
        phase: WarmupPhase.ready,
        progress: 1.0,
        startTime: startTime,
      );

  /// Factory for failed state.
  static VoiceWarmupState failed(
    String voiceId,
    String error,
    DateTime startTime,
  ) =>
      VoiceWarmupState(
        voiceId: voiceId,
        phase: WarmupPhase.failed,
        errorMessage: error,
        startTime: startTime,
      );

  /// Create a copy with updated fields.
  VoiceWarmupState copyWith({
    String? voiceId,
    WarmupPhase? phase,
    double? progress,
    String? message,
    String? errorMessage,
    DateTime? startTime,
    DateTime? phaseStartTime,
  }) {
    return VoiceWarmupState(
      voiceId: voiceId ?? this.voiceId,
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      errorMessage: errorMessage ?? this.errorMessage,
      startTime: startTime ?? this.startTime,
      phaseStartTime: phaseStartTime ?? this.phaseStartTime,
    );
  }

  @override
  String toString() {
    final elapsedStr = elapsed.inMilliseconds > 0 ? ' (${elapsed.inMilliseconds}ms)' : '';
    return 'VoiceWarmupState($voiceId: $phase$elapsedStr)';
  }
}
