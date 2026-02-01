import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Result of download validation.
class DownloadValidationResult {
  const DownloadValidationResult({
    required this.isValid,
    this.errorType,
    this.errorMessage,
    this.detectedContentType,
    this.actualSize,
    this.expectedSize,
    this.contentPreview,
  });

  /// Whether the download is valid.
  final bool isValid;

  /// Type of validation error if invalid.
  final DownloadValidationError? errorType;

  /// Human-readable error message.
  final String? errorMessage;

  /// Detected content type from file contents.
  final DetectedContentType? detectedContentType;

  /// Actual file size in bytes.
  final int? actualSize;

  /// Expected file size in bytes.
  final int? expectedSize;

  /// Preview of file content for debugging.
  final String? contentPreview;

  /// Factory for valid result.
  static const valid = DownloadValidationResult(isValid: true);

  /// Factory for invalid result.
  static DownloadValidationResult invalid({
    required DownloadValidationError type,
    required String message,
    DetectedContentType? detectedContentType,
    int? actualSize,
    int? expectedSize,
    String? contentPreview,
  }) =>
      DownloadValidationResult(
        isValid: false,
        errorType: type,
        errorMessage: message,
        detectedContentType: detectedContentType,
        actualSize: actualSize,
        expectedSize: expectedSize,
        contentPreview: contentPreview,
      );

  @override
  String toString() {
    if (isValid) return 'DownloadValidationResult(valid)';
    return 'DownloadValidationResult(invalid: $errorType - $errorMessage)';
  }
}

/// Types of download validation errors.
enum DownloadValidationError {
  /// File is empty.
  emptyFile,

  /// File is suspiciously small (likely error page).
  fileTooSmall,

  /// Content is HTML (error page from server).
  htmlErrorPage,

  /// Invalid archive magic bytes.
  invalidMagicBytes,

  /// Content-Type mismatch.
  contentTypeMismatch,

  /// Checksum mismatch.
  checksumMismatch,

  /// Generic validation failure.
  unknown,
}

/// Detected content type from file contents.
enum DetectedContentType {
  /// GZip compressed data.
  gzip,

  /// BZip2 compressed data.
  bzip2,

  /// ZIP archive.
  zip,

  /// HTML content (likely error page).
  html,

  /// Plain text.
  text,

  /// Unknown binary data.
  binary,
}

/// Validates downloaded files before extraction.
///
/// Implements multi-layer validation:
/// 1. Size validation (not empty, not suspiciously small)
/// 2. Content type detection (HTML error pages)
/// 3. Magic byte validation (archive format verification)
/// 4. Checksum validation (SHA256)
class DownloadValidator {
  const DownloadValidator();

