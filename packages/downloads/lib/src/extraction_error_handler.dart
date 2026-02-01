import 'dart:io';

import 'download_validator.dart';
import 'archive_validator.dart';

/// Recommended recovery action for extraction errors.
enum DownloadRecoveryAction {
  /// Retry the download from where it left off (resume).
  retry,

  /// Delete the corrupted file and download again from scratch.
  deleteAndRetry,

  /// Abort - the error is not recoverable.
  abort,

  /// User action required (e.g., check network, free disk space).
  userAction,
}

/// Context about an extraction error.
class ExtractionErrorContext {
  const ExtractionErrorContext({
    required this.coreId,
    required this.archivePath,
    required this.error,
    this.errorOffset,
    this.fileSize,
    this.validationResult,
    this.archiveValidationResult,
    this.suggestedAction,
    this.userMessage,
    this.technicalDetails,
  });

  /// ID of the core being downloaded.
  final String coreId;

  /// Path to the archive file.
  final String archivePath;

  /// Original error that occurred.
  final Object error;

  /// Byte offset where the error occurred (if applicable).
  final int? errorOffset;

  /// Size of the archive file.
  final int? fileSize;

  /// Result of download validation (if performed).
  final DownloadValidationResult? validationResult;

  /// Result of archive validation (if performed).
  final ArchiveValidationResult? archiveValidationResult;

  /// Suggested recovery action.
  final DownloadRecoveryAction? suggestedAction;

  /// User-friendly error message.
  final String? userMessage;

  /// Technical details for debugging.
  final String? technicalDetails;

  @override
  String toString() {
    return 'ExtractionErrorContext($coreId: $error, action: $suggestedAction)';
  }
}

/// Handles extraction errors gracefully.
///
/// Analyzes extraction failures to determine:
/// - Root cause (corrupted download, HTML error page, format mismatch)
/// - Suggested recovery action
/// - User-friendly error messages
/// - Technical details for logging
class ExtractionErrorHandler {
  const ExtractionErrorHandler({
    DownloadValidator? validator,
  }) : _validator = validator ?? const DownloadValidator();

  final DownloadValidator _validator;

  /// Handle an extraction error and provide recovery context.
  Future<ExtractionErrorContext> handleError({
    required String coreId,
    required File archiveFile,
    required Object error,
    String? expectedUrl,
    int? expectedSize,
  }) async {
    final archivePath = archiveFile.path;
    int? fileSize;
    DownloadValidationResult? validationResult;

    // Gather information about the file
    try {
      if (await archiveFile.exists()) {
        fileSize = await archiveFile.length();
      }
    } catch (_) {}

    // Try to validate the downloaded file
    if (expectedUrl != null) {
      try {
        validationResult = await _validator.validate(
          file: archiveFile,
          expectedUrl: expectedUrl,
          expectedSize: expectedSize,
        );
      } catch (_) {}
    }

    // Analyze the error
    final errorString = error.toString();
    final errorLower = errorString.toLowerCase();

    // Handle FormatException specifically
    if (error is FormatException) {
      return _handleFormatException(
        coreId: coreId,
        archivePath: archivePath,
        error: error,
        fileSize: fileSize,
        validationResult: validationResult,
      );
    }

    // Handle HTML error pages (detected by validator)
    if (validationResult != null &&
        validationResult.errorType == DownloadValidationError.htmlErrorPage) {
      return ExtractionErrorContext(
        coreId: coreId,
        archivePath: archivePath,
        error: error,
        fileSize: fileSize,
        validationResult: validationResult,
        suggestedAction: DownloadRecoveryAction.deleteAndRetry,
        userMessage:
            'Download failed: The server returned an error page instead of the file. '
            'Please check your internet connection and try again.',
        technicalDetails:
            'Server returned HTML content: ${validationResult.contentPreview}',
      );
    }

    // Handle checksum mismatch
    if (validationResult != null &&
        validationResult.errorType == DownloadValidationError.checksumMismatch) {
      return ExtractionErrorContext(
        coreId: coreId,
        archivePath: archivePath,
        error: error,
        fileSize: fileSize,
        validationResult: validationResult,
        suggestedAction: DownloadRecoveryAction.deleteAndRetry,
        userMessage:
            'Download corrupted: The file checksum does not match. '
            'This can happen due to network issues. Please try again.',
        technicalDetails: validationResult.errorMessage,
      );
    }

    // Handle file too small
    if (validationResult != null &&
        validationResult.errorType == DownloadValidationError.fileTooSmall) {
      return ExtractionErrorContext(
        coreId: coreId,
        archivePath: archivePath,
        error: error,
        fileSize: fileSize,
        validationResult: validationResult,
        suggestedAction: DownloadRecoveryAction.deleteAndRetry,
        userMessage:
            'Download incomplete: The file is smaller than expected. '
            'Please try again with a stable connection.',
        technicalDetails: validationResult.errorMessage,
      );
    }

    // Handle disk space errors
    if (errorLower.contains('no space') ||
        errorLower.contains('disk full') ||
        errorLower.contains('enospc')) {
      return ExtractionErrorContext(
        coreId: coreId,
        archivePath: archivePath,
        error: error,
        fileSize: fileSize,
        suggestedAction: DownloadRecoveryAction.userAction,
        userMessage:
            'Not enough disk space to extract the voice files. '
            'Please free up some space and try again.',
        technicalDetails: errorString,
      );
    }

    // Handle permission errors
    if (errorLower.contains('permission denied') ||
        errorLower.contains('eacces')) {
      return ExtractionErrorContext(
        coreId: coreId,
        archivePath: archivePath,
        error: error,
        fileSize: fileSize,
        suggestedAction: DownloadRecoveryAction.abort,
        userMessage:
            'Permission denied while extracting files. '
            'Please restart the app and try again.',
        technicalDetails: errorString,
      );
    }

    // Handle network errors during streaming extraction
    if (errorLower.contains('socket') ||
        errorLower.contains('connection') ||
        errorLower.contains('network')) {
      return ExtractionErrorContext(
        coreId: coreId,
        archivePath: archivePath,
        error: error,
        fileSize: fileSize,
        suggestedAction: DownloadRecoveryAction.retry,
        userMessage:
            'Network error during download. '
            'Please check your connection and try again.',
        technicalDetails: errorString,
      );
    }

    // Default: suggest delete and retry for unknown errors
    return ExtractionErrorContext(
      coreId: coreId,
      archivePath: archivePath,
      error: error,
      fileSize: fileSize,
      validationResult: validationResult,
      suggestedAction: DownloadRecoveryAction.deleteAndRetry,
      userMessage: 'Download failed. Please try again.',
      technicalDetails: errorString,
    );
  }

