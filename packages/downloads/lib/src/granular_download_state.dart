import 'download_state.dart';

/// Status of a voice's installation (separate from core download).
/// For engines like Supertonic and Kokoro where the core is shared,
/// this allows showing individual voice "installations" even though
/// the voices are just speaker IDs within the downloaded core.
enum VoiceInstallStatus {
  /// Voice is not installed (core not downloaded OR voice not "activated").
  notInstalled,
  
  /// Voice is being installed (brief simulated activation step).
  installing,
  
  /// Voice is fully installed and ready to use.
  installed,
}

/// State of a single core download.
class CoreDownloadState {
  const CoreDownloadState({
    required this.coreId,
    required this.displayName,
    required this.engineType,
    required this.status,
    this.progress = 0.0,
    required this.sizeBytes,
    this.downloadedBytes = 0,
    this.startTime,
    this.error,
  });

  final String coreId;
  final String displayName;
  final String engineType;
  final DownloadStatus status;
  final double progress;
  final int sizeBytes;
  final int downloadedBytes;
  final DateTime? startTime;
  final String? error;

  bool get isReady => status == DownloadStatus.ready;
  bool get isDownloading =>
      status == DownloadStatus.downloading || status == DownloadStatus.queued;
  bool get isExtracting => status == DownloadStatus.extracting;
  bool get isFailed => status == DownloadStatus.failed;
  bool get isNotDownloaded => status == DownloadStatus.notDownloaded;
  
  /// Whether the download is active (downloading, extracting, or queued).
  bool get isActive => status == DownloadStatus.downloading || 
                       status == DownloadStatus.extracting ||
                       status == DownloadStatus.queued;
  
  /// Calculate download speed in bytes per second.
  double? get downloadSpeed {
    if (startTime == null || status != DownloadStatus.downloading) return null;
    final elapsed = DateTime.now().difference(startTime!).inMilliseconds;
    if (elapsed <= 0) return null;
    return (downloadedBytes / elapsed) * 1000;
  }
  
  /// Estimate remaining time in seconds.
  int? get estimatedSecondsRemaining {
    final speed = downloadSpeed;
    if (speed == null || speed <= 0) return null;
    final remaining = sizeBytes - downloadedBytes;
    return (remaining / speed).ceil();
  }
  
  /// Format ETA as human-readable string.
  String? get etaText {
    final seconds = estimatedSecondsRemaining;
    if (seconds == null) return null;
    if (seconds < 60) return '${seconds}s left';
    if (seconds < 3600) return '${(seconds / 60).ceil()}m left';
    return '${(seconds / 3600).ceil()}h left';
  }
  
  /// Format download speed as human-readable string.
  String? get speedText {
    final speed = downloadSpeed;
    if (speed == null) return null;
    return '${_formatBytes(speed.round())}/s';
  }

  /// Human-readable status text for UI display.
  String get statusText {
    switch (status) {
      case DownloadStatus.notDownloaded:
        return _formatBytes(sizeBytes);
      case DownloadStatus.queued:
        return 'Waiting...';
      case DownloadStatus.downloading:
        final percent = (progress * 100).toStringAsFixed(0);
        final speed = speedText;
        final eta = etaText;
        if (speed != null && eta != null) {
          return '$percent% · $speed · $eta';
        }
        return '$percent% · ${_formatBytes(downloadedBytes)} / ${_formatBytes(sizeBytes)}';
      case DownloadStatus.extracting:
        return 'Unpacking files...';
      case DownloadStatus.ready:
        return 'Ready';
      case DownloadStatus.failed:
        return error ?? 'Failed - Tap to retry';
    }
  }

  CoreDownloadState copyWith({
    String? coreId,
    String? displayName,
    String? engineType,
    DownloadStatus? status,
    double? progress,
    int? sizeBytes,
    int? downloadedBytes,
    DateTime? startTime,
    String? error,
  }) {
    return CoreDownloadState(
      coreId: coreId ?? this.coreId,
      displayName: displayName ?? this.displayName,
      engineType: engineType ?? this.engineType,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      startTime: startTime ?? this.startTime,
      error: error ?? this.error,
    );
  }

  @override
  String toString() =>
      'CoreDownloadState($coreId, $status, ${(progress * 100).toStringAsFixed(0)}%)';
}

/// State of a voice (includes dependency info and individual install status).
class VoiceDownloadState {
  const VoiceDownloadState({
    required this.voiceId,
    required this.displayName,
    required this.engineId,
    required this.language,
    required this.requiredCoreIds,
    this.speakerId,
    this.modelKey,
    this.installStatus = VoiceInstallStatus.notInstalled,
  });

  final String voiceId;
  final String displayName;
  final String engineId;
  final String language;
  final List<String> requiredCoreIds;
  final int? speakerId;
  final String? modelKey;
  
  /// Individual voice install status.
  /// For Piper: voice IS the core, so this follows core status.
  /// For Supertonic/Kokoro: voice is a speaker ID within core, so we track
  /// individual "installation" to give users the perception of downloading
  /// individual voices (even though they're just activating speaker IDs).
  final VoiceInstallStatus installStatus;
  
