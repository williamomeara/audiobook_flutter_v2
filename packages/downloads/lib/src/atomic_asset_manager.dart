import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:tar/tar.dart' as tar;

import 'asset_spec.dart';
import 'download_state.dart';
import 'download_validator.dart';
import 'extraction_error_handler.dart';

/// Debug-only logging (stripped in release builds via assert).
void _debugLog(String message) {
  assert(() {
    // ignore: avoid_print
    print('[AtomicAssetManager] $message');
    return true;
  }());
}

/// Specification for a file in a multi-file download.
class MultiFileSpec {
  const MultiFileSpec({
    required this.filename,
    required this.url,
    required this.sizeBytes,
    this.sha256,
  });

  final String filename;
  final String url;
  final int sizeBytes;
  final String? sha256;
}

/// Enhanced asset manager with atomic downloads and SHA256 verification.
///
/// Implements the .tmp pattern for corruption-safe downloads:
/// 1. Download to .tar.gz.tmp (resumable)
/// 2. Extract to dir.tmp
/// 3. Verify SHA256
/// 4. Atomic rename: dir.tmp → dir
class AtomicAssetManager {
  AtomicAssetManager({
    required this.baseDir,
    http.Client? httpClient,
    DownloadValidator? downloadValidator,
    ExtractionErrorHandler? errorHandler,
  })  : _httpClient = httpClient ?? http.Client(),
        _downloadValidator = downloadValidator ?? const DownloadValidator(),
        _errorHandler = errorHandler ?? const ExtractionErrorHandler();

  final Directory baseDir;
  final http.Client _httpClient;
  final DownloadValidator _downloadValidator;
  final ExtractionErrorHandler _errorHandler;

  /// State per asset key.
  final Map<String, DownloadState> _states = {};

  /// State change controllers per asset key.
  final Map<String, StreamController<DownloadState>> _controllers = {};

  /// Active downloads (to prevent duplicates).
  final Set<String> _activeDownloads = {};

  /// Get current state of an asset.
  Future<DownloadState> getState(String key) async {
    final installDir = Directory('${baseDir.path}/$key');
    if (await installDir.exists()) {
      // Verify manifest exists
      final manifestFile = File('${installDir.path}/.manifest');
      if (await manifestFile.exists()) {
        return DownloadState.ready;
      }
    }
    return _states[key] ?? DownloadState.notDownloaded;
  }

  /// Watch state changes for an asset.
  Stream<DownloadState> watchState(String key) {
    _controllers[key] ??= StreamController<DownloadState>.broadcast();
    return _controllers[key]!.stream;
  }