  /// Validate a downloaded file.
  ///
  /// [file] - The downloaded file to validate.
  /// [expectedUrl] - Original download URL (for determining expected format).
  /// [expectedSize] - Expected file size in bytes (optional).
  /// [expectedSha256] - Expected SHA256 checksum (optional).
  Future<DownloadValidationResult> validate({
    required File file,
    required String expectedUrl,
    int? expectedSize,
    String? expectedSha256,
  }) async {
    // Check file exists
    if (!await file.exists()) {
      return DownloadValidationResult.invalid(
        type: DownloadValidationError.emptyFile,
        message: 'Downloaded file does not exist',
      );
    }

    // Read file header for validation
    final actualSize = await file.length();
    if (actualSize == 0) {
      return DownloadValidationResult.invalid(
        type: DownloadValidationError.emptyFile,
        message: 'Downloaded file is empty (0 bytes)',
        actualSize: 0,
        expectedSize: expectedSize,
      );
    }

    // Read first 512 bytes for content detection
    final headerBytes = await _readHeader(file, 512);
    final detectedType = detectContentType(headerBytes);
    final preview = _getContentPreview(headerBytes, detectedType);

    // Check for HTML error page
    if (detectedType == DetectedContentType.html) {
      return DownloadValidationResult.invalid(
        type: DownloadValidationError.htmlErrorPage,
        message: 'Server returned HTML error page instead of file. '
            'This usually means the file was not found, access was denied, '
            'or rate limiting occurred.',
        detectedContentType: detectedType,
        actualSize: actualSize,
        expectedSize: expectedSize,
        contentPreview: preview,
      );
    }

    // Check for suspiciously small file
    if (expectedSize != null && actualSize < (expectedSize * 0.5)) {
      return DownloadValidationResult.invalid(
        type: DownloadValidationError.fileTooSmall,
        message: 'Downloaded file is suspiciously small. '
            'Expected ~${_formatBytes(expectedSize)}, got ${_formatBytes(actualSize)}.',
        detectedContentType: detectedType,
        actualSize: actualSize,
        expectedSize: expectedSize,
        contentPreview: preview,
      );
    }

    // Validate magic bytes based on URL extension
    final expectedFormat = _getExpectedFormat(expectedUrl);
    if (expectedFormat != null) {
      final magicResult = validateMagicBytes(headerBytes, expectedFormat);
      if (!magicResult.isValid) {
        return DownloadValidationResult.invalid(
          type: DownloadValidationError.invalidMagicBytes,
          message: magicResult.errorMessage ?? 'Invalid archive format',
          detectedContentType: detectedType,
          actualSize: actualSize,
          expectedSize: expectedSize,
          contentPreview: preview,
        );
      }
    }

    // Validate checksum if provided
    if (expectedSha256 != null &&
        expectedSha256.isNotEmpty &&
        !expectedSha256.startsWith('placeholder')) {
      final actualHash = await computeSha256(file);
      if (actualHash != expectedSha256) {
        return DownloadValidationResult.invalid(
          type: DownloadValidationError.checksumMismatch,
          message: 'Checksum mismatch. Expected: $expectedSha256, got: $actualHash',
          detectedContentType: detectedType,
          actualSize: actualSize,
          expectedSize: expectedSize,
        );
      }
    }

    return DownloadValidationResult.valid;
  }

  /// Detect content type from file header bytes.
  DetectedContentType detectContentType(List<int> bytes) {
    if (bytes.isEmpty) return DetectedContentType.binary;

    // Check for GZip (0x1F 0x8B)
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      return DetectedContentType.gzip;
    }

