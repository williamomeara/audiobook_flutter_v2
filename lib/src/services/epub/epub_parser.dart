import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../models/chapter.dart';
import '../../state/app_paths.dart';
import '../../utils/id.dart';
import 'html_to_text.dart';

class ParsedEpub {
  const ParsedEpub({
    required this.title,
    required this.author,
    required this.coverPath,
    required this.chapters,
  });

  final String title;
  final String author;
  final String? coverPath;
  final List<Chapter> chapters;
}

class EpubParser {
  const EpubParser(this._paths);

  final AppPaths _paths;

  Future<ParsedEpub> parseFromFile({
    required String epubPath,
    required String bookId,
  }) async {
    // Offload heavy EPUB parsing to an isolate to avoid blocking the main thread.
    // This is critical when importing multiple books simultaneously.
    final bytes = await File(epubPath).readAsBytes();
    EpubBook epubBook;
    try {
      epubBook = await compute(_parseEpubInIsolate, bytes);
    } catch (e) {
      debugPrint('EpubReader failed, falling back to zip parse: $e');
      return _fallbackParseFromZip(epubPath: epubPath, bookId: bookId);
    }

    final title = (epubBook.Title ?? bookId).trim().isEmpty
        ? bookId
        : (epubBook.Title ?? bookId).trim();
    final author = (epubBook.Author ?? 'Unknown author').trim().isEmpty
        ? 'Unknown author'
        : (epubBook.Author ?? 'Unknown author').trim();

    String? coverPath;
    final dynamic coverObj = epubBook.CoverImage;
    if (coverObj != null) {
      final dir = _paths.bookDir(bookId);
      await dir.create(recursive: true);
      final dest = File('${dir.path}/cover.jpg');

      try {
        // If epubx gives us raw bytes
        if (coverObj is Uint8List || coverObj is List<int>) {
          final bytes = coverObj is Uint8List
              ? coverObj
              : Uint8List.fromList(coverObj as List<int>);
          await dest.writeAsBytes(bytes, flush: true);
          coverPath = dest.path;
        } else if (coverObj is img.Image) {
          // Offload JPEG encoding to isolate (CPU-intensive)
          final coverBytes = await compute(_encodeImageToJpg, coverObj);
          await dest.writeAsBytes(coverBytes, flush: true);
          coverPath = dest.path;
        } else {
          // Last-resort: try converting via toString bytes (not ideal), but log for debugging
          debugPrint(
            'EpubParser: unexpected CoverImage type: ${coverObj.runtimeType}',
          );
        }
      } catch (e) {
        debugPrint('EpubParser: failed to write cover image: $e');
      }
    }

    // If epubx didn't provide a cover image, try extracting one from the
    // archive (publisher images often exist but aren't marked as the cover).
    if (coverPath == null) {
      try {
        final maybe = await _extractCoverFromZip(
          epubPath: epubPath,
          bookId: bookId,
        );
        if (maybe != null) coverPath = maybe;
      } catch (e) {
        debugPrint('EpubParser: extractCoverFromZip failed: $e');
      }
    }

    final chapters = <Chapter>[];

    final flattened = <EpubChapter>[];
    void addChapters(List<EpubChapter>? list) {
      if (list == null) return;
      for (final ch in list) {
        flattened.add(ch);
        addChapters(ch.SubChapters);
      }
    }

    addChapters(epubBook.Chapters);

    var chapterNumber = 0;
    for (final ch in flattened) {
      final html = (ch.HtmlContent ?? '').trim();
      if (html.isEmpty) continue;
      final text = stripHtmlToText(html);
      if (text.isEmpty) continue;

      chapterNumber += 1;
      final chTitle = (ch.Title ?? '').trim();
      chapters.add(
        Chapter(
          id: '$bookId-ch-$chapterNumber-${generateId().substring(0, 6)}',
          number: chapterNumber,
          title: chTitle.isEmpty ? 'Chapter $chapterNumber' : chTitle,
          content: text,
        ),
      );
    }

    return ParsedEpub(
      title: title,
      author: author,
      coverPath: coverPath,
      chapters: chapters,
    );
  }

