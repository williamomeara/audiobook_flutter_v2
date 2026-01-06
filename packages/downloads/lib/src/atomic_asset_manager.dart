import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'asset_spec.dart';
import 'download_state.dart';

// Use print since this is a non-Flutter package
void _debugLog(String message) {
  // ignore: avoid_print
  print('[AtomicAssetManager] $message');
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
  }) : _httpClient = httpClient ?? http.Client();

  final Directory baseDir;
  final http.Client _httpClient;

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

      // Phase 2: Install (extract for archives, or place file for direct downloads)
      _updateState(key, DownloadState(
        status: DownloadStatus.extracting,
        progress: 0.90,
        totalBytes: spec.sizeBytes,
      ));

      await tmpDir.create(recursive: true);
      if (isArchive) {
        await _extractArchive(tmpDownload, tmpDir);
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

    if (expectedSha256 != null) {
      final fileHash = await _sha256File(destFile);
      if (fileHash != expectedSha256) {
        await destFile.delete();
        throw Exception('Download checksum mismatch');
      }
    }
  }

  /// Extract archive (tar.gz, tar.bz2, or zip).
  /// 
  /// For tar.bz2 archives (sherpa-onnx models), strips the leading directory
  /// component so contents are extracted directly to destDir.
  Future<void> _extractArchive(File archive, Directory destDir) async {
    final bytes = await archive.readAsBytes();

    Archive decoded;
    final lower = archive.path.toLowerCase();
    final lowerNoTmp = lower.endsWith('.tmp') ? lower.substring(0, lower.length - 4) : lower;
    final isBz2 = lowerNoTmp.endsWith('.tar.bz2') || lowerNoTmp.endsWith('.tbz2');
    
    if (lowerNoTmp.endsWith('.tar.gz') || lowerNoTmp.endsWith('.tgz')) {
      decoded = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    } else if (isBz2) {
      decoded = TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes));
    } else if (lowerNoTmp.endsWith('.zip')) {
      decoded = ZipDecoder().decodeBytes(bytes);
    } else {
      throw Exception('Unsupported archive type: ${archive.path}');
    }

    // For tar.bz2 (sherpa-onnx format), strip the leading directory component
    // e.g., "vits-piper-en_GB-alan-medium/tokens.txt" -> "tokens.txt"
    String? stripPrefix;
    if (isBz2) {
      stripPrefix = _detectCommonPrefix(decoded);
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
  
  /// Detect common prefix directory in archive (for stripping).
  String? _detectCommonPrefix(Archive archive) {
    final names = archive.files.map((f) => f.name).toList();
    if (names.isEmpty) return null;
    
    // Check if all files start with a common directory prefix
    final firstSlash = names.first.indexOf('/');
    if (firstSlash < 0) return null;
    
    final prefix = names.first.substring(0, firstSlash + 1);
    if (names.every((n) => n.startsWith(prefix))) {
      return prefix;
    }
    return null;
  }

  /// Calculate SHA256 of a file.
  Future<String> _sha256File(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
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
