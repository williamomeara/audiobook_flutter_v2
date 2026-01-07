import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class EpubDownloadResult {
  const EpubDownloadResult({required this.file, required this.bytes});

  final File file;
  final int bytes;
}

class EpubDownloadService {
  const EpubDownloadService({http.Client? client}) : _client = client;

  final http.Client? _client;

  // Timeout for individual stream chunks (30 seconds per chunk).
  // Large files may take longer, but if no data arrives in 30s, abort.
  static const Duration _streamTimeout = Duration(seconds: 30);

  Future<EpubDownloadResult> downloadToTemporaryFile({
    required Uri url,
    required String fileName,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    // Retry up to 3 times for transient connection errors
    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await _performDownload(url, fileName, onProgress);
      } catch (e) {
        final isTransient =
            e is SocketException ||
            e is TimeoutException ||
            e is HttpException && e.message.contains('Connection closed');
        final isLastAttempt = attempt == maxRetries;

        if (!isTransient || isLastAttempt) {
          rethrow;
        }

        if (kDebugMode) {
          debugPrint(
            'EpubDownloadService: download attempt $attempt failed, retrying... ($e)',
          );
        }

        // Exponential backoff: 1s, 2s, 3s
        await Future.delayed(Duration(seconds: attempt));
      }
    }

    throw StateError('Download failed after $maxRetries attempts');
  }

  Future<EpubDownloadResult> _performDownload(
    Uri url,
    String fileName,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  ) async {
    final tempDir = await getTemporaryDirectory();

    final safeName = _sanitizeFileName(fileName);
    final targetPath = '${tempDir.path}/$safeName';
    final partPath = '$targetPath.part';

    final partFile = File(partPath);
    if (await partFile.exists()) {
      try {
        await partFile.delete();
      } catch (_) {
        // ignore
      }
    }

    final client = _client ?? http.Client();
    try {
      final request = http.Request('GET', url);
      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Download failed (${response.statusCode})');
      }

      final length = response.contentLength;
      final total = (length != null && length > 0) ? length : null;
      final sink = partFile.openWrite();

      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(_streamTimeout)) {
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(received, total);
        }
      } on TimeoutException {
        throw HttpException(
          'Download timeout: no data received for ${_streamTimeout.inSeconds}s',
        );
      }

      await sink.flush();
      await sink.close();

      final finalFile = File(targetPath);
      if (await finalFile.exists()) {
        try {
          await finalFile.delete();
        } catch (_) {
          // ignore
        }
      }

      await partFile.rename(targetPath);
      return EpubDownloadResult(file: finalFile, bytes: received);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('EpubDownloadService: download failed: $e');
      }
      rethrow;
    } finally {
      if (_client == null) {
        try {
          client.close();
        } catch (_) {
          // ignore
        }
      }
    }
  }

  String _sanitizeFileName(String name) {
    final trimmed = name.trim().isEmpty ? 'book.epub' : name.trim();
    final withoutBadChars = trimmed.replaceAll(
      RegExp(r'[^A-Za-z0-9._\- ]+'),
      '_',
    );
    var out = withoutBadChars;
    if (!out.toLowerCase().endsWith('.epub')) {
      out = '$out.epub';
    }
    if (out.length > 160) {
      out = '${out.substring(0, 160)}.epub';
    }
    return out;
  }
}

final epubDownloadServiceProvider = Provider<EpubDownloadService>((ref) {
  return const EpubDownloadService();
});
