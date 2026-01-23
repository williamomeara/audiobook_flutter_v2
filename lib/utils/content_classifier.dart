import 'dart:math';

/// Classification for chapter/section content type
enum ContentType {
  /// Front matter: cover, title, copyright, dedication, TOC, etc.
  frontMatter,

  /// Body matter: actual story content (chapters, prologue, epilogue)
  bodyMatter,

  /// Back matter: about author, acknowledgments, index, etc.
  backMatter,
}

/// Lightweight chapter info for classification
class ChapterInfo {
  final String filename;
  final String title;
  final String contentSnippet;
  final String? epubType;

  ChapterInfo({
    required this.filename,
    required this.title,
    required this.contentSnippet,
    this.epubType,
  });
}

/// Classifies EPUB chapters into front/body/back matter.
///
/// Detection priority (highest to lowest):
/// 1. EPUB3 landmarks (epub:type attribute)
/// 2. Chapter title patterns
/// 3. Filename patterns
/// 4. Content analysis (first 500 chars)
class ContentClassifier {
  // Title patterns for front matter
  static final _frontMatterTitles = [
    RegExp(r'^cover$', caseSensitive: false),
    RegExp(r'^title\s*page$', caseSensitive: false),
    RegExp(r'^copyright', caseSensitive: false),
    RegExp(r'^table\s*of\s*contents$', caseSensitive: false),
    RegExp(r'^contents$', caseSensitive: false),
    RegExp(r'^dedication$', caseSensitive: false),
    RegExp(r'^epigraph$', caseSensitive: false),
    RegExp(r'^foreword$', caseSensitive: false),
    RegExp(r'^preface$', caseSensitive: false),
    RegExp(r'^also\s*by', caseSensitive: false),
    RegExp(r'^half[\s-]?title', caseSensitive: false),
    RegExp(r'^dramatis\s*personae$', caseSensitive: false),
    RegExp(r'^list\s*of\s*characters$', caseSensitive: false),
  ];

  // Title patterns for back matter
  static final _backMatterTitles = [
    RegExp(r'^about\s*(the\s*)?author', caseSensitive: false),
    RegExp("^author(['\u2019])?s?\\s*note", caseSensitive: false),
    RegExp(r'^acknowledgments?$', caseSensitive: false),
    RegExp(r'^bibliography$', caseSensitive: false),
    RegExp(r'^notes$', caseSensitive: false),
    RegExp(r'^end\s*notes?$', caseSensitive: false),
    RegExp(r'^index$', caseSensitive: false),
    RegExp(r'^appendix', caseSensitive: false),
    RegExp(r'^glossary$', caseSensitive: false),
    RegExp(r'^also\s*by', caseSensitive: false),
    RegExp(r'^further\s*reading', caseSensitive: false),
    RegExp("^reader(['\u2019])?s?\\s*guide", caseSensitive: false),
    RegExp(r'^discussion\s*questions?', caseSensitive: false),
    RegExp(r'^newsletter', caseSensitive: false),
    RegExp(r'^discover\s*(your\s*)?next', caseSensitive: false),
  ];

  // Title patterns that indicate body matter (story content)
  static final _bodyMatterTitles = [
    RegExp(r'^chapter\s*\d', caseSensitive: false),
    RegExp(r'^chapter\s+[ivxlc]+', caseSensitive: false), // Roman numerals
    RegExp(r'^part\s*\d', caseSensitive: false),
    RegExp(r'^part\s+[ivxlc]+', caseSensitive: false),
    RegExp(r'^book\s*\d', caseSensitive: false),
    RegExp(r'^book\s+[ivxlc]+', caseSensitive: false),
    RegExp(r'^prologue$', caseSensitive: false),
    RegExp(r'^epilogue$', caseSensitive: false),
    RegExp(r'^interlude', caseSensitive: false),
    RegExp(r'^\d+$'), // Just a number (chapter number)
    RegExp(r'^[ivxlc]+$', caseSensitive: false), // Just roman numerals
  ];

  // Filename patterns for front matter
  static final _frontMatterFiles = [
    RegExp(r'cover\.', caseSensitive: false),
    RegExp(r'_cov[._]', caseSensitive: false),
    RegExp(r'title', caseSensitive: false),
    RegExp(r'_tp[._]', caseSensitive: false),
    RegExp(r'copyright', caseSensitive: false),
    RegExp(r'_cop[._]', caseSensitive: false),
    RegExp(r'toc\.', caseSensitive: false),
    RegExp(r'_toc[._]', caseSensitive: false),
    RegExp(r'contents', caseSensitive: false),
    RegExp(r'dedication', caseSensitive: false),
    RegExp(r'_ded[._]', caseSensitive: false),
    RegExp(r'frontmatter', caseSensitive: false),
    RegExp(r'front[_-]matter', caseSensitive: false),
    RegExp(r'epigraph', caseSensitive: false),
    RegExp(r'halftitle', caseSensitive: false),
  ];

  // Filename patterns for back matter
  static final _backMatterFiles = [
    RegExp(r'about[_-]?the[_-]?author', caseSensitive: false),
    RegExp(r'acknowledgment', caseSensitive: false),
    RegExp(r'bibliography', caseSensitive: false),
    RegExp(r'appendix', caseSensitive: false),
    RegExp(r'glossary', caseSensitive: false),
    RegExp(r'backmatter', caseSensitive: false),
    RegExp(r'back[_-]matter', caseSensitive: false),
    RegExp(r'next-reads', caseSensitive: false),
  ];