  ExtractionErrorContext _handleFormatException({
    required String coreId,
    required String archivePath,
    required FormatException error,
    int? fileSize,
    DownloadValidationResult? validationResult,
  }) {
    final message = error.message;
    final offset = error.offset;

    // Check if this is the "Unexpected extension byte" error
    if (message.contains('Unexpected extension byte') ||
        message.contains('extension byte')) {
      // This typically means the file is not valid UTF-8 (binary in text field)
      // or the archive contains data that looks like a PAX header but isn't

      // If validation showed HTML, report that
      if (validationResult?.errorType == DownloadValidationError.htmlErrorPage) {
        return ExtractionErrorContext(
          coreId: coreId,
          archivePath: archivePath,
          error: error,
          errorOffset: offset,
          fileSize: fileSize,
          validationResult: validationResult,
          suggestedAction: DownloadRecoveryAction.deleteAndRetry,
          userMessage:
              'Download failed: The server returned an error page instead of the voice file. '
              'This can happen when the file is temporarily unavailable. Please try again later.',
          technicalDetails:
              'FormatException at offset $offset: ${error.message}. '
              'Content preview: ${validationResult?.contentPreview}',
        );
      }

      // Otherwise, it's likely a corrupt download
      return ExtractionErrorContext(
        coreId: coreId,
        archivePath: archivePath,
        error: error,
        errorOffset: offset,
        fileSize: fileSize,
        validationResult: validationResult,
        suggestedAction: DownloadRecoveryAction.deleteAndRetry,
        userMessage:
            'Download corrupted at byte $offset. '
            'Please delete and try again.',
        technicalDetails:
            'FormatException: ${error.message}. '
            'File size: ${fileSize ?? "unknown"}. '
            'Detected content: ${validationResult?.detectedContentType ?? "unknown"}.',
      );
    }

    // Handle "Invalid end" errors (truncated archive)
    if (message.contains('Invalid end') || message.contains('truncated')) {
      return ExtractionErrorContext(
        coreId: coreId,
        archivePath: archivePath,
        error: error,
        errorOffset: offset,
        fileSize: fileSize,
        suggestedAction: DownloadRecoveryAction.deleteAndRetry,
        userMessage:
            'Download incomplete: The file was cut off during transfer. '
            'Please try again.',
        technicalDetails: 'FormatException: ${error.message}',
      );
    }

    // Default FormatException handling
    return ExtractionErrorContext(
      coreId: coreId,
      archivePath: archivePath,
      error: error,
      errorOffset: offset,
      fileSize: fileSize,
      validationResult: validationResult,
      suggestedAction: DownloadRecoveryAction.deleteAndRetry,
      userMessage:
          'Archive format error. The download may be corrupted. Please try again.',
      technicalDetails: 'FormatException: ${error.message}',
    );
  }

  /// Suggest recovery action based on error type.
  DownloadRecoveryAction suggestRecoveryAction(Object error) {
    final errorString = error.toString().toLowerCase();

    // Retry for transient errors
    if (errorString.contains('timeout') ||
        errorString.contains('socket') ||
        errorString.contains('connection reset')) {
      return DownloadRecoveryAction.retry;
    }

    // User action for resource issues
    if (errorString.contains('no space') ||
        errorString.contains('disk full') ||
        errorString.contains('permission denied')) {
      return DownloadRecoveryAction.userAction;
    }

    // Abort for unrecoverable errors
    if (errorString.contains('not found') ||
        errorString.contains('404') ||
        errorString.contains('403')) {
      return DownloadRecoveryAction.abort;
    }

    // Default to delete and retry
    return DownloadRecoveryAction.deleteAndRetry;
  }
}