  Future<String?> _extractCoverFromZip({
    required String epubPath,
    required String bookId,
  }) async {
    try {
      final dir = _paths.bookDir(bookId);
      await dir.create(recursive: true);

      final inputStream = InputFileStream(epubPath);
      final archive = ZipDecoder().decodeBuffer(inputStream);

      return _extractCoverFromArchive(
        archive: archive,
        destDir: dir,
        epubPathForLog: epubPath,
      );
    } catch (e, st) {
      debugPrint('EpubParser: extractCoverFromZip failed: $e\n$st');
      return null;
    }
  }

  Future<String?> _extractCoverFromArchive({
    required Archive archive,
    required Directory destDir,
    required String epubPathForLog,
  }) async {
    // 1) Prefer files with 'cover' in the name
    for (final file in archive) {
      final name = file.name.toLowerCase();
      if (!file.isFile) continue;
      if (name.contains('cover') &&
          (name.endsWith('.jpg') ||
              name.endsWith('.jpeg') ||
              name.endsWith('.png') ||
              name.endsWith('.webp'))) {
        final ext = name.substring(name.lastIndexOf('.'));
        final dest = File('${destDir.path}/cover$ext');
        await dest.writeAsBytes(file.content as List<int>, flush: true);
        if (kDebugMode) {
          debugPrint(
            'EpubParser: wrote fallback cover ${dest.path} size=${File(dest.path).lengthSync()} (from $name)',
          );
        }
        return dest.path;
      }
    }

    // 2) Otherwise pick the largest image file (best-effort)
    ArchiveFile? best;
    final candidates = <ArchiveFile>[];
    for (final file in archive) {
      final name = file.name.toLowerCase();
      if (!file.isFile) continue;
      if (name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.png') ||
          name.endsWith('.webp')) {
        candidates.add(file);
        if (best == null || file.size > best.size) {
          best = file;
        }
      }
    }

    if (kDebugMode) {
      try {
        debugPrint(
          'EpubParser: image candidates in zip for $epubPathForLog: ${candidates.map((c) => '${c.name}(${c.size})').join(', ')}',
        );
      } catch (_) {}
    }

    if (best != null) {
      final name = best.name;
      final ext = name.substring(name.lastIndexOf('.'));
      final dest = File('${destDir.path}/cover$ext');
      await dest.writeAsBytes(best.content as List<int>, flush: true);
      if (kDebugMode) {
        debugPrint(
          'EpubParser: wrote fallback cover ${dest.path} size=${File(dest.path).lengthSync()} (from $name)',
        );
      }
      return dest.path;
    }

    return null;
  }

  Future<ParsedEpub> _fallbackParseFromZip({
    required String epubPath,
    required String bookId,
  }) async {
    final dir = _paths.bookDir(bookId);
    await dir.create(recursive: true);

    String? coverPath;
    final chapters = <Chapter>[];

    try {
      final inputStream = InputFileStream(epubPath);
      final archive = ZipDecoder().decodeBuffer(inputStream);
      // Use shared helper to extract a cover; it will log candidates.
      coverPath = await _extractCoverFromArchive(
        archive: archive,
        destDir: dir,
        epubPathForLog: epubPath,
      );

      // Collect xhtml/html files as chapters (best-effort)
      final xhtmlFiles = archive
          .where(
            (f) =>
                f.isFile &&
                (f.name.endsWith('.xhtml') ||
                    f.name.endsWith('.html') ||
                    f.name.endsWith('.htm')),
          )
          .toList();
      xhtmlFiles.sort((a, b) => a.name.compareTo(b.name));

      var chapterNumber = 0;
      for (final entry in xhtmlFiles) {
        final raw = entry.content as List<int>;
        String text;
        try {
          text = stripHtmlToText(utf8.decode(raw));
        } catch (_) {
          text = stripHtmlToText(String.fromCharCodes(raw));
        }
        if (text.trim().isEmpty) continue;
        chapterNumber += 1;
        final fileTitle = entry.name.split('/').last;
        final title = _chooseChapterTitle(
          fileTitle: fileTitle,
          text: text,
          chapterNumber: chapterNumber,
        );
        chapters.add(
          Chapter(
            id: '$bookId-ch-$chapterNumber-${generateId().substring(0, 6)}',
            number: chapterNumber,
            title: title,
            content: text,
          ),
        );
      }

      // Best-effort title/author fallback
      final fileName = epubPath.split('/').last;
      final title = fileName.replaceAll('.epub', '');
      return ParsedEpub(
        title: title,
        author: 'Unknown author',
        coverPath: coverPath,
        chapters: chapters,
      );
    } catch (e, st) {
      debugPrint('Fallback parse failed: $e\n$st');
      // Don't rethrow from the fallback parser — return a minimal ParsedEpub so
      // the caller can surface a user-friendly error without crashing the app.
      final fileName = epubPath.split('/').last;
      return ParsedEpub(
        title: fileName.replaceAll('.epub', ''),
        author: 'Unknown author',
        coverPath: coverPath,
        chapters: chapters,
      );
    }
  }
}

