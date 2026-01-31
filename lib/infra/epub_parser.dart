import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_size_getter/image_size_getter.dart';

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

    // Extract all images from EPUB for figure support (with dimensions)
    final imageInfoMap = await _extractAllImages(epubPath: epubPath, bookId: bookId);

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
      final rawHtml = (ch.HtmlContent ?? '').trim();
      if (rawHtml.isEmpty) continue;
      
      // Extract only the content for this chapter's anchor if file is shared
      // Do this FIRST on raw HTML before image replacement to avoid corrupting
      // figure placeholders when splitting at anchor boundaries
      final fileName = ch.ContentFileName ?? '';
      final chaptersInFile = chaptersByFile[fileName] ?? [];
      String chapterHtml;
      
      if (chaptersInFile.length > 1 && ch.Anchor != null && ch.Anchor!.isNotEmpty) {
        // Multiple chapters share this file - extract content between anchors
        chapterHtml = _extractAnchorHtml(rawHtml, ch.Anchor!, chaptersInFile, ch);
      } else {
        // Single chapter per file - use entire content
        chapterHtml = rawHtml;
      }
      
      // Now replace <img> tags with figure placeholders in the extracted HTML
      final htmlWithFigures = _replaceImagesWithPlaceholders(chapterHtml, fileName, imageInfoMap);
      
      // Finally strip HTML to plain text
      final text = _stripHtmlToText(htmlWithFigures);
      
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
    // Pass book title to help detect repeated title prefixes
    final chapters = await processChaptersInBackground(rawChapters, bookTitle: title);

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

      // Extract images for figure support (same as main parser) with dimensions
      final imageInfoMap = await _extractAllImages(epubPath: epubPath, bookId: bookId);

      final xhtmlFiles = archive
          .where((f) => f.isFile && 
                 (f.name.endsWith('.xhtml') || f.name.endsWith('.html') || f.name.endsWith('.htm')))
          .toList();
      xhtmlFiles.sort((a, b) => a.name.compareTo(b.name));

      var chapterNumber = 0;
      for (final entry in xhtmlFiles) {
        final raw = entry.content as List<int>;
        String html;
        try {
          html = utf8.decode(raw);
        } catch (_) {
          html = String.fromCharCodes(raw);
        }
        
        // Replace images with placeholders before stripping HTML
        html = _replaceImagesWithPlaceholders(html, entry.name, imageInfoMap);
        
        final text = _stripHtmlToText(html);
        if (text.trim().isEmpty) continue;
        
        chapterNumber += 1;
        rawChapters.add(Chapter(
          id: '$bookId-ch-$chapterNumber-${generateId(length: 6)}',
          number: chapterNumber,
          title: 'Chapter $chapterNumber',
          content: text,
        ));
      }
