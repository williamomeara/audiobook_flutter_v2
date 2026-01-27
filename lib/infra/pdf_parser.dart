import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'package:core_domain/core_domain.dart';

import '../app/app_paths.dart';
import '../utils/text_normalizer.dart' as tts_normalizer;
import '../utils/boilerplate_remover.dart';
import '../utils/content_classifier.dart';
import '../utils/structure_analyzer.dart';

/// Parsed PDF result.
class ParsedPdf {
  const ParsedPdf({
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

/// PDF parser service.
/// 
/// Extracts text and metadata from PDF files for TTS playback.
/// Uses pdfrx library (PDFium-based) for cross-platform PDF support.
class PdfParser {
  const PdfParser(this._paths);

  // ignore: unused_field - will be used in Phase 5 for cover extraction
  final AppPaths _paths;

  /// Default number of pages per chapter when no outline is available.
  static const int _defaultPagesPerChapter = 20;

  /// Parse a PDF file and return structured content.
  Future<ParsedPdf> parseFromFile({
    required String pdfPath,
    required String bookId,
  }) async {
    final document = await PdfDocument.openFile(pdfPath);

    try {
      // Extract metadata
      final title = _extractTitle(document, pdfPath);
      final author = _extractAuthor(document);

      debugPrint('PdfParser: Parsing "$title" by $author');
      debugPrint('PdfParser: ${document.pages.length} pages');

      // Extract cover image from first page
      final coverPath = await _extractCover(document, bookId);
      if (coverPath != null) {
        debugPrint('PdfParser: Extracted cover to $coverPath');
      }

      // Extract text from all pages
      final pageTexts = await _extractAllPageTexts(document);
      debugPrint('PdfParser: Extracted text from ${pageTexts.length} pages');

      // Try to build chapters from outline, fallback to page-based
      final rawChapters = await _buildChapters(
        document: document,
        pageTexts: pageTexts,
        bookId: bookId,
      );

      debugPrint('PdfParser: Created ${rawChapters.length} raw chapters');

      // Apply smart text processing pipeline
      final chapters = _processChapters(rawChapters);
      debugPrint('PdfParser: ${chapters.length} chapters after processing');

      return ParsedPdf(
        title: title,
        author: author,
        coverPath: coverPath,
        chapters: chapters,
      );
    } finally {
      document.dispose();
    }
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
    debugPrint('PdfParser: Body matter range: $startIdx to $endIdx of ${rawChapters.length}');

    // Filter to body matter only
    var bodyChapters = rawChapters.sublist(startIdx, endIdx);

    // Detect repeated prefixes and suffixes across chapters
    final chapterContents = bodyChapters.map((ch) => ch.content).toList();
    final repeatedPrefix = BoilerplateRemover.detectRepeatedPrefix(chapterContents);
    final repeatedSuffix = BoilerplateRemover.detectRepeatedSuffix(chapterContents);
    if (repeatedPrefix != null) {
      debugPrint('PdfParser: Detected repeated prefix: "$repeatedPrefix"');
    }

    // Detect chapter-spanning boilerplate patterns
    final spanningBoilerplate = StructureAnalyzer.detectChapterSpanningBoilerplate(chapterContents);

    // Clean and normalize each chapter
    var chapterNumber = 0;
    bodyChapters = bodyChapters.map((chapter) {
      var content = chapter.content;

      // Apply PDF-specific cleaning first
      content = _cleanPdfText(content);

      // Remove detected repeated prefix
      if (repeatedPrefix != null) {
        content = BoilerplateRemover.removePrefix(content, repeatedPrefix);
      }

      // Remove detected repeated suffix
      if (repeatedSuffix != null) {
        content = BoilerplateRemover.removeSuffix(content, repeatedSuffix);
      }

      // Remove preliminary sections (transcriber notes, editor notes, etc.)
      final preliminary = StructureAnalyzer.extractPreliminarySection(content);
      if (preliminary != null) {
        content = content.replaceFirst(preliminary, '');
      }

      // Filter chapter-spanning boilerplate lines
      if (spanningBoilerplate.isNotEmpty) {
        content = content
            .split('\n')
            .where((line) => !spanningBoilerplate.contains(line.trim()))
            .join('\n');
      }

      // Remove per-chapter boilerplate (page numbers, scanner notes, etc.)
      content = BoilerplateRemover.cleanChapter(content);

      // Normalize text (quotes, dashes, ligatures, special chars)
      content = tts_normalizer.TextNormalizer.normalize(content);

      // Skip empty chapters after cleaning
      if (content.trim().isEmpty) return null;

      chapterNumber++;
      return Chapter(
        id: chapter.id,
        number: chapterNumber,
        title: chapter.title,
        content: content,
      );
    }).whereType<Chapter>().toList();

    return bodyChapters;
  }

  /// Extract cover image from the first page of the PDF.
  Future<String?> _extractCover(PdfDocument document, String bookId) async {
    if (document.pages.isEmpty) return null;

    try {
      final firstPage = document.pages[0];
      
      // Render page at a reasonable resolution for cover display
      // Target ~400x600 at 1.5x device pixel ratio = 600x900 rendered
      final pageWidth = firstPage.width;
      final pageHeight = firstPage.height;
      
      // Calculate scale to get approximately 600px width
      final targetWidth = 600.0;
      final scale = targetWidth / pageWidth;
      final renderWidth = (pageWidth * scale).round();
      final renderHeight = (pageHeight * scale).round();
      
      debugPrint('PdfParser: Rendering cover at ${renderWidth}x$renderHeight');
      
      // Render the page to an image
      final pdfImage = await firstPage.render(
        fullWidth: renderWidth.toDouble(),
        fullHeight: renderHeight.toDouble(),
        backgroundColor: const ui.Color(0xFFFFFFFF),
      );
      
      if (pdfImage == null) {
        debugPrint('PdfParser: Failed to render cover image');
        return null;
      }
      
      try {
        // Get the raw pixel data (RGBA format from pdfrx)
        final pixels = pdfImage.pixels;
        
        // Create image using the image package
        // pdfrx returns RGBA pixels, image package stores as AABBGGRR
        final image = img.Image(pdfImage.width, pdfImage.height);
        
        // Copy pixels - pdfrx uses RGBA, image package uses AABBGGRR in data
        for (var y = 0; y < pdfImage.height; y++) {
          for (var x = 0; x < pdfImage.width; x++) {
            final idx = (y * pdfImage.width + x) * 4;
            final r = pixels[idx];
            final g = pixels[idx + 1];
            final b = pixels[idx + 2];
            final a = pixels[idx + 3];
            // setPixelRgba expects int values 0-255
            image.setPixelRgba(x, y, r, g, b, a);
          }
        }
        
        final jpgBytes = img.encodeJpg(image, quality: 85);
        
        // Save to book directory
        final dir = _paths.bookDir(bookId);
        await dir.create(recursive: true);
        final dest = File('${dir.path}/cover.jpg');
        await dest.writeAsBytes(Uint8List.fromList(jpgBytes), flush: true);
        
        return dest.path;
      } finally {
        // Dispose the PdfImage to free native memory resources
        pdfImage.dispose();
      }
    } catch (e, st) {
      debugPrint('PdfParser: Cover extraction failed: $e');
      debugPrint('$st');
      return null;
    }
  }

  /// Clean PDF-specific text issues.
  ///
  /// Handles issues unique to PDF extraction:
  /// - Standalone page numbers
  /// - Hyphenated words at line breaks
  /// - Excessive whitespace
  /// - Common PDF artifacts
  /// - Publishing system artifacts (QXP, InDesign, etc.)
  String _cleanPdfText(String content) {
    var result = content;

    // Remove standalone page numbers (lines with just numbers)
    result = result.replaceAll(RegExp(r'^\s*\d{1,4}\s*$', multiLine: true), '');

    // Remove common page header/footer patterns
    // E.g., "Chapter 1 | Book Title" or "Page 42"
    result = result.replaceAll(
      RegExp(r'^(?:Page\s+)?\d+\s*$', multiLine: true, caseSensitive: false),
      '',
    );

    // Remove publishing system artifacts (QuarkXPress, InDesign, etc.)
    // E.g., "chapters 1-4.qxp 9/16/2010 3:09 PM Page 10"
    result = result.replaceAll(
      RegExp(
        r'[a-zA-Z0-9_\-\s]+\.(?:qxp|indd|qxd)\s+\d{1,2}/\d{1,2}/\d{2,4}\s+\d{1,2}:\d{2}\s*[AP]M\s+Page\s+\d+',
        caseSensitive: false,
      ),
      '',
    );

    // Remove layout/publishing artifacts without file extension
    // E.g., "sources:Layout 1 9/28/2010 12:56 PM Page 741" or "e-Index:Layout 1 9/28/2010 3:07 PM"
    result = result.replaceAll(
      RegExp(
        r'[a-zA-Z0-9_\-:]+Layout\s+\d+\s+\d{1,2}/\d{1,2}/\d{2,4}\s+\d{1,2}:\d{2}\s*[AP]M(?:\s+Page\s+\d+)?',
        caseSensitive: false,
      ),
      '',
    );

    // Remove standalone "Page N" patterns that might be at end of lines
    result = result.replaceAll(
      RegExp(r'\s+Page\s+\d+\s*$', multiLine: true),
      '',
    );

    // Fix hyphenated words at line breaks
    // "hyphen-\nated" -> "hyphenated"
    result = result.replaceAllMapped(
      RegExp(r'([a-zA-Z])-\s*\n\s*([a-zA-Z])'),
      (m) => '${m[1]}${m[2]}',
    );

    // Remove form feed characters (common in PDFs)
    result = result.replaceAll('\f', '\n\n');

    // Collapse multiple blank lines to double newline (paragraph break)
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // Collapse multiple spaces to single space
    result = result.replaceAll(RegExp(r' {2,}'), ' ');

    // Clean up lines that are just whitespace
    result = result.replaceAll(RegExp(r'^\s+$', multiLine: true), '');

    // Remove lines that look like footers (copyright, ISBN, etc.)
    result = result.replaceAll(
      RegExp(
        r'^(?:Copyright|ISBN|All rights reserved|Printed in).*$',
        multiLine: true,
        caseSensitive: false,
      ),
      '',
    );

    return result.trim();
  }

  /// Build chapters from PDF outline if available, otherwise use page-based splitting.
  Future<List<Chapter>> _buildChapters({
    required PdfDocument document,
    required List<String> pageTexts,
    required String bookId,
  }) async {
    // Try to load PDF outline (bookmarks/table of contents)
    final outline = await document.loadOutline();
    
    if (outline.isNotEmpty) {
      debugPrint('PdfParser: Found outline with ${outline.length} entries');
      final chapters = await _buildChaptersFromOutline(
        document: document,
        outline: outline,
        pageTexts: pageTexts,
        bookId: bookId,
      );
      
      // If outline produced chapters, use them
      if (chapters.isNotEmpty) {
        return chapters;
      }
      debugPrint('PdfParser: Outline produced no chapters, falling back to page-based');
    } else {
      debugPrint('PdfParser: No outline found, using page-based chapters');
    }
    
    // Fallback to page-based splitting
    return _buildChaptersFromPages(
      pageTexts: pageTexts,
      bookId: bookId,
      pagesPerChapter: _defaultPagesPerChapter,
    );
  }

  /// Build chapters based on PDF outline/bookmarks.
  Future<List<Chapter>> _buildChaptersFromOutline({
    required PdfDocument document,
    required List<PdfOutlineNode> outline,
    required List<String> pageTexts,
    required String bookId,
  }) async {
    // Flatten nested outline to get all entries with page numbers
    final flatOutline = _flattenOutline(outline);
    
    if (flatOutline.isEmpty) return [];
    
    // Sort by page number
    flatOutline.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    
    // Deduplicate entries pointing to the same page
    final deduped = <_OutlineEntry>[];
    for (final entry in flatOutline) {
      if (deduped.isEmpty || deduped.last.pageNumber != entry.pageNumber) {
        deduped.add(entry);
      } else if (entry.title.length > deduped.last.title.length) {
        // Prefer longer title if same page
        deduped[deduped.length - 1] = entry;
      }
    }
    
    final chapters = <Chapter>[];
    final totalPages = pageTexts.length;
    
    for (var i = 0; i < deduped.length; i++) {
      final entry = deduped[i];
      final startPage = entry.pageNumber;
      
      // End page is either next outline entry or end of document
      final endPage = (i + 1 < deduped.length) 
          ? deduped[i + 1].pageNumber 
          : totalPages;
      
      // Validate page range
      if (startPage < 0 || startPage >= totalPages) continue;
      final safeEndPage = min(endPage, totalPages);
      if (safeEndPage <= startPage) continue;
      
      // Extract text for this chapter
      final chapterContent = pageTexts
          .sublist(startPage, safeEndPage)
          .where((text) => text.isNotEmpty)
          .join('\n\n');
      
      if (chapterContent.trim().isEmpty) continue;
      
      final chapterNumber = chapters.length + 1;
      final title = entry.title.isNotEmpty 
          ? entry.title 
          : 'Chapter $chapterNumber';
      
      chapters.add(Chapter(
        id: '$bookId-ch-$chapterNumber-${generateId(length: 6)}',
        number: chapterNumber,
        title: title,
        content: chapterContent,
      ));
    }
    
    return chapters;
  }

  /// Flatten nested outline structure into a flat list with page numbers.
  List<_OutlineEntry> _flattenOutline(List<PdfOutlineNode> nodes, {int depth = 0}) {
    final result = <_OutlineEntry>[];
    
    for (final node in nodes) {
      // Get page number from destination
      final pageNumber = node.dest?.pageNumber;
      
      if (pageNumber != null && pageNumber >= 0) {
        result.add(_OutlineEntry(
          title: node.title.trim(),
          pageNumber: pageNumber,
          depth: depth,
        ));
      }
      
      // Recursively process children
      if (node.children.isNotEmpty) {
        result.addAll(_flattenOutline(node.children, depth: depth + 1));
      }
    }
    
    return result;
  }

  /// Extract title from PDF metadata or filename.
  String _extractTitle(PdfDocument document, String pdfPath) {
    // Try PDF metadata first
    // Note: pdfrx provides title via document properties
    // For now, fall back to filename extraction
    return _extractTitleFromPath(pdfPath);
  }

  /// Extract author from PDF metadata.
  String _extractAuthor(PdfDocument document) {
    // pdfrx doesn't expose author directly in the simple API
    // Would need to access document.catalog for XMP metadata
    return 'Unknown Author';
  }

  /// Extract title from file path.
  String _extractTitleFromPath(String path) {
    final filename = path.split(Platform.pathSeparator).last;
    // Remove extension
    final nameWithoutExt = filename.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    // Clean up common patterns like "(Author Name)" at the end
    final cleaned = nameWithoutExt
        .replaceAll(RegExp(r'\s*\([^)]+\)\s*$'), '') // Remove (Author) suffix
        .replaceAll(RegExp(r'\s*\[[^\]]+\]\s*$'), '') // Remove [Publisher] suffix
        .replaceAll(RegExp(r'\s*-\s*$'), '') // Remove trailing dash
        .trim();
    return cleaned.isNotEmpty ? cleaned : nameWithoutExt;
  }

  /// Extract text from all pages.
  Future<List<String>> _extractAllPageTexts(PdfDocument document) async {
    final pageTexts = <String>[];

    for (var i = 0; i < document.pages.length; i++) {
      final page = document.pages[i];
      try {
        final pageText = await page.loadText();
        final text = pageText.fullText;
        pageTexts.add(text.trim());
      } catch (e) {
        debugPrint('PdfParser: Failed to extract text from page ${i + 1}: $e');
        pageTexts.add('');
      }
    }

    return pageTexts;
  }

  /// Build chapters by grouping pages.
  /// 
  /// Simple strategy: group every N pages into a chapter.
  /// Later phases will use PDF outline for smarter chapter detection.
  List<Chapter> _buildChaptersFromPages({
    required List<String> pageTexts,
    required String bookId,
    required int pagesPerChapter,
  }) {
    if (pageTexts.isEmpty) return [];

    final chapters = <Chapter>[];
    final totalPages = pageTexts.length;
    var chapterNumber = 0;

    for (var startPage = 0; startPage < totalPages; startPage += pagesPerChapter) {
      final endPage = min(startPage + pagesPerChapter, totalPages);
      
      // Combine text from pages in this chapter
      final chapterContent = pageTexts
          .sublist(startPage, endPage)
          .where((text) => text.isNotEmpty)
          .join('\n\n');

      if (chapterContent.trim().isEmpty) continue;

      chapterNumber++;
      
      // Generate title based on page range
      final title = _generateChapterTitle(
        chapterNumber: chapterNumber,
        startPage: startPage + 1,
        endPage: endPage,
        totalPages: totalPages,
      );

      chapters.add(Chapter(
        id: '$bookId-ch-$chapterNumber-${generateId(length: 6)}',
        number: chapterNumber,
        title: title,
        content: chapterContent,
      ));
    }

    return chapters;
  }

  /// Generate a chapter title based on page range.
  String _generateChapterTitle({
    required int chapterNumber,
    required int startPage,
    required int endPage,
    required int totalPages,
  }) {
    if (startPage == endPage) {
      return 'Page $startPage';
    } else if (totalPages <= _defaultPagesPerChapter) {
      return 'Chapter $chapterNumber';
    } else {
      return 'Chapter $chapterNumber (pp. $startPage-$endPage)';
    }
  }
}

/// Helper class for flattened outline entries.
class _OutlineEntry {
  const _OutlineEntry({
    required this.title,
    required this.pageNumber,
    required this.depth,
  });

  final String title;
  final int pageNumber;
  final int depth;
}

/// PDF parser provider.
final pdfParserProvider = FutureProvider<PdfParser>((ref) async {
  final paths = await ref.watch(appPathsProvider.future);
  return PdfParser(paths);
});
