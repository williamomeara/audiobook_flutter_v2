import 'dart:math';

/// Types of download errors with recovery strategies.
enum DownloadErrorType {
  /// Network timed out - retry with exponential backoff.
  networkTimeout,

  /// Cannot reach server - check internet connection.
  networkUnreachable,

  /// Not enough storage space - need user action.
  noSpace,

  /// Downloaded file checksum doesn't match - delete and retry.
  checksumMismatch,

  /// File permission error - fatal, needs user action.
  filePermissions,

  /// Download was interrupted - can resume or retry.
  interrupted,

  /// Manifest configuration error - need app update.
  manifestError,

  /// Unknown error.
  unknown;

  /// Whether this error type can be retried.
  bool get isRetryable =>
      !{filePermissions, manifestError}.contains(this);

  /// Get retry delay for exponential backoff.
  Duration getRetryDelay(int attemptNumber) {
    if (!isRetryable) return Duration.zero;
    final seconds = min(32, pow(2, attemptNumber).toInt());
    return Duration(seconds: seconds);
  }

  /// User-friendly error message.
  String get userMessage {
    switch (this) {
      case networkTimeout:
        return 'Network timed out. Check your connection and try again.';
      case networkUnreachable:
        return 'Cannot reach server. Check your internet connection.';
      case noSpace:
        return 'Not enough storage space. Free up some space and try again.';
      case checksumMismatch:
        return 'Download was corrupted. Please try again.';
      case filePermissions:
        return 'Permission denied. Check app storage permissions.';
      case interrupted:
        return 'Download was interrupted. Tap to resume.';
      case manifestError:
        return 'Configuration error. Please update the app.';
      case unknown:
        return 'An unexpected error occurred. Please try again.';
    }
  }
}

/// Exception for download errors with type information.
class DownloadException implements Exception {
  DownloadException(
    this.type,
    this.message, {
    this.attemptNumber = 0,
    this.originalError,
  });

  final DownloadErrorType type;
  final String message;
  final int attemptNumber;
  final Object? originalError;

  /// Whether this download should be retried.
  bool get shouldRetry => type.isRetryable && attemptNumber < 3;

  /// Get delay before next retry.
  Duration get retryDelay => type.getRetryDelay(attemptNumber);

  /// Create next attempt exception with incremented counter.
  DownloadException nextAttempt() {
    return DownloadException(
      type,
      message,
      attemptNumber: attemptNumber + 1,
      originalError: originalError,
    );
  }

  @override
  String toString() =>
      'DownloadException: ${type.userMessage} (attempt $attemptNumber: $message)';

  /// Create from HTTP status code.
  factory DownloadException.fromHttpStatus(int statusCode, String url) {
    if (statusCode == 408 || statusCode == 504) {
      return DownloadException(
        DownloadErrorType.networkTimeout,
        'HTTP $statusCode for $url',
      );
    }
    if (statusCode >= 500) {
      return DownloadException(
        DownloadErrorType.networkUnreachable,
        'HTTP $statusCode for $url',
      );
    }
    return DownloadException(
      DownloadErrorType.unknown,
      'HTTP $statusCode for $url',
    );
  }

  /// Create from socket/network exception.
  factory DownloadException.fromSocketException(Object error) {
    return DownloadException(
      DownloadErrorType.networkUnreachable,
      error.toString(),
      originalError: error,
    );
  }

  /// Create from file system exception.
  factory DownloadException.fromFileSystemException(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('no space') || message.contains('disk full')) {
      return DownloadException(
        DownloadErrorType.noSpace,
        error.toString(),
        originalError: error,
      );
    }
    if (message.contains('permission denied')) {
      return DownloadException(
        DownloadErrorType.filePermissions,
        error.toString(),
        originalError: error,
      );
    }
    return DownloadException(
      DownloadErrorType.unknown,
      error.toString(),
      originalError: error,
    );
  }
}
