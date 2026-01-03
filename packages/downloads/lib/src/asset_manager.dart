import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'dart:developer' as developer;

import 'asset_spec.dart';
import 'download_state.dart';

/// Interface for managing voice asset downloads.
abstract interface class VoiceAssetManager {
  /// Get current state of an asset.
  Future<DownloadState> getState(AssetKey key);

  /// Watch state changes for an asset.
  Stream<DownloadState> watchState(AssetKey key);

  /// Download an asset.
  Future<void> download(AssetSpec spec);

  /// Delete an asset.
  Future<void> delete(AssetSpec spec);

  /// Resolve remote file size.
  Future<int?> resolveRemoteSizeBytes(Uri uri);
}

/// Implementation of VoiceAssetManager.
class FileAssetManager implements VoiceAssetManager {
  FileAssetManager({required this.baseDir});

  /// Base directory for downloads.
  final Directory baseDir;

  /// State per asset key.
  final Map<String, DownloadState> _states = {};

  /// State change controllers per asset key.
  final Map<String, StreamController<DownloadState>> _controllers = {};

  /// Active downloads (to prevent duplicates).
  final Set<String> _activeDownloads = {};

  @override
  Future<DownloadState> getState(AssetKey key) async {
    // Check if already installed
    final installDir = Directory('${baseDir.path}/${key.value}');
    if (await installDir.exists()) {
      return DownloadState.ready;
    }
    return _states[key.value] ?? DownloadState.notDownloaded;
  }

  @override
  Stream<DownloadState> watchState(AssetKey key) {
    _controllers[key.value] ??= StreamController<DownloadState>.broadcast();
    return _controllers[key.value]!.stream;
  }

  @override
  Future<void> download(AssetSpec spec) async {
    final key = spec.key;

    // Prevent duplicate downloads
    if (_activeDownloads.contains(key)) return;
    _activeDownloads.add(key);

    try {
      _updateState(key, DownloadState(
        status: DownloadStatus.queued,
        totalBytes: spec.sizeBytes,
      ));

      // Create temp file
      await baseDir.create(recursive: true);
      final tempFile = File('${baseDir.path}/$key.tmp');

      developer.log('Starting download for key=$key url=${spec.downloadUrl} tmp=${tempFile.path}', name: 'FileAssetManager');

      // Download
      await _downloadFile(
        url: spec.downloadUrl,
        destFile: tempFile,
        key: key,
        expectedSize: spec.sizeBytes,
      );

      // Extract if archive
      _updateState(key, DownloadState(
        status: DownloadStatus.extracting,
        progress: 0.95,
        totalBytes: spec.sizeBytes,
      ));

      final installDir = Directory('${baseDir.path}/${spec.key}');
      await installDir.create(recursive: true);

      if (spec.downloadUrl.endsWith('.zip') || spec.downloadUrl.endsWith('.tar.gz')) {
        await _extractArchive(tempFile, installDir, stripPrefix: '${spec.key}/');
        await tempFile.delete();
      } else {
        // Just move the file. Use the final path segment of the URL as filename when possible.
        final uri = Uri.parse(spec.downloadUrl);
        final filename = uri.pathSegments.isNotEmpty ? Uri.decodeComponent(uri.pathSegments.last) : spec.key;
        final destFile = File('${installDir.path}/$filename');
        await tempFile.rename(destFile.path);
      }

      _updateState(key, DownloadState.ready);
    } catch (e) {
      _updateState(key, DownloadState(
        status: DownloadStatus.failed,
        error: e.toString(),
      ));
    } finally {
      _activeDownloads.remove(key);
    }
  }

  @override
  Future<void> delete(AssetSpec spec) async {
    final installDir = Directory('${baseDir.path}/${spec.key}');
    if (await installDir.exists()) {
      await installDir.delete(recursive: true);
    }
    _updateState(spec.key, DownloadState.notDownloaded);
  }

  @override
  Future<int?> resolveRemoteSizeBytes(Uri uri) async {
    try {
      final response = await http.head(uri);
      final contentLength = response.headers['content-length'];
      if (contentLength != null) {
        return int.tryParse(contentLength);
      }
    } catch (_) {
      // Ignore errors
    }
    return null;
  }

  void _updateState(String key, DownloadState state) {
    _states[key] = state;
    _controllers[key]?.add(state);
  }

  Future<void> _downloadFile({
    required String url,
    required File destFile,
    required String key,
    int? expectedSize,
  }) async {
    final client = http.Client();
    try {
      developer.log('HTTP GET: $url', name: 'FileAssetManager');
      final streamedResponse = await client.send(http.Request('GET', Uri.parse(url)));
      
      // Handle redirects manually
      http.StreamedResponse response = streamedResponse;
      developer.log('Received HTTP ${response.statusCode} for $url', name: 'FileAssetManager');
      if (response.statusCode == 302 || response.statusCode == 301) {
        final redirectUrl = response.headers['location'];
        developer.log('Redirect to $redirectUrl', name: 'FileAssetManager');
        if (redirectUrl != null) {
          client.close();
          return _downloadFile(
            url: redirectUrl,
            destFile: destFile,
            key: key,
            expectedSize: expectedSize,
          );
        }
      }

      if (response.statusCode != 200) {
        developer.log('Download failed with status ${response.statusCode} for $url', name: 'FileAssetManager');
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? expectedSize;
      var downloaded = 0;

      final sink = destFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloaded += chunk.length;

          final progress = contentLength != null && contentLength > 0
              ? downloaded / contentLength
              : 0.0;

          _updateState(key, DownloadState(
            status: DownloadStatus.downloading,
            progress: progress * 0.9, // Reserve 10% for extraction
            downloadedBytes: downloaded,
            totalBytes: contentLength,
          ));
        }
      } finally {
        await sink.close();
      }

      developer.log('Finished download for key=$key, bytes=$downloaded, expected=$contentLength -> ${destFile.path}', name: 'FileAssetManager');
    } finally {
      client.close();
    }
  }

  Future<void> _extractArchive(File archive, Directory destDir, {String? stripPrefix}) async {
    developer.log('Extracting ${archive.path} -> ${destDir.path} (stripPrefix=$stripPrefix)', name: 'FileAssetManager');
    final bytes = await archive.readAsBytes();

    Archive decoded;
    if (archive.path.endsWith('.zip')) {
      decoded = ZipDecoder().decodeBytes(bytes);
    } else if (archive.path.endsWith('.tar.gz') || archive.path.endsWith('.tgz')) {
      decoded = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    } else {
      // Assume zip
      decoded = ZipDecoder().decodeBytes(bytes);
    }

    var total = 0;
    var filesExtracted = 0;
    for (final file in decoded) {
      total += 1;
      var filename = file.name;
      // If requested, strip a common leading path prefix (useful when archives contain a top-level folder)
      if (stripPrefix != null && filename.startsWith(stripPrefix)) {
        filename = filename.substring(stripPrefix.length);
      }
      if (filename.isEmpty) continue;

      if (file.isFile) {
        filesExtracted += 1;
        final outFile = File('${destDir.path}/$filename');
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory('${destDir.path}/$filename').create(recursive: true);
      }
    }
    developer.log('Extracted archive ${archive.path}: entries=$total files=$filesExtracted', name: 'FileAssetManager');
  }

  /// Dispose all stream controllers.
  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }
}