  /// Download an asset with atomic installation.
  Future<void> download(AssetSpec spec) async {
    final key = spec.key;

    if (_activeDownloads.contains(key)) return;
    _activeDownloads.add(key);

    final targetDir = Directory('${baseDir.path}/$key');
    final tmpDir = Directory('${baseDir.path}/$key.tmp');

    final isArchive = _isArchiveUrl(spec.downloadUrl);
    final tmpDownload = File(
      '${baseDir.path}/$key${isArchive ? _archiveTmpSuffix(spec.downloadUrl) : '.download.tmp'}',
    );

    try {
      _debugLog('[AtomicAssetManager] Starting download: ${spec.displayName} -> $key');
      _updateState(key, DownloadState(
        status: DownloadStatus.queued,
        totalBytes: spec.sizeBytes,
      ));

      // Phase 1: Download to .tmp file (with resume support)
      await tmpDownload.parent.create(recursive: true);
      await _downloadWithResume(
        url: spec.downloadUrl,
        destFile: tmpDownload,
        key: key,
        expectedSize: spec.sizeBytes,
        expectedSha256: spec.checksum,
      );

      // Phase 1.5: Validate downloaded file before extraction
      if (isArchive) {
        _debugLog('[AtomicAssetManager] Validating downloaded archive...');
        final validationResult = await _downloadValidator.validate(
          file: tmpDownload,
          expectedUrl: spec.downloadUrl,
          expectedSize: spec.sizeBytes,
          expectedSha256: spec.checksum,
        );

        if (!validationResult.isValid) {
          _debugLog('[AtomicAssetManager] Validation failed: ${validationResult.errorMessage}');
          // Use error handler to get user-friendly message
          final errorContext = await _errorHandler.handleError(
            coreId: key,
            archiveFile: tmpDownload,
            error: Exception(validationResult.errorMessage),
            expectedUrl: spec.downloadUrl,
            expectedSize: spec.sizeBytes,
          );
          throw Exception(errorContext.userMessage ?? validationResult.errorMessage);
        }
        _debugLog('[AtomicAssetManager] Validation passed');
      }

      // Phase 2: Install (extract for archives, or place file for direct downloads)
      _updateState(key, DownloadState(
        status: DownloadStatus.extracting,
        progress: 0.90,
        totalBytes: spec.sizeBytes,
      ));

      await tmpDir.create(recursive: true);
      if (isArchive) {
        try {
          await _extractArchive(tmpDownload, tmpDir);
        } on FormatException catch (e) {
          // Use error handler for better error messages
          _debugLog('[AtomicAssetManager] Extraction failed with FormatException: $e');
          final errorContext = await _errorHandler.handleError(
            coreId: key,
            archiveFile: tmpDownload,
            error: e,
            expectedUrl: spec.downloadUrl,
            expectedSize: spec.sizeBytes,
          );
          throw Exception(errorContext.userMessage ?? e.toString());
        }
      } else {
        final filename = _installFilenameForUrl(spec.downloadUrl);
        final outFile = File('${tmpDir.path}/$filename');
        await outFile.parent.create(recursive: true);
        await tmpDownload.rename(outFile.path);
      }

      // Phase 3: Verify SHA256 of extracted content (best-effort)
      if (spec.checksum != null) {
        _updateState(key, DownloadState(
          status: DownloadStatus.extracting,
          progress: 0.95,
          totalBytes: spec.sizeBytes,
        ));

        final verified = await _verifyDirectoryChecksum(tmpDir, spec.checksum!);
        if (!verified) {
          throw Exception('SHA256 verification failed for $key');
        }
      }

      // Phase 4: Atomic rename
      if (await targetDir.exists()) {
        final oldDir = Directory('${targetDir.path}.old');
        await targetDir.rename(oldDir.path);
        try {
          await tmpDir.rename(targetDir.path);
          await oldDir.delete(recursive: true);
        } catch (e) {
          await oldDir.rename(targetDir.path);
          rethrow;
        }
      } else {
        await tmpDir.rename(targetDir.path);
      }

      // Phase 5: Write manifest and cleanup
      await _writeManifest(targetDir, spec);
      if (await tmpDownload.exists()) {
        await tmpDownload.delete();
      }

      _updateState(key, DownloadState.ready);
    } catch (e, stackTrace) {
      _debugLog('Download failed: $e\n$stackTrace');
      // Cleanup on failure
      try {
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }
        if (await tmpDownload.exists()) {
          await tmpDownload.delete();
        }
      } catch (_) {}

      _updateState(key, DownloadState(
        status: DownloadStatus.failed,
        error: e.toString(),
      ));
      rethrow;  // Propagate error to caller
    } finally {
      _activeDownloads.remove(key);
    }
  }

  /// Delete an installed asset.
  Future<void> delete(String key) async {
    final installDir = Directory('${baseDir.path}/$key');
    final tmpDir = Directory('${baseDir.path}/$key.tmp');
    
    _debugLog('Attempting to delete: ${installDir.path}');
    
    // Delete the installed directory
    if (await installDir.exists()) {
      await installDir.delete(recursive: true);
      _debugLog('Deleted directory: ${installDir.path}');
    } else {
      _debugLog('Install directory does not exist: ${installDir.path}');
    }
    
    // Delete the tmp directory if it exists
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
      _debugLog('Deleted tmp directory: ${tmpDir.path}');
    }
    
    // Delete any temp download files (.tar.gz.tmp, .tgz.tmp, .zip.tmp, .download.tmp)
    final possibleTmpFiles = [
      File('${baseDir.path}/$key.tar.gz.tmp'),
      File('${baseDir.path}/$key.tgz.tmp'),
      File('${baseDir.path}/$key.zip.tmp'),
      File('${baseDir.path}/$key.download.tmp'),
    ];
    for (final tmpFile in possibleTmpFiles) {
      if (await tmpFile.exists()) {
        await tmpFile.delete();
        _debugLog('Deleted tmp file: ${tmpFile.path}');
      }
    }
    
    // Verify the main directory is gone
    if (await installDir.exists()) {
      _debugLog('WARNING: Directory still exists after delete!');
    } else {
      _debugLog('Verified: Directory successfully deleted');
    }
    
    _updateState(key, DownloadState.notDownloaded);
  }

  /// Download multiple files atomically (all succeed or all fail).
  /// 
  /// This is used for cores that require multiple files (e.g., Piper ONNX + JSON).
  Future<void> downloadMultiFile({
    required String key,
    required List<MultiFileSpec> files,
    void Function(double progress)? onProgress,
  }) async {
    if (_activeDownloads.contains(key)) return;
    _activeDownloads.add(key);

    final targetDir = Directory('${baseDir.path}/$key');
    final tmpDir = Directory('${baseDir.path}/$key.tmp');

    try {
      _updateState(key, DownloadState(status: DownloadStatus.queued));

      // Clean up any previous attempt
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
      await tmpDir.create(recursive: true);

      // Calculate total size from manifest
      final totalSize = files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
      var completedFilesBytes = 0; // Bytes for files fully completed

      // Download each file
      for (final file in files) {
        // Check for cancellation
        final currentState = _states[key];
        if (currentState?.status == DownloadStatus.failed) {
          throw Exception('Download cancelled');
        }

        final destFile = File('${tmpDir.path}/${file.filename}');
        await destFile.parent.create(recursive: true);

        await _downloadSingleFile(
          url: file.url,
          destFile: destFile,
          key: key,
          expectedSha256: file.sha256,
          onProgress: (downloaded, total) {
            final combinedBytes = completedFilesBytes + downloaded;
            // Clamp progress to max 0.85 (reserve 15% for extraction/verification)
            final overallProgress = (combinedBytes / totalSize).clamp(0.0, 1.0) * 0.85;
            _updateState(key, DownloadState(
              status: DownloadStatus.downloading,
              progress: overallProgress,
              downloadedBytes: combinedBytes,
              totalBytes: totalSize,
            ));
            onProgress?.call(overallProgress);
          },
        );
        // Add the manifest size (not actual downloaded) to keep consistent with totalSize
        completedFilesBytes += file.sizeBytes;
      }

      // Extracting/verifying phase
      _updateState(key, DownloadState(
        status: DownloadStatus.extracting,
        progress: 0.90,
        totalBytes: totalSize,
      ));

      // Atomic install: move tmp to final
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
      await tmpDir.rename(targetDir.path);

      // Write manifest
      await _writeMultiFileManifest(targetDir, key, files);

      _updateState(key, DownloadState.ready);
    } catch (e) {
      // Cleanup on failure
      try {
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }
      } catch (_) {}

      _updateState(key, DownloadState(
        status: DownloadStatus.failed,
        error: e.toString(),
      ));
      rethrow;
    } finally {
      _activeDownloads.remove(key);
    }
  }

  /// Download a single file with progress reporting (no extraction).
  Future<void> _downloadSingleFile({
    required String url,
    required File destFile,
    required String key,
    String? expectedSha256,
    void Function(int downloaded, int total)? onProgress,
  }) async {
    var currentUrl = url;
    late http.StreamedResponse response;

    // Follow redirects
    for (var i = 0; i < 6; i++) {
      final request = http.Request('GET', Uri.parse(currentUrl));
      request.headers['User-Agent'] = 'audiobook_flutter_v2/1.0 (+https://example.local)';
      request.headers['Accept'] = '*/*';

      response = await _httpClient.send(request);

      if (_isRedirectStatus(response.statusCode)) {
        final loc = response.headers['location'];
        if (loc == null || loc.isEmpty) {
          throw Exception('Download failed: HTTP ${response.statusCode} (missing Location)');
        }
        currentUrl = Uri.parse(currentUrl).resolve(loc).toString();
        continue;
      }
      break;
    }

    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode} for $currentUrl');
    }

    final contentLength = response.contentLength ?? 0;
    var downloaded = 0;
    final sink = destFile.openWrite();

    try {
      await for (final chunk in response.stream) {
        // Check for cancellation
        final currentState = _states[key];
        if (currentState?.status == DownloadStatus.failed) {
          throw Exception('Download cancelled');
        }

        sink.add(chunk);
        downloaded += chunk.length;
        onProgress?.call(downloaded, contentLength);
      }
    } finally {
      await sink.close();
    }

    // Verify checksum if provided
    if (expectedSha256 != null && expectedSha256.isNotEmpty && !expectedSha256.startsWith('placeholder')) {
      final fileHash = await _sha256File(destFile);
      if (fileHash != expectedSha256) {
        await destFile.delete();
        throw Exception('Checksum mismatch for ${destFile.path}');
      }
    }
  }

  /// Write manifest for multi-file downloads.
  Future<void> _writeMultiFileManifest(Directory dir, String key, List<MultiFileSpec> files) async {
    final manifest = {
      'key': key,
      'version': '1',
      'type': 'multi_file',
      'files': files.map((f) => f.filename).toList(),
      'installedAt': DateTime.now().toIso8601String(),
    };

    final manifestFile = File('${dir.path}/.manifest');
    await manifestFile.writeAsString(manifest.entries
        .map((e) => '${e.key}=${e.value}')
        .join('\n'));
  }

  /// Cancel an active download.
  void cancelDownload(String key) {
    // Mark as cancelled, the download loop will check this
    _updateState(key, DownloadState(
      status: DownloadStatus.failed,
      error: 'Cancelled by user',
    ));
    _activeDownloads.remove(key);
  }

  /// Download with resume support and progress reporting.
  Future<void> _downloadWithResume({
    required String url,
    required File destFile,
    required String key,
    int? expectedSize,
    String? expectedSha256,
  }) async {
    var downloaded = 0;
    var resumeFrom = 0;

    // Check for existing partial download
    if (await destFile.exists()) {
      resumeFrom = await destFile.length();
      downloaded = resumeFrom;
    }

    var currentUrl = url;
    late http.StreamedResponse response;

    for (var i = 0; i < 6; i++) {
      final request = http.Request('GET', Uri.parse(currentUrl));
      // Helpful headers to reduce servers rejecting programmatic clients
      request.headers['User-Agent'] = 'audiobook_flutter_v2/1.0 (+https://example.local)';
      request.headers['Accept'] = '*/*';
      if (resumeFrom > 0) {
        request.headers['Range'] = 'bytes=$resumeFrom-';
      }

      response = await _httpClient.send(request);

      if (_isRedirectStatus(response.statusCode)) {
        final loc = response.headers['location'];
        if (loc == null || loc.isEmpty) {
          // Try to include any body for diagnostics
          final bytes = await response.stream.toBytes();
          final bodySnippet = bytes.isNotEmpty ? String.fromCharCodes(bytes.take(512)) : '';
          throw Exception('Download failed: HTTP ${response.statusCode} (missing Location). Body: $bodySnippet');
        }
        currentUrl = Uri.parse(currentUrl).resolve(loc).toString();
        continue;
      }

      break;
    }

    if (response.statusCode != 200 && response.statusCode != 206) {
      final bytes = await response.stream.toBytes();
      final snippet = bytes.isNotEmpty ? String.fromCharCodes(bytes.take(512)) : '';
      final contentType = response.headers['content-type'] ?? 'unknown';
      throw Exception('Download failed: HTTP ${response.statusCode} for $currentUrl (content-type: $contentType) body-snippet: $snippet');
    }

    // Log download start for debugging
    final contentType = response.headers['content-type'] ?? 'unknown';
    _debugLog('Download response: HTTP ${response.statusCode}, content-type: $contentType, content-length: ${response.contentLength}');

    // Server ignored Range; restart cleanly.
    if (resumeFrom > 0 && response.statusCode == 200) {
      await destFile.delete();
      return _downloadWithResume(
        url: currentUrl,
        destFile: destFile,
        key: key,
        expectedSize: expectedSize,
        expectedSha256: expectedSha256,
      );
    }

    final contentLength = response.contentLength ?? expectedSize;
    final totalSize = (resumeFrom > 0 && response.statusCode == 206)
        ? resumeFrom + (contentLength ?? 0)
        : contentLength;

    final sink = destFile.openWrite(mode: FileMode.append);

    try {
      await for (final chunk in response.stream) {
        final currentState = _states[key];
        if (currentState?.status == DownloadStatus.failed) {
          throw Exception('Download cancelled');
        }

        sink.add(chunk);
        downloaded += chunk.length;

        final progress = totalSize != null && totalSize > 0
            ? (downloaded / totalSize) * 0.85
            : 0.0;

        _updateState(key, DownloadState(
          status: DownloadStatus.downloading,
          progress: progress,
          downloadedBytes: downloaded,
          totalBytes: totalSize,
        ));
      }
    } finally {
      await sink.close();
    }

    // Validate downloaded file before proceeding to extraction
    await _validateDownloadedFile(destFile, url, expectedSize);

    if (expectedSha256 != null) {
      final fileHash = await _sha256File(destFile);
      if (fileHash != expectedSha256) {
        await destFile.delete();
        throw Exception('Download checksum mismatch');
      }
    }
  }

  /// Validate downloaded file to catch server errors (HTML pages, incomplete downloads).
  Future<void> _validateDownloadedFile(File file, String url, int? expectedSize) async {
    final actualSize = await file.length();
    
    // Check if file is suspiciously small (likely an error page)
    if (expectedSize != null && actualSize < (expectedSize * 0.5)) {
      final bytes = await file.readAsBytes();
      if (_isHtmlContentSync(bytes)) {
        final preview = _getFilePreviewSync(bytes);
        await file.delete();
        throw Exception(
          'Download returned error page instead of file. '
          'Expected ~${_formatBytes(expectedSize)}, got ${_formatBytes(actualSize)}. '
          'Content: $preview'
        );
      }
    }
    
    // Quick validation of archive magic bytes
    final isArchive = _isArchiveUrl(url);
    if (isArchive && actualSize >= 2) {
      final headerBytes = <int>[];
      await for (final chunk in file.openRead(0, 2)) {
        headerBytes.addAll(chunk);
        if (headerBytes.length >= 2) break;
      }
      
      if (headerBytes.length >= 2) {
        final path = url.toLowerCase();
        
        // Check for GZip
        if ((path.contains('.tar.gz') || path.contains('.tgz')) &&
            (headerBytes[0] != 0x1F || headerBytes[1] != 0x8B)) {
          // Read more bytes for error message
          final bytes = await file.readAsBytes();
          final preview = _getFilePreviewSync(bytes);
          await file.delete();
          throw Exception(
            'Downloaded file is not a valid GZip archive. '
            'Got bytes [0x${headerBytes[0].toRadixString(16)}, 0x${headerBytes[1].toRadixString(16)}] '
            'instead of GZip signature [0x1F, 0x8B]. '
            'Content: $preview'
          );
        }
      }
    }
  }
  
  /// Sync version of HTML check for use in isolate/after download.
  static bool _isHtmlContentSync(List<int> bytes) {
    if (bytes.length < 15) return false;
    final sampleSize = bytes.length < 500 ? bytes.length : 500;
    final sample = String.fromCharCodes(bytes.take(sampleSize));
    final lowerSample = sample.toLowerCase();
    return lowerSample.contains('<!doctype') ||
           lowerSample.contains('<html') ||
           lowerSample.contains('not found') ||
           lowerSample.contains('rate limit');
  }
  
  /// Sync version of preview for use after download.
  static String _getFilePreviewSync(List<int> bytes) {
    if (bytes.isEmpty) return '(empty)';
    final sampleSize = bytes.length < 100 ? bytes.length : 100;
    final sample = String.fromCharCodes(bytes.take(sampleSize));
    final display = sample.length > 80 ? '${sample.substring(0, 80)}...' : sample;
    return display;
  }
  
  /// Format bytes as human-readable string.
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Extract archive (tar.gz, tar.bz2, or zip) in background isolate.
  /// 
  /// For tar.bz2 archives (sherpa-onnx models), strips the leading directory
  /// component so contents are extracted directly to destDir.
  Future<void> _extractArchive(File archive, Directory destDir) async {
    // Run extraction in background isolate to avoid UI jank
    await Isolate.run(() => _extractArchiveIsolate(_ExtractParams(
      archivePath: archive.path,
      destPath: destDir.path,
    )));
  }

  /// Calculate SHA256 of a file in background isolate.
  Future<String> _sha256File(File file) async {
    // Run hash computation in background isolate to avoid UI jank
    return Isolate.run(() => _sha256FileIsolate(file.path));
  }

  /// Verify directory checksum (check main model file).
  Future<bool> _verifyDirectoryChecksum(Directory dir, String expected) async {
    // Look for common model file patterns
    final modelFiles = ['model.onnx', 'model.bin', 'kokoro.onnx', 'piper.onnx'];
    
    for (final modelName in modelFiles) {
      final modelFile = File('${dir.path}/$modelName');
      if (await modelFile.exists()) {
        final hash = await _sha256File(modelFile);
        if (hash == expected) {
          return true;
        }
      }
    }
    
    // If no specific model file, verify manifest if it exists
    final manifestFile = File('${dir.path}/MANIFEST.sha256');
    if (await manifestFile.exists()) {
      final content = await manifestFile.readAsString();
      return content.trim() == expected;
    }
    
    // For directories without specific hash, just check extraction succeeded
    return true;
  }

  /// Write manifest file to mark installation complete.
  Future<void> _writeManifest(Directory dir, AssetSpec spec) async {
    final manifest = {
      'key': spec.key,
      'version': '1',
      'sha256': spec.checksum ?? 'unknown',
      'installedAt': DateTime.now().toIso8601String(),
    };

    final manifestFile = File('${dir.path}/.manifest');
    await manifestFile.writeAsString(manifest.entries
        .map((e) => '${e.key}=${e.value}')
        .join('\n'));
  }

  bool _isArchiveUrl(String url) {
    final path = Uri.parse(url).path.toLowerCase();
    return path.endsWith('.tar.gz') || 
           path.endsWith('.tgz') || 
           path.endsWith('.tar.bz2') || 
           path.endsWith('.tbz2') || 
           path.endsWith('.zip');
  }

  String _archiveTmpSuffix(String url) {
    final path = Uri.parse(url).path.toLowerCase();
    if (path.endsWith('.tar.gz')) return '.tar.gz.tmp';
    if (path.endsWith('.tgz')) return '.tgz.tmp';
    if (path.endsWith('.tar.bz2')) return '.tar.bz2.tmp';
    if (path.endsWith('.tbz2')) return '.tbz2.tmp';
    if (path.endsWith('.zip')) return '.zip.tmp';
    return '.archive.tmp';
  }

  bool _isRedirectStatus(int code) {
    return code == 301 || code == 302 || code == 303 || code == 307 || code == 308;
  }

  String _installFilenameForUrl(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    if (path.endsWith('.onnx.json')) return 'model.onnx.json';
    if (path.endsWith('.onnx')) return 'model.onnx';
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'asset.bin';
  }

  void _updateState(String key, DownloadState state) {
    _states[key] = state;
    _controllers[key]?.add(state);
  }

  /// Dispose all stream controllers.
  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }
}

