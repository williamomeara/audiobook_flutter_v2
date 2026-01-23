import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import 'package:core_domain/core_domain.dart';

import '../app/app_paths.dart';
import '../utils/text_normalizer.dart' as tts_normalizer;
import '../utils/boilerplate_remover.dart';
import '../utils/content_classifier.dart';

/// Parsed EPUB result.
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

/// EPUB parser service.
class EpubParser {
  const EpubParser(this._paths);

  final AppPaths _paths;

  Future<ParsedEpub> parseFromFile({
    required String epubPath,
    required String bookId,
  }) async {
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
        if (coverObj is Uint8List || coverObj is List<int>) {
          final bytes = coverObj is Uint8List
              ? coverObj
              : Uint8List.fromList(coverObj as List<int>);
          await dest.writeAsBytes(bytes, flush: true);
          coverPath = dest.path;
        } else if (coverObj is img.Image) {
          final coverBytes = await compute(_encodeImageToJpg, coverObj);
          await dest.writeAsBytes(coverBytes, flush: true);
          coverPath = dest.path;
        }
      } catch (e) {
        debugPrint('EpubParser: failed to write cover image: $e');
      }
    }

    // Try extracting cover from zip if not found
    if (coverPath == null) {
      try {
        coverPath = await _extractCoverFromZip(epubPath: epubPath, bookId: bookId);
      } catch (_) {}
    }

    final rawChapters = <Chapter>[];
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
      final text = _stripHtmlToText(html);
      if (text.isEmpty) continue;

      chapterNumber += 1;
      final chTitle = (ch.Title ?? '').trim();
      rawChapters.add(Chapter(
        id: '$bookId-ch-$chapterNumber-${generateId(length: 6)}',
        number: chapterNumber,
        title: chTitle.isEmpty ? 'Chapter $chapterNumber' : chTitle,
        content: text,
      ));
    }

    // Apply smart text processing pipeline
    final chapters = _processChapters(rawChapters);

    return ParsedEpub(
      title: title,
      author: author,
      coverPath: coverPath,
      chapters: chapters,
    );
  }

  /// Process chapters through the smart text pipeline.
  ///
  /// Pipeline steps:
  /// 1. Classify chapters to find body matter range (skip front/back matter)
  /// 2. Clean each chapter (remove boilerplate, scanner notes)
  /// 3. Normalize text (quotes, dashes, ligatures, spaces)
  /// 4. Renumber chapters starting from 1
  List<Chapter> _processChapters(List<Chapter> rawChapters) {
    if (rawChapters.isEmpty) return rawChapters;

    // Build ChapterInfo for classification
    final chapterInfos = rawChapters.map((ch) {
      final snippetLength = min(500, ch.content.length);
      return ChapterInfo(
        filename: ch.id,
        title: ch.title,
        contentSnippet: ch.content.substring(0, snippetLength),
      );
    }).toList();

    // Find body matter range (skip front/back matter)
    final (startIdx, endIdx) = ContentClassifier.findBodyMatterRange(chapterInfos);

    // Filter to body matter only
    var bodyChapters = rawChapters.sublist(startIdx, endIdx);

    // Detect repeated prefixes across chapters (e.g., "Book Title | Publisher")
    final chapterContents = bodyChapters.map((ch) => ch.content).toList();
    final repeatedPrefix = BoilerplateRemover.detectRepeatedPrefix(chapterContents);

    // Clean and normalize each chapter
    bodyChapters = bodyChapters.map((chapter) {
      var content = chapter.content;

      // Remove detected repeated prefix
      if (repeatedPrefix != null) {
        content = BoilerplateRemover.removePrefix(content, repeatedPrefix);
      }

      // Remove per-chapter boilerplate (page numbers, scanner notes, etc.)
      content = BoilerplateRemover.cleanChapter(content);

      // Normalize text (quotes, dashes, ligatures, special chars)
      content = tts_normalizer.TextNormalizer.normalize(content);

      return Chapter(
        id: chapter.id,
        number: chapter.number,
        title: chapter.title,
        content: content,
      );
    }).toList();

    // Renumber chapters starting from 1
    final renumbered = bodyChapters.asMap().entries.map((e) => Chapter(
      id: e.value.id,
      number: e.key + 1,
      title: e.value.title,
      content: e.value.content,
    )).toList();

    return renumbered;
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

      // Look for cover image
      for (final file in archive) {
        final name = file.name.toLowerCase();
        if (!file.isFile) continue;
        if (name.contains('cover') &&
            (name.endsWith('.jpg') || name.endsWith('.jpeg') || 
             name.endsWith('.png') || name.endsWith('.webp'))) {
          final ext = name.substring(name.lastIndexOf('.'));
          final dest = File('${dir.path}/cover$ext');
          await dest.writeAsBytes(file.content as List<int>, flush: true);
          return dest.path;
        }
      }

      // Fallback: largest image
      ArchiveFile? best;
      for (final file in archive) {
        final name = file.name.toLowerCase();
        if (!file.isFile) continue;
        if (name.endsWith('.jpg') || name.endsWith('.jpeg') || 
            name.endsWith('.png') || name.endsWith('.webp')) {
          if (best == null || file.size > best.size) {
            best = file;
          }
        }
      }

      if (best != null) {
        final name = best.name;
        final ext = name.substring(name.lastIndexOf('.'));
        final dest = File('${dir.path}/cover$ext');
        await dest.writeAsBytes(best.content as List<int>, flush: true);
        return dest.path;
      }
    } catch (_) {}
    return null;
  }

  Future<ParsedEpub> _fallbackParseFromZip({
    required String epubPath,
    required String bookId,
  }) async {
    final dir = _paths.bookDir(bookId);
    await dir.create(recursive: true);

    String? coverPath;
    final rawChapters = <Chapter>[];

    try {
      final inputStream = InputFileStream(epubPath);
      final archive = ZipDecoder().decodeBuffer(inputStream);
      
      coverPath = await _extractCoverFromZip(epubPath: epubPath, bookId: bookId);

      final xhtmlFiles = archive
          .where((f) => f.isFile && 
                 (f.name.endsWith('.xhtml') || f.name.endsWith('.html') || f.name.endsWith('.htm')))
          .toList();
      xhtmlFiles.sort((a, b) => a.name.compareTo(b.name));

      var chapterNumber = 0;
      for (final entry in xhtmlFiles) {
        final raw = entry.content as List<int>;
        String text;
        try {
          text = _stripHtmlToText(utf8.decode(raw));
        } catch (_) {
          text = _stripHtmlToText(String.fromCharCodes(raw));
        }
        if (text.trim().isEmpty) continue;
        
        chapterNumber += 1;
        rawChapters.add(Chapter(
          id: '$bookId-ch-$chapterNumber-${generateId(length: 6)}',
          number: chapterNumber,
          title: 'Chapter $chapterNumber',
          content: text,
        ));
      }

      // Apply smart text processing pipeline
      final chapters = _processChapters(rawChapters);

      final fileName = epubPath.split('/').last;
      return ParsedEpub(
        title: fileName.replaceAll('.epub', ''),
        author: 'Unknown author',
        coverPath: coverPath,
        chapters: chapters,
      );
    } catch (e) {
      // Apply smart processing even on error path if we have chapters
      final chapters = _processChapters(rawChapters);
      
      final fileName = epubPath.split('/').last;
      return ParsedEpub(
        title: fileName.replaceAll('.epub', ''),
        author: 'Unknown author',
        coverPath: coverPath,
        chapters: chapters,
      );
    }
  }

  /// Strip HTML tags and normalize whitespace.
  String _stripHtmlToText(String html) {
    // Remove script and style tags with content
    var text = html.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '');
    
    // Replace br and p tags with newlines
    text = text.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    text = text.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
    
    // Remove all remaining HTML tags
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    
    // Decode HTML entities
    text = _decodeHtmlEntities(text);
    
    // Normalize whitespace
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    return text;
  }

  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'");
  }
}

/// Parse EPUB in isolate.
Future<EpubBook> _parseEpubInIsolate(Uint8List bytes) async {
  return await EpubReader.readBook(bytes);
}

/// Encode image in isolate.
Uint8List _encodeImageToJpg(img.Image image) {
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

/// EPUB parser provider.
final epubParserProvider = FutureProvider<EpubParser>((ref) async {
  final paths = await ref.watch(appPathsProvider.future);
  return EpubParser(paths);
});
