/// Download state for an asset.
enum DownloadStatus {
  /// Asset is not downloaded.
  notDownloaded,

  /// Download is queued.
  queued,

  /// Download is in progress.
  downloading,

  /// Extracting/installing downloaded content.
  extracting,

  /// Asset is fully installed and ready.
  ready,

  /// Download or installation failed.
  failed,
}

/// State of a download operation.
class DownloadState {
  const DownloadState({
    required this.status,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.error,
  });

  /// Current status.
  final DownloadStatus status;

  /// Progress from 0.0 to 1.0.
  final double progress;

  /// Bytes downloaded so far.
  final int downloadedBytes;

  /// Total bytes to download (if known).
  final int? totalBytes;

  /// Error message if failed.
  final String? error;

  /// Whether download is complete and ready.
  bool get isReady => status == DownloadStatus.ready;

  /// Whether download is in progress.
  bool get isDownloading =>
      status == DownloadStatus.downloading || status == DownloadStatus.queued;

  static const notDownloaded = DownloadState(status: DownloadStatus.notDownloaded);
  static const ready = DownloadState(status: DownloadStatus.ready, progress: 1.0);

  DownloadState copyWith({
    DownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    String? error,
  }) {
    return DownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      error: error ?? this.error,
    );
  }

  @override
  String toString() =>
      'DownloadState($status, ${(progress * 100).toStringAsFixed(1)}%)';
}
