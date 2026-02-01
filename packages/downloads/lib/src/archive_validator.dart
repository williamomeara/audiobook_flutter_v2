import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Result of archive validation.
class ArchiveValidationResult {
  const ArchiveValidationResult({
    required this.isValid,
    this.errorType,
    this.errorMessage,
    this.entryCount,
    this.totalUncompressedSize,
    this.suspiciousEntries,
  });

  /// Whether the archive is valid.
  final bool isValid;

  /// Type of validation error if invalid.
  final ArchiveValidationError? errorType;

  /// Human-readable error message.
  final String? errorMessage;

  /// Number of entries in the archive.
  final int? entryCount;

  /// Total uncompressed size in bytes.
  final int? totalUncompressedSize;

  /// List of suspicious entry paths (if any).
  final List<String>? suspiciousEntries;

  /// Factory for valid result.
  static ArchiveValidationResult valid({
    required int entryCount,
    required int totalUncompressedSize,
  }) =>
      ArchiveValidationResult(
        isValid: true,
        entryCount: entryCount,
        totalUncompressedSize: totalUncompressedSize,
      );

  /// Factory for invalid result.
  static ArchiveValidationResult invalid({
    required ArchiveValidationError type,
    required String message,
    List<String>? suspiciousEntries,
  }) =>
      ArchiveValidationResult(
        isValid: false,
        errorType: type,
        errorMessage: message,
        suspiciousEntries: suspiciousEntries,
      );

  @override
  String toString() {
    if (isValid) return 'ArchiveValidationResult(valid, $entryCount entries)';
    return 'ArchiveValidationResult(invalid: $errorType - $errorMessage)';
  }
}

/// Types of archive validation errors.
enum ArchiveValidationError {
  /// Archive is corrupted or unreadable.
  corrupted,

  /// Archive contains path traversal attempts.
  pathTraversal,

  /// Archive contains suspiciously large files.
  suspiciousSize,

  /// Archive is empty.
  emptyArchive,

  /// Archive format not supported.
  unsupportedFormat,

  /// Archive contains suspicious entries.
  suspiciousEntries,
}

/// Validates archive structure before extraction.
///
/// Performs pre-extraction validation to detect:
/// - Corrupted archives
/// - Path traversal attacks (../ in paths)
/// - Suspiciously large files (zip bombs)
/// - Empty archives
/// - Invalid entry names
class ArchiveValidator {
  const ArchiveValidator({
    this.maxUncompressedSize = 5 * 1024 * 1024 * 1024, // 5GB default
    this.maxEntryCount = 100000, // 100k entries default
  });

  /// Maximum allowed uncompressed size in bytes.
  final int maxUncompressedSize;

  /// Maximum allowed number of entries.
  final int maxEntryCount;

  /// Validate archive before extraction.
  ///
  /// [archiveFile] - The archive file to validate.
  /// [archivePath] - Path hint for determining format (e.g., ".tar.gz").
  ///
  /// This performs a lightweight scan of the archive structure without
  /// fully extracting all contents, making it fast enough to run before
  /// every extraction.
  Future<ArchiveValidationResult> validate({
    required File archiveFile,
    required String archivePath,
  }) async {
    try {
      final bytes = await archiveFile.readAsBytes();
      return validateBytes(bytes: bytes, archivePath: archivePath);
    } catch (e) {
      return ArchiveValidationResult.invalid(
        type: ArchiveValidationError.corrupted,
        message: 'Failed to read archive file: $e',
      );
    }
  }

