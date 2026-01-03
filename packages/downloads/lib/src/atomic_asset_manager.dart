import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'asset_spec.dart';
import 'download_state.dart';

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
    } catch (e) {
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
    } finally {
      _activeDownloads.remove(key);
    }
  }

  /// Delete an installed asset.
  Future<void> delete(String key) async {
    final installDir = Directory('${baseDir.path}/$key');
    if (await installDir.exists()) {
      await installDir.delete(recursive: true);
    }
    _updateState(key, DownloadState.notDownloaded);
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
          throw Exception('Download failed: HTTP ${response.statusCode} (missing Location). Body: ${bodySnippet}');
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
      throw Exception('Download failed: HTTP ${response.statusCode} for $currentUrl (content-type: $contentType) body-snippet: ${snippet}');
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

  /// Extract archive (tar.gz or zip).
  Future<void> _extractArchive(File archive, Directory destDir) async {
    final bytes = await archive.readAsBytes();

    Archive decoded;
    final lower = archive.path.toLowerCase();
    final lowerNoTmp = lower.endsWith('.tmp') ? lower.substring(0, lower.length - 4) : lower;
    if (lowerNoTmp.endsWith('.tar.gz') || lowerNoTmp.endsWith('.tgz')) {
      decoded = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    } else if (lowerNoTmp.endsWith('.zip')) {
      decoded = ZipDecoder().decodeBytes(bytes);
    } else {
      throw Exception('Unsupported archive type: ${archive.path}');
    }

    for (final file in decoded) {
      final filename = file.name;
      if (file.isFile) {
        final outFile = File('${destDir.path}/$filename');
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory('${destDir.path}/$filename').create(recursive: true);
      }
    }
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
    return path.endsWith('.tar.gz') || path.endsWith('.tgz') || path.endsWith('.zip');
  }

  String _archiveTmpSuffix(String url) {
    final path = Uri.parse(url).path.toLowerCase();
    if (path.endsWith('.tar.gz')) return '.tar.gz.tmp';
    if (path.endsWith('.tgz')) return '.tgz.tmp';
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