  // Content patterns for front matter
  static final _frontMatterContent = [
    RegExp(r'copyright\s*[©\u00A9]', caseSensitive: false),
    RegExp(r'all\s*rights\s*reserved', caseSensitive: false),
    RegExp(r'\bISBN\b', caseSensitive: false),
    RegExp(r'published\s*by', caseSensitive: false),
    RegExp(r'library\s*of\s*congress', caseSensitive: false),
    RegExp(r'printed\s*in', caseSensitive: false),
    RegExp(r'first\s*(edition|published)', caseSensitive: false),
    RegExp(r'for\s+my\s+', caseSensitive: false), // Dedication pattern
  ];

  // Content patterns for back matter
  static final _backMatterContent = [
    RegExp(r'is\s*(the\s*)?author\s*of', caseSensitive: false),
    RegExp(r'lives?\s*in\s*\w+', caseSensitive: false), // Author bio pattern
    RegExp(r'born\s*in\s*\d{4}', caseSensitive: false),
    RegExp(r'visit\s*(the\s*)?author', caseSensitive: false),
    RegExp(r'follow\s*(the\s*)?author', caseSensitive: false),
  ];

  /// Classify a single chapter based on available metadata and content.
  static ContentType classify({
    required String filename,
    required String title,
    required String contentSnippet,
    String? epubType,
  }) {
    // 1. EPUB3 landmarks (highest priority)
    if (epubType != null && epubType.isNotEmpty) {
      final type = epubType.toLowerCase();
      if (type.contains('frontmatter') ||
          type.contains('cover') ||
          type.contains('titlepage') ||
          type.contains('copyright') ||
          type.contains('toc') ||
          type.contains('dedication') ||
          type.contains('epigraph') ||
          type.contains('foreword') ||
          type.contains('preface')) {
        return ContentType.frontMatter;
      }
      if (type.contains('backmatter') ||
          type.contains('appendix') ||
          type.contains('glossary') ||
          type.contains('index') ||
          type.contains('colophon') ||
          type.contains('afterword')) {
        return ContentType.backMatter;
      }
      if (type.contains('bodymatter') ||
          type.contains('chapter') ||
          type.contains('part') ||
          type.contains('prologue') ||
          type.contains('epilogue')) {
        return ContentType.bodyMatter;
      }
    }

    // 2. Title matching - check body matter first (more specific)
    final normalizedTitle = title.trim();
    for (final pattern in _bodyMatterTitles) {
      if (pattern.hasMatch(normalizedTitle)) return ContentType.bodyMatter;
    }
    for (final pattern in _frontMatterTitles) {
      if (pattern.hasMatch(normalizedTitle)) return ContentType.frontMatter;
    }
    for (final pattern in _backMatterTitles) {
      if (pattern.hasMatch(normalizedTitle)) return ContentType.backMatter;
    }

    // 3. Filename matching
    for (final pattern in _frontMatterFiles) {
      if (pattern.hasMatch(filename)) return ContentType.frontMatter;
    }
    for (final pattern in _backMatterFiles) {
      if (pattern.hasMatch(filename)) return ContentType.backMatter;
    }

    // 4. Content analysis (first 500 chars)
    final snippet = contentSnippet.length > 500
        ? contentSnippet.substring(0, 500)
        : contentSnippet;
    for (final pattern in _frontMatterContent) {
      if (pattern.hasMatch(snippet)) return ContentType.frontMatter;
    }
    for (final pattern in _backMatterContent) {
      if (pattern.hasMatch(snippet)) return ContentType.backMatter;
    }

    // 5. Default to body matter
    return ContentType.bodyMatter;
  }

  /// Find the range of body matter chapters (start index, end index).
  ///
  /// Scans forward to find the first body matter chapter,
  /// then scans backward to find where back matter begins.
  ///
  /// Returns (startIndex, endIndex) where endIndex is exclusive.
  static (int, int) findBodyMatterRange(List<ChapterInfo> chapters) {
    if (chapters.isEmpty) return (0, 0);

    // Find first body matter chapter (scan forward)
    int startIndex = 0;
    for (int i = 0; i < chapters.length; i++) {
      final type = classify(
        filename: chapters[i].filename,
        title: chapters[i].title,
        contentSnippet: chapters[i].contentSnippet,
        epubType: chapters[i].epubType,
      );
      if (type == ContentType.bodyMatter) {
        startIndex = i;
        break;
      }
    }

    // Find where back matter starts (scan backward)
    // Look for the last body matter chapter
    int endIndex = chapters.length;
    for (int i = chapters.length - 1; i >= startIndex; i--) {
      final type = classify(
        filename: chapters[i].filename,
        title: chapters[i].title,
        contentSnippet: chapters[i].contentSnippet,
        epubType: chapters[i].epubType,
      );
      if (type == ContentType.bodyMatter) {
        endIndex = i + 1;
        break;
      }
    }

    // Ensure valid range
    if (startIndex >= endIndex) {
      // No valid body matter found - return all chapters as fallback
      return (0, chapters.length);
    }

    return (startIndex, endIndex);
  }

  /// Classify all chapters and return a list of classifications.
  static List<ContentType> classifyAll(List<ChapterInfo> chapters) {
    return chapters
        .map((ch) => classify(
              filename: ch.filename,
              title: ch.title,
              contentSnippet: ch.contentSnippet,
              epubType: ch.epubType,
            ))
        .toList();
  }

  /// Filter chapters to only include body matter.
  ///
  /// Returns a new list containing only body matter chapters.
  static List<T> filterToBodyMatter<T>(
    List<T> chapters,
    List<ChapterInfo> chapterInfos,
  ) {
    if (chapters.length != chapterInfos.length) {
      throw ArgumentError(
          'chapters and chapterInfos must have the same length');
    }

    final (startIndex, endIndex) = findBodyMatterRange(chapterInfos);
    return chapters.sublist(startIndex, endIndex);
  }
}