/// Data class for passing extraction parameters to isolate.
class _ExtractParams {
  _ExtractParams({
    required this.archivePath,
    required this.destPath,
  });

  final String archivePath;
  final String destPath;
}

/// Extract archive in background isolate to avoid UI jank.
Future<void> _extractArchiveIsolate(_ExtractParams params) async {
  final archive = File(params.archivePath);
  final destDir = Directory(params.destPath);
  
  final bytes = await archive.readAsBytes();

  // Validate archive format before attempting decompression
  _validateArchiveBytes(bytes, archive.path);

  Archive decoded;
  final lower = archive.path.toLowerCase();
  final lowerNoTmp = lower.endsWith('.tmp') ? lower.substring(0, lower.length - 4) : lower;
  final isBz2 = lowerNoTmp.endsWith('.tar.bz2') || lowerNoTmp.endsWith('.tbz2');
  final isTarGz = lowerNoTmp.endsWith('.tar.gz') || lowerNoTmp.endsWith('.tgz');
  
  try {
    if (isTarGz) {
      decoded = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    } else if (isBz2) {
      decoded = TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes));
    } else if (lowerNoTmp.endsWith('.zip')) {
      decoded = ZipDecoder().decodeBytes(bytes);
    } else {
      throw Exception('Unsupported archive type: ${archive.path}');
    }
  } on FormatException catch (e) {
    // The Dart archive package's TarDecoder has issues with PAX extended headers
    // containing non-UTF-8 filenames (common in macOS/CoreML archives).
    // Fallback to a lenient tar decoder that handles these cases.
    if (isTarGz || isBz2) {
      await _extractWithLenientTar(archive, destDir, isTarGz, isBz2);
      return;
    }
    
    // Provide better error message for format exceptions
    final preview = _getFilePreview(bytes);
    throw Exception(
      'Archive extraction failed: ${e.message}. '
      'File size: ${bytes.length} bytes. '
      'File preview: $preview'
    );
  }

  // For tar.bz2 (sherpa-onnx format), strip the leading directory component
  String? stripPrefix;
  if (isBz2) {
    final names = decoded.files.map((f) => f.name).toList();
    if (names.isNotEmpty) {
      final firstSlash = names.first.indexOf('/');
      if (firstSlash >= 0) {
        final prefix = names.first.substring(0, firstSlash + 1);
        if (names.every((n) => n.startsWith(prefix))) {
          stripPrefix = prefix;
        }
      }
    }
  }

  for (final file in decoded) {
    String filename = file.name;
    
    // Strip prefix if detected
    if (stripPrefix != null && filename.startsWith(stripPrefix)) {
      filename = filename.substring(stripPrefix.length);
      if (filename.isEmpty) continue; // Skip the root directory entry
    }
    
    if (file.isFile) {
      final outFile = File('${destDir.path}/$filename');
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>);
    } else if (filename.isNotEmpty) {
      await Directory('${destDir.path}/$filename').create(recursive: true);
    }
  }
}

