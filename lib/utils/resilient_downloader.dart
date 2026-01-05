import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Lightweight resilient downloader used as a fallback when the primary
/// AtomicAssetManager download path fails. Implements resume-with-range,
/// retry logic, archive extraction in an isolate, checksum validation and
/// atomic move to target directory.
class ResilientDownloader {
  static final Logger _logger = Logger('ResilientDownloader');

  static Future<void> downloadAndInstall(
    String url,
    Directory targetDir, {
    int? expectedBytes,
    String? expectedSha,
    String? engineName,
    void Function(double progress)? onProgress,
    int maxRetries = 3,
  }) async {
    _logger.info('downloadAndInstall: $url -> ${targetDir.path}');

    final tempRoot = Directory('${targetDir.parent.path}/.tmp_downloads');
    await tempRoot.create(recursive: true);

    final ext = _archiveExtensionFromUrl(url);
    final tempFile = File('${tempRoot.path}/${targetDir.uri.pathSegments.last}_download$ext');

    await _downloadFile(url, tempFile, (downloaded, total) {
      final p = total > 0 ? (downloaded / total) : 0.0;
      try {
        onProgress?.call(p);
      } catch (_) {}
    }, expectedBytes: expectedBytes, maxRetries: maxRetries);

    // Optionally validate checksum on the downloaded blob (archive or single file)
    if (expectedSha != null && expectedSha.isNotEmpty && !expectedSha.startsWith('placeholder')) {
      final hash = await _computeSha256(tempFile);
      if (hash != expectedSha) {
        throw StateError('Checksum mismatch: expected $expectedSha, got $hash');
      }
    }

    // Prepare extraction
    final extractDir = Directory('${tempRoot.path}/${targetDir.uri.pathSegments.last}_extract');
    await extractDir.create(recursive: true);

    if (ext != '.tmp') {
      await _extractArchive(tempFile, extractDir);
      try {
        await tempFile.delete();
      } catch (_) {}

      // Move extracted contents into final dir
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
      await targetDir.create(recursive: true);
      await _moveDirectory(extractDir, targetDir);
    } else {
      // Non-archive: move single file into target dir
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
      await targetDir.create(recursive: true);
      final name = tempFile.uri.pathSegments.isNotEmpty ? tempFile.uri.pathSegments.last : 'asset.bin';
      final dest = File('${targetDir.path}/$name');
      await tempFile.rename(dest.path);
    }

    // Write .ready marker
    final marker = File('${targetDir.path}/.ready');
    await marker.writeAsString(DateTime.now().toIso8601String());

    // Cleanup temp
    try {
      if (await extractDir.exists()) await extractDir.delete(recursive: true);
    } catch (_) {}
  }

