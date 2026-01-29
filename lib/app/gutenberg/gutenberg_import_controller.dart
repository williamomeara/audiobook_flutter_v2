import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../infra/gutendex/gutendex_models.dart';
import '../app_paths.dart';
import '../library_controller.dart';

enum GutenbergImportPhase { idle, downloading, importing, done, failed }

class GutenbergImportEntry {
  const GutenbergImportEntry({
    required this.phase,
    required this.progress,
    required this.message,
  });

  final GutenbergImportPhase phase;
  final double? progress;
  final String? message;

  bool get isBusy =>
      phase == GutenbergImportPhase.downloading ||
      phase == GutenbergImportPhase.importing;

  GutenbergImportEntry copyWith({
    GutenbergImportPhase? phase,
    double? progress,
    String? message,
    bool clearMessage = false,
  }) {
    return GutenbergImportEntry(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  static const idle = GutenbergImportEntry(
    phase: GutenbergImportPhase.idle,
    progress: null,
    message: null,
  );
}

class GutenbergImportState {
  const GutenbergImportState({required this.entries});

  final Map<int, GutenbergImportEntry> entries;

  GutenbergImportEntry entryFor(int gutenbergId) =>
      entries[gutenbergId] ?? GutenbergImportEntry.idle;

  GutenbergImportState copyWith({Map<int, GutenbergImportEntry>? entries}) {
    return GutenbergImportState(entries: entries ?? this.entries);
  }

  static const initial = GutenbergImportState(entries: <int, GutenbergImportEntry>{});
}

class GutenbergImportResult {
  const GutenbergImportResult.success(this.message, {this.bookId}) : ok = true;
  const GutenbergImportResult.failure(this.message) : ok = false, bookId = null;

  final bool ok;
  final String message;
  final String? bookId;
}

class GutenbergImportController extends Notifier<GutenbergImportState> {
  static const int _maxConcurrentImports = 2;
  int _activeImports = 0;

  @override
  GutenbergImportState build() => GutenbergImportState.initial;

  bool isAlreadyImported(int gutenbergId) {
    final library = ref.read(libraryProvider).value?.books;
    if (library == null) return false;
    return library.any((b) => b.gutenbergId == gutenbergId);
  }

  Future<GutenbergImportResult> importBook(GutendexBook book) async {
    final existing = state.entryFor(book.id);
    if (existing.isBusy) {
      return const GutenbergImportResult.failure('Import already in progress');
    }

    if (_activeImports >= _maxConcurrentImports) {
      return const GutenbergImportResult.failure('Too many imports running. Please wait.');
    }

    final urlStr = book.epubUrl;
    if (urlStr == null || urlStr.isEmpty) {
      _setEntry(
        book.id,
        const GutenbergImportEntry(
          phase: GutenbergImportPhase.failed,
          progress: null,
          message: 'No EPUB available for this book',
        ),
      );
      return const GutenbergImportResult.failure('No EPUB available for this book');
    }

    final uri = Uri.tryParse(urlStr);
    if (uri == null) {
      _setEntry(
        book.id,
        const GutenbergImportEntry(
          phase: GutenbergImportPhase.failed,
          progress: null,
          message: 'Invalid download URL',
        ),
      );
      return const GutenbergImportResult.failure('Invalid download URL');
    }

    File? downloaded;
    try {
      _activeImports++;

      // Deduplicate at start (fast path)
      final existingId = ref.read(libraryProvider.notifier).findByGutenbergId(book.id);
      if (existingId != null) {
        _setEntry(
          book.id,
          const GutenbergImportEntry(
            phase: GutenbergImportPhase.done,
            progress: 1,
            message: 'Imported',
          ),
        );
        return GutenbergImportResult.success('Already imported', bookId: existingId);
      }

      _setEntry(
        book.id,
        const GutenbergImportEntry(
          phase: GutenbergImportPhase.downloading,
          progress: 0,
          message: 'Downloading…',
        ),
      );

      final paths = await ref.read(appPathsProvider.future);
      await paths.tempDownloadsDir.create(recursive: true);

      final fileName = _suggestFileName(book);
      final safeName = _sanitizeFileName(fileName);
      final partFile = File('${paths.tempDownloadsDir.path}/$safeName.part');
      final finalFile = File('${paths.tempDownloadsDir.path}/$safeName');

      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      if (await finalFile.exists()) {
        try {
          await finalFile.delete();
        } catch (_) {}
      }

      downloaded = await _downloadToFile(
        uri,
        partFile,
        onProgress: (received, total) {
          final progress = total == null || total <= 0
              ? null
              : (received / total).clamp(0.0, 1.0);
          final current = state.entryFor(book.id);
          if (current.phase != GutenbergImportPhase.downloading) return;
          _setEntry(book.id, current.copyWith(progress: progress, message: 'Downloading…'));
        },
      );

      await downloaded.rename(finalFile.path);
      downloaded = finalFile;

      _setEntry(
        book.id,
        const GutenbergImportEntry(
          phase: GutenbergImportPhase.importing,
          progress: null,
          message: 'Importing…',
        ),
      );

      final bookId = await ref.read(libraryProvider.notifier).importBookFromPath(
            sourcePath: downloaded.path,
            fileName: safeName,
            gutenbergId: book.id,
            overrideTitle: book.title,
            overrideAuthor: book.authorsDisplay,
          );

      _setEntry(
        book.id,
        const GutenbergImportEntry(
          phase: GutenbergImportPhase.done,
          progress: 1,
          message: 'Imported',
        ),
      );

      return GutenbergImportResult.success('Imported', bookId: bookId);
    } catch (e) {
      if (kDebugMode) debugPrint('Gutenberg import failed: $e');
      _setEntry(
        book.id,
        GutenbergImportEntry(
          phase: GutenbergImportPhase.failed,
          progress: null,
          message: 'Download/import failed: $e',
        ),
      );
      return const GutenbergImportResult.failure('Download/import failed');
    } finally {
      _activeImports--;
      if (downloaded != null) {
        try {
          await downloaded.delete();
        } catch (_) {}
      }
    }
  }

  Future<File> _downloadToFile(
    Uri uri,
    File targetFile, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final request = http.Request('GET', uri);
    request.headers['Accept-Encoding'] = 'identity';
    request.headers['User-Agent'] = 'audiobook_flutter_v2';

    final response = await request.send();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Download failed (${response.statusCode})');
    }

    final length = response.contentLength;
    final total = (length != null && length > 0) ? length : null;

    final sink = targetFile.openWrite();
    var received = 0;
    await for (final chunk in response.stream) {
      received += chunk.length;
      sink.add(chunk);
      onProgress?.call(received, total);
    }
    await sink.flush();
    await sink.close();
    return targetFile;
  }

  void _setEntry(int gutenbergId, GutenbergImportEntry entry) {
    final next = Map<int, GutenbergImportEntry>.from(state.entries);
    next[gutenbergId] = entry;
    state = state.copyWith(entries: next);
  }

  String _suggestFileName(GutendexBook book) {
    final title = book.title.trim().isEmpty ? 'Gutenberg ${book.id}' : book.title.trim();
    final author = book.authorsDisplay.trim().isEmpty ? 'Unknown' : book.authorsDisplay.trim();
    return '$title — $author (Gutenberg ${book.id}).epub';
  }

  String _sanitizeFileName(String name) {
    final trimmed = name.trim().isEmpty ? 'book.epub' : name.trim();
    final withoutBadChars = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._\- ]+'), '_');
    var out = withoutBadChars;
    if (!out.toLowerCase().endsWith('.epub')) out = '$out.epub';
    if (out.length > 160) out = '${out.substring(0, 160)}.epub';
    return out;
  }
}

final gutenbergImportProvider =
    NotifierProvider<GutenbergImportController, GutenbergImportState>(
  GutenbergImportController.new,
);