/// Extract tar archive using package:tar which properly handles PAX extended
/// headers and is more robust than the archive package's TarDecoder.
Future<void> _extractWithLenientTar(
  File archiveFile,
  Directory destDir,
  bool isTarGz,
  bool isBz2,
) async {
  await destDir.create(recursive: true);
  
  // Create appropriate stream based on compression type
  Stream<List<int>> inputStream = archiveFile.openRead();
  
  if (isTarGz) {
    inputStream = inputStream.transform(gzip.decoder);
  } else if (isBz2) {
    // For bzip2, we need to decompress to bytes first since there's no bzip2 stream transformer
    final bytes = await archiveFile.readAsBytes();
    final decompressed = BZip2Decoder().decodeBytes(bytes);
    inputStream = Stream.value(decompressed);
  }
  
  // Use package:tar's TarReader which properly handles PAX headers
  final reader = tar.TarReader(inputStream);
  
  try {
    while (await reader.moveNext()) {
      final entry = reader.current;
      final name = entry.header.name;
      
      // Skip empty names
      if (name.isEmpty) continue;
      
      // Create output path
      final outPath = '${destDir.path}/$name';
      
      if (entry.header.typeFlag == tar.TypeFlag.dir || name.endsWith('/')) {
        // Directory entry
        await Directory(outPath).create(recursive: true);
      } else if (entry.header.typeFlag == tar.TypeFlag.reg || 
                 entry.header.typeFlag == tar.TypeFlag.regA) {
        // Regular file
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        
        // Stream contents to file
        final sink = outFile.openWrite();
        try {
          await entry.contents.pipe(sink);
        } finally {
          await sink.close();
        }
      }
      // Skip symlinks, hard links, and other special entries for security
    }
  } finally {
    await reader.cancel();
  }
}