    // Check for BZip2 (0x42 0x5A = "BZ")
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x5A) {
      return DetectedContentType.bzip2;
    }

    // Check for ZIP (0x50 0x4B = "PK")
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      return DetectedContentType.zip;
    }

    // Check for HTML
    if (_isHtmlContent(bytes)) {
      return DetectedContentType.html;
    }

    // Check for text
    if (_isTextContent(bytes)) {
      return DetectedContentType.text;
    }

    return DetectedContentType.binary;
  }

  /// Validate magic bytes match expected format.
  DownloadValidationResult validateMagicBytes(
    List<int> bytes,
    DetectedContentType expectedFormat,
  ) {
    if (bytes.length < 2) {
      return DownloadValidationResult.invalid(
        type: DownloadValidationError.invalidMagicBytes,
        message: 'File too small to validate format',
      );
    }

    switch (expectedFormat) {
      case DetectedContentType.gzip:
        if (bytes[0] != 0x1F || bytes[1] != 0x8B) {
          return DownloadValidationResult.invalid(
            type: DownloadValidationError.invalidMagicBytes,
            message: 'Invalid GZip format. Expected magic bytes [0x1F, 0x8B], '
                'got [0x${bytes[0].toRadixString(16).padLeft(2, '0')}, '
                '0x${bytes[1].toRadixString(16).padLeft(2, '0')}].',
          );
        }
        break;
      case DetectedContentType.bzip2:
        if (bytes[0] != 0x42 || bytes[1] != 0x5A) {
          return DownloadValidationResult.invalid(
            type: DownloadValidationError.invalidMagicBytes,
            message: 'Invalid BZip2 format. Expected magic bytes [0x42, 0x5A] ("BZ"), '
                'got [0x${bytes[0].toRadixString(16).padLeft(2, '0')}, '
                '0x${bytes[1].toRadixString(16).padLeft(2, '0')}].',
          );
        }
        break;
      case DetectedContentType.zip:
        if (bytes[0] != 0x50 || bytes[1] != 0x4B) {
          return DownloadValidationResult.invalid(
            type: DownloadValidationError.invalidMagicBytes,
            message: 'Invalid ZIP format. Expected magic bytes [0x50, 0x4B] ("PK"), '
                'got [0x${bytes[0].toRadixString(16).padLeft(2, '0')}, '
                '0x${bytes[1].toRadixString(16).padLeft(2, '0')}].',
          );
        }
        break;
      default:
        // No specific magic byte validation for other types
        break;
    }

    return DownloadValidationResult.valid;
  }

  /// Compute SHA256 hash of a file.
  Future<String> computeSha256(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// Compute chunked SHA256 hash during download (for streaming validation).
  Future<String> computeChunkedSha256(Stream<List<int>> stream) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);

    await for (final chunk in stream) {
      input.add(chunk);
    }
    input.close();

    return output.events.single.toString();
  }

  // Private helpers

  Future<Uint8List> _readHeader(File file, int maxBytes) async {
    final raf = await file.open();
    try {
      final length = await file.length();
      final bytesToRead = length < maxBytes ? length : maxBytes;
      return await raf.read(bytesToRead);
    } finally {
      await raf.close();
    }
  }

  bool _isHtmlContent(List<int> bytes) {
    if (bytes.length < 15) return false;

    final sampleSize = bytes.length < 500 ? bytes.length : 500;
    final sample = String.fromCharCodes(bytes.take(sampleSize));
    final lowerSample = sample.toLowerCase();

    return lowerSample.contains('<!doctype') ||
        lowerSample.contains('<html') ||
        lowerSample.contains('not found') ||
        lowerSample.contains('rate limit') ||
        lowerSample.contains('access denied') ||
        lowerSample.contains('<head>') ||
        lowerSample.contains('<body>');
  }

  bool _isTextContent(List<int> bytes) {
    // Check if mostly printable ASCII
    var printableCount = 0;
    final sampleSize = bytes.length < 200 ? bytes.length : 200;

    for (var i = 0; i < sampleSize; i++) {
      final b = bytes[i];
      if ((b >= 32 && b <= 126) || b == 9 || b == 10 || b == 13) {
        printableCount++;
      }
    }

    return printableCount > sampleSize * 0.9;
  }

  DetectedContentType? _getExpectedFormat(String url) {
    final path = Uri.parse(url).path.toLowerCase();
    if (path.endsWith('.tar.gz') || path.endsWith('.tgz')) {
      return DetectedContentType.gzip;
    }
    if (path.endsWith('.tar.bz2') || path.endsWith('.tbz2')) {
      return DetectedContentType.bzip2;
    }
    if (path.endsWith('.zip')) {
      return DetectedContentType.zip;
    }
    return null;
  }

  String _getContentPreview(List<int> bytes, DetectedContentType type) {
    if (bytes.isEmpty) return '(empty file)';

    if (type == DetectedContentType.html || type == DetectedContentType.text) {
      final sampleSize = bytes.length < 100 ? bytes.length : 100;
      final sample = String.fromCharCodes(bytes.take(sampleSize));
      return sample.length > 80 ? '${sample.substring(0, 80)}...' : sample;
    }

    // Show hex for binary content
    final hexBytes = bytes
        .take(20)
        .map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}')
        .join(', ');
    return 'Binary: [$hexBytes, ...]';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Helper class for chunked hash computation.
class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = [];

  @override
  void add(T event) => events.add(event);

  @override
  void close() {}
}
