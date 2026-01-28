import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import 'package:core_domain/core_domain.dart';

import '../app/app_paths.dart';
import '../utils/background_chapter_processor.dart';

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

    // Group chapters by their content file to handle anchor-based splitting
    final chaptersByFile = <String, List<EpubChapter>>{};
    for (final ch in flattened) {
      final fileName = ch.ContentFileName ?? '';
      if (fileName.isEmpty) continue;
      chaptersByFile.putIfAbsent(fileName, () => []).add(ch);
    }

    var chapterNumber = 0;
    for (final ch in flattened) {
      final html = (ch.HtmlContent ?? '').trim();
      if (html.isEmpty) continue;
      
      // Extract only the content for this chapter's anchor if file is shared
      final fileName = ch.ContentFileName ?? '';
      final chaptersInFile = chaptersByFile[fileName] ?? [];
      String text;
      
      if (chaptersInFile.length > 1 && ch.Anchor != null && ch.Anchor!.isNotEmpty) {
        // Multiple chapters share this file - extract content between anchors
        text = _extractAnchorContent(html, ch.Anchor!, chaptersInFile, ch);
      } else {
        // Single chapter per file - use entire content
        text = _stripHtmlToText(html);
      }
      
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

    // Apply smart text processing pipeline in background isolate
    final chapters = await processChaptersInBackground(rawChapters);

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

      // Apply smart text processing pipeline in background isolate
      final chapters = await processChaptersInBackground(rawChapters);

      final fileName = epubPath.split('/').last;
      return ParsedEpub(
        title: fileName.replaceAll('.epub', ''),
        author: 'Unknown author',
        coverPath: coverPath,
        chapters: chapters,
      );
    } catch (e) {
      // Apply smart processing even on error path if we have chapters
      final chapters = await processChaptersInBackground(rawChapters);
      
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
    
    // Remove Project Gutenberg boilerplate sections before stripping tags
    // These are marked with class="pg-boilerplate" in the HTML
    text = text.replaceAll(
      RegExp(r'<section[^>]*class="[^"]*pg-boilerplate[^"]*"[^>]*>[\s\S]*?</section>', caseSensitive: false), 
      ''
    );
    // Also handle div-based boilerplate (older PG formats)
    text = text.replaceAll(
      RegExp(r'<div[^>]*class="[^"]*pg-boilerplate[^"]*"[^>]*>[\s\S]*?</div>', caseSensitive: false), 
      ''
    );
    // Remove PG header and footer elements by id
    text = text.replaceAll(
      RegExp(r'<[^>]*id="pg-header"[^>]*>[\s\S]*?</[^>]+>', caseSensitive: false), 
      ''
    );
    text = text.replaceAll(
      RegExp(r'<[^>]*id="pg-footer"[^>]*>[\s\S]*?</[^>]+>', caseSensitive: false), 
      ''
    );
    text = text.replaceAll(
      RegExp(r'<[^>]*id="pg-start-separator"[^>]*>[\s\S]*?</[^>]+>', caseSensitive: false), 
      ''
    );
    text = text.replaceAll(
      RegExp(r'<[^>]*id="pg-end-separator"[^>]*>[\s\S]*?</[^>]+>', caseSensitive: false), 
      ''
    );
    
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

  /// Extract content between anchor boundaries when multiple chapters share one file.
  /// 
  /// This handles EPUBs where the TOC uses anchor fragments (e.g., file.xhtml#chapter1)
  /// to point to different sections within a single HTML file.
  String _extractAnchorContent(
    String html, 
    String currentAnchor, 
    List<EpubChapter> chaptersInFile,
    EpubChapter currentChapter,
  ) {
    // Find all anchor positions in the HTML for chapters in this file
    final anchorPositions = <String, int>{};
    
    for (final ch in chaptersInFile) {
      final anchor = ch.Anchor;
      if (anchor == null || anchor.isEmpty) continue;
      
      // Look for id="anchor" or name="anchor" in the HTML
      final patterns = [
        RegExp('id=["\']${RegExp.escape(anchor)}["\']', caseSensitive: false),
        RegExp('name=["\']${RegExp.escape(anchor)}["\']', caseSensitive: false),
      ];
      
      for (final pattern in patterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          anchorPositions[anchor] = match.start;
          break;
        }
      }
    }
    
    // If we couldn't find the current anchor, fall back to full content
    if (!anchorPositions.containsKey(currentAnchor)) {
      return _stripHtmlToText(html);
    }
    
    // Sort anchors by position in HTML
    final sortedAnchors = anchorPositions.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    
    // Find the current anchor's position in the sorted list
    final currentIndex = sortedAnchors.indexWhere((e) => e.key == currentAnchor);
    if (currentIndex == -1) {
      return _stripHtmlToText(html);
    }
    
    // Extract content from current anchor to next anchor (or end of file)
    final startPos = anchorPositions[currentAnchor]!;
    final endPos = currentIndex + 1 < sortedAnchors.length
        ? sortedAnchors[currentIndex + 1].value
        : html.length;
    
    // Extract the HTML segment
    final segment = html.substring(startPos, endPos);
    
    return _stripHtmlToText(segment);
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