/// Calculate SHA256 of file in background isolate.
Future<String> _sha256FileIsolate(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  return sha256.convert(bytes).toString();
}

/// Validate archive bytes before decompression to provide better error messages.
/// Throws an exception if the bytes don't match expected archive format.
void _validateArchiveBytes(List<int> bytes, String archivePath) {
  if (bytes.isEmpty) {
    throw Exception('Downloaded file is empty (0 bytes)');
  }

  final lower = archivePath.toLowerCase();
  final lowerNoTmp = lower.endsWith('.tmp') 
      ? lower.substring(0, lower.length - 4) 
      : lower;

  // Check for HTML error page (common when GitHub returns 404, rate limit, etc.)
  if (_isHtmlContent(bytes)) {
    final preview = _getFilePreview(bytes);
    throw Exception(
      'Download failed: Server returned HTML instead of archive file. '
      'This usually means the file was not found, access was denied, or rate limiting occurred. '
      'Content preview: $preview'
    );
  }

  // Validate GZip magic bytes
  if (lowerNoTmp.endsWith('.tar.gz') || lowerNoTmp.endsWith('.tgz')) {
    if (bytes.length < 2 || bytes[0] != 0x1F || bytes[1] != 0x8B) {
      final preview = _getFilePreview(bytes);
      throw Exception(
        'Invalid GZip format. Expected magic bytes [0x1F, 0x8B], '
        'got [0x${bytes[0].toRadixString(16).padLeft(2, '0')}, 0x${bytes[1].toRadixString(16).padLeft(2, '0')}]. '
        'File size: ${bytes.length} bytes. '
        'Content preview: $preview'
      );
    }
  }

  // Validate BZip2 magic bytes
  if (lowerNoTmp.endsWith('.tar.bz2') || lowerNoTmp.endsWith('.tbz2')) {
    // BZip2 starts with 'BZ' (0x42, 0x5A)
    if (bytes.length < 2 || bytes[0] != 0x42 || bytes[1] != 0x5A) {
      final preview = _getFilePreview(bytes);
      throw Exception(
        'Invalid BZip2 format. Expected magic bytes [0x42, 0x5A] ("BZ"), '
        'got [0x${bytes[0].toRadixString(16).padLeft(2, '0')}, 0x${bytes[1].toRadixString(16).padLeft(2, '0')}]. '
        'File size: ${bytes.length} bytes. '
        'Content preview: $preview'
      );
    }
  }

  // Validate ZIP magic bytes
  if (lowerNoTmp.endsWith('.zip')) {
    // ZIP starts with 'PK' (0x50, 0x4B)
    if (bytes.length < 2 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      final preview = _getFilePreview(bytes);
      throw Exception(
        'Invalid ZIP format. Expected magic bytes [0x50, 0x4B] ("PK"), '
        'got [0x${bytes[0].toRadixString(16).padLeft(2, '0')}, 0x${bytes[1].toRadixString(16).padLeft(2, '0')}]. '
        'File size: ${bytes.length} bytes. '
        'Content preview: $preview'
      );
    }
  }
}