  /// Whether this voice uses shared core (Supertonic, Kokoro) vs self-contained (Piper).
  bool get usesSharedCore => engineId == 'supertonic' || engineId == 'kokoro';

  /// Check if all required cores are ready.
  bool allCoresReady(Map<String, CoreDownloadState> coreStates) {
    return requiredCoreIds.every((id) => coreStates[id]?.isReady ?? false);
  }
  
  /// Check if this voice is fully ready to use.
  /// For Piper: just checks core is ready.
  /// For Supertonic/Kokoro: checks core is ready AND voice is installed.
  bool isReady(Map<String, CoreDownloadState> coreStates) {
    if (!allCoresReady(coreStates)) return false;
    // For shared core engines, also check voice install status
    if (usesSharedCore) {
      return installStatus == VoiceInstallStatus.installed;
    }
    // For Piper, core ready = voice ready
    return true;
  }
  
  /// Whether the voice is currently being installed.
  bool get isInstalling => installStatus == VoiceInstallStatus.installing;

  /// Check if any required core is currently downloading.
  bool anyDownloading(Map<String, CoreDownloadState> coreStates) {
    return requiredCoreIds.any((id) => coreStates[id]?.isDownloading ?? false);
  }

  /// Check if any required core is queued (but not actively downloading).
  bool anyQueued(Map<String, CoreDownloadState> coreStates) {
    return requiredCoreIds.any((id) {
      final core = coreStates[id];
      return core != null && 
             core.status == DownloadStatus.queued;
    });
  }

  /// Get list of missing core IDs.
  List<String> getMissingCoreIds(Map<String, CoreDownloadState> coreStates) {
    return requiredCoreIds
        .where((id) => !(coreStates[id]?.isReady ?? false))
        .toList();
  }

  /// Get download progress (average of required cores).
  double getDownloadProgress(Map<String, CoreDownloadState> coreStates) {
    if (requiredCoreIds.isEmpty) return 1.0;
    final total = requiredCoreIds.fold<double>(
      0.0,
      (sum, id) => sum + (coreStates[id]?.progress ?? 0.0),
    );
    return total / requiredCoreIds.length;
  }
  
  /// Create a copy with updated install status.
  VoiceDownloadState copyWith({
    VoiceInstallStatus? installStatus,
  }) {
    return VoiceDownloadState(
      voiceId: voiceId,
      displayName: displayName,
      engineId: engineId,
      language: language,
      requiredCoreIds: requiredCoreIds,
      speakerId: speakerId,
      modelKey: modelKey,
      installStatus: installStatus ?? this.installStatus,
    );
  }

  @override
  String toString() => 'VoiceDownloadState($voiceId, $engineId, $installStatus)';
}

/// Combined download state for UI.
class GranularDownloadState {
  const GranularDownloadState({
    required this.cores,
    required this.voices,
    this.currentDownload,
    this.error,
  });

  final Map<String, CoreDownloadState> cores;
  final Map<String, VoiceDownloadState> voices;
  final String? currentDownload;
  final String? error;

  /// Get all voices that are ready to use.
  /// Uses the new isReady method which accounts for individual voice installation.
  List<VoiceDownloadState> get readyVoices =>
      voices.values.where((v) => v.isReady(cores)).toList();

  /// Get voices for a specific engine.
  List<VoiceDownloadState> getVoicesForEngine(String engineId) =>
      voices.values.where((v) => v.engineId == engineId).toList();

  /// Get cores for a specific engine.
  List<CoreDownloadState> getCoresForEngine(String engineId) =>
      cores.values.where((c) => c.engineType == engineId).toList();

  /// Check if a core is ready.
  bool isCoreReady(String coreId) => cores[coreId]?.isReady ?? false;

  /// Check if a voice can be used (all cores ready AND voice installed).
  bool isVoiceReady(String voiceId) {
    final voice = voices[voiceId];
    if (voice == null) return false;
    return voice.isReady(cores);
  }

  /// Check if any downloads are in progress.
  bool get isDownloading => cores.values.any((c) => c.isDownloading);

  /// Get total installed size in bytes.
  int get totalInstalledSize => cores.values
      .where((c) => c.isReady)
      .fold(0, (sum, c) => sum + c.sizeBytes);

  /// Get count of ready voices.
  int get readyVoiceCount => readyVoices.length;

  /// Get total voice count.
  int get totalVoiceCount => voices.length;

  GranularDownloadState copyWith({
    Map<String, CoreDownloadState>? cores,
    Map<String, VoiceDownloadState>? voices,
    String? currentDownload,
    String? error,
  }) {
    return GranularDownloadState(
      cores: cores ?? this.cores,
      voices: voices ?? this.voices,
      currentDownload: currentDownload,
      error: error,
    );
  }

  /// Create empty state.
  static const empty = GranularDownloadState(
    cores: {},
    voices: {},
  );
}

/// Format bytes as human-readable string.
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