String _chooseChapterTitle({
  required String fileTitle,
  required String text,
  required int chapterNumber,
}) {
  final cleanedText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final sample = cleanedText.length > 800
      ? cleanedText.substring(0, 800)
      : cleanedText;

  // 1) If the chapter text clearly declares a chapter/prologue/etc, use that.
  final chapterMatch = RegExp(
    r'\b(chapter|cap[ií]tulo)\s+([0-9]+|[ivxlcdm]+)\b(?:\s*[:.\-–]\s*([^\n]{1,80}))?',
    caseSensitive: false,
  ).firstMatch(sample);
  if (chapterMatch != null) {
    final label = chapterMatch.group(1)!;
    final num = chapterMatch.group(2) ?? '';
    final tail = (chapterMatch.group(3) ?? '').trim();
    final normalizedLabel = label.toLowerCase().startsWith('cap')
        ? 'Capítulo'
        : 'Chapter';
    if (tail.isNotEmpty && tail.length <= 60) {
      return '$normalizedLabel $num: $tail';
    }
    return '$normalizedLabel $num';
  }

  final specialMatch = RegExp(
    r'\b(prologue|epilogue|preface|introduction|appendix|acknowledg(e)?ments|contents|table of contents)\b',
    caseSensitive: false,
  ).firstMatch(sample);
  if (specialMatch != null) {
    final raw = specialMatch.group(1)!.toLowerCase();
    switch (raw) {
      case 'table of contents':
        return 'Table of Contents';
      case 'acknowledgements':
      case 'acknowledgments':
        return 'Acknowledgements';
      default:
        return raw[0].toUpperCase() + raw.substring(1);
    }
  }

  // 2) Use the file title only if it looks human-ish (avoid epub generator ids).
  final base = fileTitle.replaceAll(
    RegExp(r'\.(xhtml|html|htm)$', caseSensitive: false),
    '',
  );
  if (_looksLikeHumanTitle(base)) {
    return base;
  }

  // 3) Fall back to a stable generic name.
  return 'Chapter $chapterNumber';
}

bool _looksLikeHumanTitle(String s) {
  final v = s.trim();
  if (v.isEmpty) return false;
  if (v.length > 40) return false;
  if (!RegExp(r'[A-Za-z]').hasMatch(v)) return false;
  if (v.contains('_')) return false;
  if (RegExp(r'\b(epub|oebps|opf|ncx)\b', caseSensitive: false).hasMatch(v)) {
    return false;
  }
  if (RegExp(r'\d{4,}').hasMatch(v)) return false;
  if (RegExp(r'^[0-9]+[-_][0-9]+$').hasMatch(v)) return false;
  return true;
}

/// Top-level function for isolate: parse EPUB bytes.
/// This runs in a background isolate to avoid blocking the main thread.
Future<EpubBook> _parseEpubInIsolate(Uint8List bytes) async {
  return await EpubReader.readBook(bytes);
}

/// Top-level function for isolate: encode image to JPEG.
/// This runs in a background isolate to avoid blocking the main thread.
Uint8List _encodeImageToJpg(img.Image image) {
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

final epubParserProvider = Provider<EpubParser>((ref) {
  final paths = ref.watch(appPathsProvider);
  return EpubParser(paths);
});