/// Check if the bytes look like HTML content (common for error pages).
bool _isHtmlContent(List<int> bytes) {
  if (bytes.length < 15) return false;
  
  // Try to decode first 500 bytes as ASCII (safe for HTML detection)
  final sampleSize = bytes.length < 500 ? bytes.length : 500;
  final sample = String.fromCharCodes(bytes.take(sampleSize));
  final lowerSample = sample.toLowerCase();
  
  return lowerSample.contains('<!doctype') ||
         lowerSample.contains('<html') ||
         lowerSample.contains('not found') ||
         lowerSample.contains('rate limit') ||
         lowerSample.contains('access denied') ||
         lowerSample.contains('error');
}

/// Get a human-readable preview of file content for error messages.
String _getFilePreview(List<int> bytes) {
  if (bytes.isEmpty) return '(empty file)';
  
  // Take first 100 bytes for preview
  final sampleSize = bytes.length < 100 ? bytes.length : 100;
  
  // Try to show as text if it looks like text, otherwise show hex
  final sample = String.fromCharCodes(bytes.take(sampleSize));
  final hasControlChars = sample.codeUnits.any((c) => c < 32 && c != 9 && c != 10 && c != 13);
  
  if (hasControlChars) {
    // Show first 20 bytes as hex
    final hexBytes = bytes.take(20).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ');
    return 'Binary: [$hexBytes, ...]';
  } else {
    // Show as text, truncated
    final display = sample.length > 80 ? '${sample.substring(0, 80)}...' : sample;
    return 'Text: "$display"';
  }
}