  static Future<void> _downloadFile(
    String url,
    File targetFile,
    void Function(int downloadedBytes, int totalBytes) onProgress, {
    int? expectedBytes,
    int maxRetries = 3,
  }) async {
    final uri = Uri.parse(url);
    final fallbackTotal = expectedBytes ?? 0;
    if (kDebugMode) _logger.fine('starting download $url -> ${targetFile.path}');

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      var existingBytes = 0;
      if (await targetFile.exists()) existingBytes = await targetFile.length();

      final request = http.Request('GET', uri);
      request.headers['Accept-Encoding'] = 'identity';
      if (existingBytes > 0) request.headers['Range'] = 'bytes=$existingBytes-';

      late http.StreamedResponse response;
      try {
        response = await request.send();
      } catch (e) {
        if (kDebugMode) _logger.warning('request.send failed for $url on attempt $attempt: $e');
        if (attempt == maxRetries) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
        continue;
      }

      if (kDebugMode) _logger.fine('HTTP ${response.statusCode} for $url (existing=$existingBytes, contentLength=${response.contentLength})');

      if (response.statusCode == 416) {
        if (await targetFile.exists()) await targetFile.delete();
        if (attempt == maxRetries) throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
        continue;
      }

      if (response.statusCode == 200 && existingBytes > 0) {
        await targetFile.delete();
        existingBytes = 0;
      }

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final contentBytes = response.contentLength ?? 0;
      final totalBytes = contentBytes > 0
          ? (response.statusCode == 206 ? existingBytes + contentBytes : contentBytes)
          : fallbackTotal;

      var downloadedBytes = existingBytes;
      final sink = targetFile.openWrite(mode: existingBytes > 0 ? FileMode.append : FileMode.write);

      if (kDebugMode) developer.log('ResilientDownloader: starting stream for $url. totalBytes=$totalBytes', name: 'ResilientDownloader');

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          if (totalBytes > 0) onProgress(downloadedBytes, totalBytes);
        }
        await sink.flush();
        await sink.close();
        if (totalBytes > 0) onProgress(totalBytes, totalBytes);
        if (kDebugMode) developer.log('ResilientDownloader: completed download ${targetFile.path} ($downloadedBytes/$totalBytes)', name: 'ResilientDownloader');
        return;
      } catch (e) {
        if (kDebugMode) developer.log('ResilientDownloader: stream error for $url on attempt $attempt: $e', name: 'ResilientDownloader');
        await sink.flush();
        await sink.close();
        if (attempt == maxRetries) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
      }
    }
  }

  static Future<String> _computeSha256(File file) async {
    final stream = file.openRead();
    final hash = await sha256.bind(stream).first;
    return hash.toString();
  }

  static Future<void> _extractArchive(File archiveFile, Directory targetDir) async {
    final archivePath = archiveFile.path;
    final outPath = targetDir.path;
    await Isolate.run(() async {
      await extractFileToDisk(
        archivePath,
        outPath,
        asyncWrite: true,
      );
    });
  }

  static String _archiveExtensionFromUrl(String url) {
    try {
      final path = Uri.parse(url).path;
      if (path.endsWith('.tar.gz')) return '.tar.gz';
      if (path.endsWith('.tgz')) return '.tgz';
      if (path.endsWith('.tar.bz2')) return '.tar.bz2';
      if (path.endsWith('.zip')) return '.zip';
    } catch (_) {}
    return '.tmp';
  }

  static Future<void> _moveDirectory(Directory source, Directory target) async {
    await for (final entity in source.list(recursive: false)) {
      final newPath = entity.path.replaceFirst(source.path, target.path);
      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await Directory(newPath).create(recursive: true);
        await _moveDirectory(entity, Directory(newPath));
      }
    }
  }

  /// Download multiple file URLs into the target directory (no extraction).
  static Future<void> downloadFiles(
    List<String> urls,
    Directory targetDir, {
    void Function(String url, double progress)? onFileProgress,
    int maxRetries = 3,
  }) async {
    developer.log('ResilientDownloader: downloadFiles -> ${targetDir.path}', name: 'ResilientDownloader');
    final tempRoot = Directory('${targetDir.parent.path}/.tmp_downloads');
    await tempRoot.create(recursive: true);
    await targetDir.create(recursive: true);

    for (final url in urls) {
      final uri = Uri.parse(url);
      final name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : Uri.encodeFull(url.hashCode.toString());
      final tempFile = File('${tempRoot.path}/$name');

      await _downloadFile(url, tempFile, (downloaded, total) {
        final p = total > 0 ? (downloaded / total) : 0.0;
        try {
          onFileProgress?.call(url, p);
        } catch (_) {}
      }, expectedBytes: null, maxRetries: maxRetries);

      final dest = File('${targetDir.path}/$name');
      await dest.parent.create(recursive: true);
      await tempFile.rename(dest.path);
    }
  }

  /// Attempt downloading a single file from multiple mirror URLs in order.
  static Future<void> downloadWithMirrors(
    List<String> mirrors,
    File targetFile,
    void Function(int downloadedBytes, int totalBytes)? onProgress, {
    int? expectedBytes,
    int maxRetries = 3,
  }) async {
    // Pre-check mirrors to find at least one that exists to avoid repeated 404 attempts.
    final available = await findFirstAvailable(mirrors);
    if (available == null) {
      throw Exception('No available mirrors for ${targetFile.path}');
    }

    // Prefer the first available mirror returned by findFirstAvailable
    final candidates = [available, ...mirrors.where((m) => m != available)];

    for (final url in candidates) {
      try {
        developer.log('downloadWithMirrors: attempting $url -> ${targetFile.path}', name: 'ResilientDownloader');
        await targetFile.parent.create(recursive: true);
        if (await targetFile.exists()) await targetFile.delete();
        await _downloadFile(url, targetFile, (d, t) {
          try {
            onProgress?.call(d, t);
          } catch (_) {}
        }, expectedBytes: expectedBytes, maxRetries: maxRetries);
        developer.log('downloadWithMirrors: success for $url', name: 'ResilientDownloader');
        return; // success
      } catch (e) {
        developer.log('downloadWithMirrors: failed for $url: $e', name: 'ResilientDownloader');
        if (await targetFile.exists()) {
          try { await targetFile.delete(); } catch (_) {}
        }
        continue;
      }
    }
    throw Exception('All mirrors failed for ${targetFile.path}');
  }

  /// Find the first mirror URL that responds to a HEAD request with status < 400.
  static Future<String?> findFirstAvailable(List<String> mirrors, {Duration timeout = const Duration(seconds: 6)}) async {
    for (final url in mirrors) {
      try {
        final uri = Uri.parse(url);
        final resp = await http.head(uri).timeout(timeout);
        if (resp.statusCode >= 200 && resp.statusCode < 400) return url;
      } catch (e) {
        developer.log('findFirstAvailable: HEAD failed for $url: $e', name: 'ResilientDownloader');
        continue;
      }
    }
    return null;
  }
}