  /// Validate archive bytes.
  ArchiveValidationResult validateBytes({
    required Uint8List bytes,
    required String archivePath,
  }) {
    if (bytes.isEmpty) {
      return ArchiveValidationResult.invalid(
        type: ArchiveValidationError.emptyArchive,
        message: 'Archive file is empty',
      );
    }

    try {
      final lower = archivePath.toLowerCase();
      final lowerNoTmp =
          lower.endsWith('.tmp') ? lower.substring(0, lower.length - 4) : lower;

      Archive archive;

      if (lowerNoTmp.endsWith('.tar.gz') || lowerNoTmp.endsWith('.tgz')) {
        final decompressed = GZipDecoder().decodeBytes(bytes);
        archive = TarDecoder().decodeBytes(decompressed);
      } else if (lowerNoTmp.endsWith('.tar.bz2') ||
          lowerNoTmp.endsWith('.tbz2')) {
        final decompressed = BZip2Decoder().decodeBytes(bytes);
        archive = TarDecoder().decodeBytes(decompressed);
      } else if (lowerNoTmp.endsWith('.zip')) {
        archive = ZipDecoder().decodeBytes(bytes);
      } else {
        return ArchiveValidationResult.invalid(
          type: ArchiveValidationError.unsupportedFormat,
          message: 'Unsupported archive format: $archivePath',
        );
      }

      return _validateArchiveStructure(archive);
    } on FormatException catch (e) {
      // Handle the specific FormatException that was causing problems
      return ArchiveValidationResult.invalid(
        type: ArchiveValidationError.corrupted,
        message: 'Archive format error: ${e.message}. '
            'The archive may be corrupted or contain invalid encoding.',
      );
    } catch (e) {
      return ArchiveValidationResult.invalid(
        type: ArchiveValidationError.corrupted,
        message: 'Failed to parse archive: $e',
      );
    }
  }

  ArchiveValidationResult _validateArchiveStructure(Archive archive) {
    if (archive.isEmpty) {
      return ArchiveValidationResult.invalid(
        type: ArchiveValidationError.emptyArchive,
        message: 'Archive contains no files',
      );
    }

    if (archive.length > maxEntryCount) {
      return ArchiveValidationResult.invalid(
        type: ArchiveValidationError.suspiciousSize,
        message:
            'Archive contains too many entries: ${archive.length} > $maxEntryCount',
      );
    }

    final suspiciousEntries = <String>[];
    var totalUncompressedSize = 0;

    for (final entry in archive) {
      final name = entry.name;

      // Check for path traversal
      if (_hasPathTraversal(name)) {
        suspiciousEntries.add(name);
      }

      // Check for suspicious entry names
      if (_isSuspiciousName(name)) {
        suspiciousEntries.add(name);
      }

      // Track total uncompressed size
      if (entry.isFile) {
        totalUncompressedSize += entry.size;
        if (totalUncompressedSize > maxUncompressedSize) {
          return ArchiveValidationResult.invalid(
            type: ArchiveValidationError.suspiciousSize,
            message:
                'Archive uncompressed size exceeds limit: $totalUncompressedSize > $maxUncompressedSize',
          );
        }
      }
    }

    if (suspiciousEntries.isNotEmpty) {
      return ArchiveValidationResult.invalid(
        type: ArchiveValidationError.pathTraversal,
        message:
            'Archive contains suspicious entries: ${suspiciousEntries.take(5).join(", ")}',
        suspiciousEntries: suspiciousEntries,
      );
    }

    return ArchiveValidationResult.valid(
      entryCount: archive.length,
      totalUncompressedSize: totalUncompressedSize,
    );
  }

  /// Check for path traversal attempts.
  bool _hasPathTraversal(String path) {
    // Normalize path and check for ..
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');

    for (final segment in segments) {
      if (segment == '..') return true;
      if (segment == '.') continue;

      // Check for encoded traversal
      if (segment.contains('%2e') || segment.contains('%2E')) return true;
    }

    // Check for absolute paths
    if (normalized.startsWith('/')) return true;

    // Check for Windows absolute paths
    if (normalized.length >= 2 && normalized[1] == ':') return true;

    return false;
  }

  /// Check for suspicious file names.
  bool _isSuspiciousName(String name) {
    final lower = name.toLowerCase();

    // Check for null bytes (indicates binary injection attempt)
    if (name.contains('\x00')) return true;

    // Check for very long names
    if (name.length > 500) return true;

    // Check for hidden files that shouldn't be in archives
    final segments = name.split('/');
    for (final segment in segments) {
      // Skip normal hidden files like .manifest
      if (segment == '.manifest') continue;
      if (segment == '.DS_Store') continue;

      // Flag unusual hidden files
      if (segment.startsWith('...')) return true;
    }

    // Check for potential shell injection in names
    if (lower.contains(r'$(') || lower.contains(r'`')) return true;

    return false;
  }
}