final fileName = epubPath.split('/').last;
      final fallbackTitle = fileName.replaceAll('.epub', '');
      
      // Apply smart text processing pipeline in background isolate
      final chapters = await processChaptersInBackground(rawChapters, bookTitle: fallbackTitle);

      return ParsedEpub(
        title: fallbackTitle,
        author: 'Unknown author',
        coverPath: coverPath,
        chapters: chapters,
      );
    } catch (e) {
      final fileName = epubPath.split('/').last;
      final fallbackTitle = fileName.replaceAll('.epub', '');
      
      // Apply smart processing even on error path if we have chapters
      final chapters = await processChaptersInBackground(rawChapters, bookTitle: fallbackTitle);
      
      return ParsedEpub(
        title: fallbackTitle,
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

    // Remove all remaining HTML tags (including malformed ones)
    // Use dotAll mode to match tags that span multiple lines
    text = text.replaceAll(RegExp(r'<[^>]*>', dotAll: true), '');

    // Remove incomplete/truncated HTML tags at end of text (from anchor boundary splits)
    // Matches: <h3, <div class= chapter, <span style=, etc. (tags without closing >)
    text = text.replaceAll(RegExp(r'<[a-zA-Z][^>]*$'), '');
    
    // Remove incomplete tags at start of text (content starting mid-tag)
    // Matches: class="foo"> or attribute="value">
    text = text.replaceAll(RegExp(r'^[^<]*?>'), '');

    // Remove HTML attribute patterns with trailing artifacts
    // KEY FIX: Include non-alphanumeric characters after the attribute
    // Matches: id="pgepubid00000">, id="pgepubid00001\">
    text = text.replaceAll(RegExp(r'\bid\s*=\s*"pgepubid\d+"'), '');
    text = text.replaceAll(RegExp(r"\bid\s*=\s*'pgepubid\d+'"), '');

    // Remove numeric-only id patterns: id00000>, id00002\">
    text = text.replaceAll(RegExp(r'\bid\d{5,}'), '');

    // Remove short numeric IDs with trailing non-word chars: 08>, d00000>, etc.
    text = text.replaceAllMapped(RegExp(r'(^|\s)(d\d+)[^a-z0-9]'), (match) {
      return (match.group(1) ?? '') + ' ';
    });
    text = text.replaceAllMapped(RegExp(r'(^|\s)0\d{2,}[^a-z0-9]*'), (match) {
      return (match.group(1) ?? '') + ' ';
    });

    // Remove remaining id= patterns with quoted values
    text = text.replaceAll(RegExp(r'\bid\s*=\s*[^\s>]*'), '');

    // Remove stray quote/bracket combinations using simple string operations
    text = text.replaceAll('\"', ' ');
    text = text.replaceAll("'", ' ');
    text = text.replaceAll('>', ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Remove Project Gutenberg pipe separator in all positions
    text = text.replaceAll(RegExp(r'\|\s*Project Gutenberg\s*'), ' ');

    // Remove orphaned closing angle bracket at segment boundaries
    text = text.replaceAll(RegExp(r'^>\s*'), '');
    text = text.replaceAll(RegExp(r'\s*>$'), '');

    // Remove leading/trailing quotes (HTML artifacts, not code)
    if (text.startsWith('"') || text.startsWith("'")) {
      text = text.substring(1);
    }
    if (text.endsWith('"') || text.endsWith("'")) {
      text = text.substring(0, text.length - 1);
    }

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
  /// 
  /// Returns raw HTML (not text) so figure placeholders can be inserted after.
  String _extractAnchorHtml(
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
      return html;
    }
    
    // Sort anchors by position in HTML
    final sortedAnchors = anchorPositions.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    
    // Find the current anchor's position in the sorted list
    final currentIndex = sortedAnchors.indexWhere((e) => e.key == currentAnchor);
    if (currentIndex == -1) {
      return html;
    }
    
    // Extract content from current anchor to next anchor (or end of file)
    final startPos = anchorPositions[currentAnchor]!;
    final endPos = currentIndex + 1 < sortedAnchors.length
        ? sortedAnchors[currentIndex + 1].value
        : html.length;
    
    // Extract and return the raw HTML segment
    return html.substring(startPos, endPos);
  }

  /// Image info with path and optional dimensions.
  /// Used internally during EPUB parsing.
}

class _ImageInfo {
  _ImageInfo({required this.path, this.width, this.height});
  final String path;
  final int? width;
  final int? height;
}

extension _EpubParserImageExtraction on EpubParser {
  /// Extract all images from EPUB archive and save to book directory.
  /// Returns a map of original image paths (as they appear in EPUB) to image info with dimensions.
  Future<Map<String, _ImageInfo>> _extractAllImages({
    required String epubPath,
    required String bookId,
  }) async {
    final imageInfoMap = <String, _ImageInfo>{};
    
    try {
      final dir = _paths.bookDir(bookId);
      final imagesDir = Directory('${dir.path}/images');
      await imagesDir.create(recursive: true);

      final inputStream = InputFileStream(epubPath);
      final archive = ZipDecoder().decodeBuffer(inputStream);
      
      var imageIndex = 0;
      for (final file in archive) {
        if (!file.isFile) continue;
        
        final name = file.name.toLowerCase();
        // Skip cover images (already handled separately)
        if (name.contains('cover')) continue;
        
        // Check if this is an image file (skip SVG - can't easily get dimensions)
        if (name.endsWith('.jpg') || name.endsWith('.jpeg') || 
            name.endsWith('.png') || name.endsWith('.gif') ||
            name.endsWith('.webp')) {
          
          // Extract the file
          final ext = name.substring(name.lastIndexOf('.'));
          final destName = 'img_${imageIndex.toString().padLeft(4, '0')}$ext';
          final destPath = '${imagesDir.path}/$destName';
          
          try {
            final destFile = File(destPath);
            final content = file.content as List<int>;
            await destFile.writeAsBytes(content, flush: true);
            
            // Get image dimensions from metadata (fast - no full decode)
            // Uses image_size_getter which reads only file headers, not full pixel data
            int? width;
            int? height;
            try {
              final bytes = Uint8List.fromList(content);
              final sizeResult = ImageSizeGetter.getSizeResult(MemoryInput(bytes));
              final size = sizeResult.size;
              // Handle potential rotation (EXIF orientation)
              if (size.needRotate) {
                width = size.height;
                height = size.width;
              } else {
                width = size.width;
                height = size.height;
              }
            } catch (_) {
              // Silently continue without dimensions
            }
            
            final imageInfo = _ImageInfo(path: destPath, width: width, height: height);
            
            // Map the original path (relative in EPUB) to the image info
            // Store both the full path and common variants for matching
            imageInfoMap[file.name] = imageInfo;
            
            // Also store just the filename for simpler matching
            final baseName = file.name.split('/').last;
            imageInfoMap[baseName] = imageInfo;
            
            // Store without leading path separators
            if (file.name.startsWith('/')) {
              imageInfoMap[file.name.substring(1)] = imageInfo;
            }
            
            imageIndex++;
          } catch (e) {
            debugPrint('Failed to extract image ${file.name}: $e');
          }
        } else if (name.endsWith('.svg')) {
          // SVG files - extract but no dimensions
          final ext = '.svg';
          final destName = 'img_${imageIndex.toString().padLeft(4, '0')}$ext';
          final destPath = '${imagesDir.path}/$destName';
          
          try {
            final destFile = File(destPath);
            await destFile.writeAsBytes(file.content as List<int>, flush: true);
            
            final imageInfo = _ImageInfo(path: destPath);
            imageInfoMap[file.name] = imageInfo;
            
            final baseName = file.name.split('/').last;
            imageInfoMap[baseName] = imageInfo;
            
            if (file.name.startsWith('/')) {
              imageInfoMap[file.name.substring(1)] = imageInfo;
            }
            
            imageIndex++;
          } catch (e) {
            debugPrint('Failed to extract SVG ${file.name}: $e');
          }
        }
      }
      
      if (imageIndex > 0) {
        debugPrint('EpubParser: Extracted $imageIndex images for book $bookId');
      }
    } catch (e) {
      debugPrint('EpubParser: Failed to extract images: $e');
    }
    
    return imageInfoMap;
  }

  /// Replace <img> tags in HTML with figure placeholders.
  /// 
  /// The placeholder format is: [FIGURE:{imagePath}:{altText}:{width}:{height}]
  /// Width and height are included when available.
  /// This allows the text segmenter to create proper figure segments.
  String _replaceImagesWithPlaceholders(
    String html,
    String chapterFileName,
    Map<String, _ImageInfo> imageInfoMap,
  ) {
    // Simpler regex to match <img> tags
    final imgPattern = RegExp(r'<img[^>]*>', caseSensitive: false);
    
    final matches = imgPattern.allMatches(html).toList();
    if (matches.isEmpty) return html;
    
    debugPrint('EpubParser: Processing ${matches.length} images in $chapterFileName');
    
    var replacedCount = 0;
    final result = html.replaceAllMapped(imgPattern, (match) {
      final imgTag = match.group(0) ?? '';
      
      // Extract src attribute using separate patterns for single and double quotes
      final srcDoubleMatch = RegExp(r'src="([^"]*)"', caseSensitive: false).firstMatch(imgTag);
      final srcSingleMatch = RegExp(r"src='([^']*)'", caseSensitive: false).firstMatch(imgTag);
      final src = srcDoubleMatch?.group(1) ?? srcSingleMatch?.group(1);
      
      // Extract alt attribute using separate patterns for single and double quotes  
      final altDoubleMatch = RegExp(r'alt="([^"]*)"', caseSensitive: false).firstMatch(imgTag);
      final altSingleMatch = RegExp(r"alt='([^']*)'", caseSensitive: false).firstMatch(imgTag);
      var alt = altDoubleMatch?.group(1) ?? altSingleMatch?.group(1);
      
      if (src == null || src.isEmpty) {
        return '';
      }
      
      // Resolve the image info
      _ImageInfo? imageInfo = _resolveImageInfo(src, chapterFileName, imageInfoMap);
      
      if (imageInfo == null) {
        // Image not found in extracted images, skip
        return '';
      }
      
      // Clean alt text (remove special characters that could break parsing)
      alt = (alt ?? 'Image').replaceAll(':', ' ').replaceAll('[', '').replaceAll(']', '').trim();
      if (alt.isEmpty) alt = 'Image';
      
      // Build placeholder with optional dimensions
      String placeholder;
      if (imageInfo.width != null && imageInfo.height != null) {
        placeholder = ' $figurePlaceholderPrefix${imageInfo.path}:$alt:${imageInfo.width}:${imageInfo.height}$figurePlaceholderSuffix ';
      } else {
        placeholder = ' $figurePlaceholderPrefix${imageInfo.path}:$alt$figurePlaceholderSuffix ';
      }
      
      replacedCount++;
      // Return placeholder that will survive text stripping
      return placeholder;
    });
    
    debugPrint('EpubParser: Replaced $replacedCount images with placeholders');
    return result;
  }

  /// Resolve an image src attribute to image info with path and dimensions.
  _ImageInfo? _resolveImageInfo(
    String src,
    String chapterFileName,
    Map<String, _ImageInfo> imageInfoMap,
  ) {
    // Try direct lookup first
    if (imageInfoMap.containsKey(src)) {
      return imageInfoMap[src];
    }
    
    // Try just the filename
    final srcFileName = src.split('/').last;
    if (imageInfoMap.containsKey(srcFileName)) {
      return imageInfoMap[srcFileName];
    }
    
    // Try resolving relative to chapter path
    final chapterDir = chapterFileName.contains('/') 
        ? chapterFileName.substring(0, chapterFileName.lastIndexOf('/'))
        : '';
    
    if (chapterDir.isNotEmpty) {
      final relativePath = '$chapterDir/$src';
      if (imageInfoMap.containsKey(relativePath)) {
        return imageInfoMap[relativePath];
      }
      
      // Normalize path (handle ../)
      final normalizedPath = _normalizePath(relativePath);
      if (imageInfoMap.containsKey(normalizedPath)) {
        return imageInfoMap[normalizedPath];
      }
    }
    
    // Try without common prefixes
    for (final prefix in ['OEBPS/', 'EPUB/', 'OPS/', 'Content/']) {
      final withPrefix = '$prefix$src';
      if (imageInfoMap.containsKey(withPrefix)) {
        return imageInfoMap[withPrefix];
      }
      
      final withoutPrefix = src.replaceFirst(RegExp('^$prefix', caseSensitive: false), '');
      if (imageInfoMap.containsKey(withoutPrefix)) {
        return imageInfoMap[withoutPrefix];
      }
    }
    
    return null;
  }

  /// Normalize a path by resolving ../ segments.
  String _normalizePath(String path) {
    final parts = path.split('/');
    final result = <String>[];
    
    for (final part in parts) {
      if (part == '..') {
        if (result.isNotEmpty) result.removeLast();
      } else if (part != '.' && part.isNotEmpty) {
        result.add(part);
      }
    }
    
    return result.join('/');
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
