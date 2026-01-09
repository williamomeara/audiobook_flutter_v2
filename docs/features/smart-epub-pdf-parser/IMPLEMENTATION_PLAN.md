# Smart EPUB/PDF Parser - Implementation Plan

## Executive Summary

This plan outlines a phased approach to improve EPUB/PDF text extraction for TTS (Text-to-Speech). The goals are:

1. **Clean text output** - Normalize typography for TTS (quotes, dashes, ligatures)
2. **Smart content filtering** - Skip front/back matter, start at actual story
3. **Boilerplate removal** - Remove Project Gutenberg headers, scanner notes, etc.
4. **Reliable sentence segmentation** - Proper boundaries for TTS synthesis

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Implementation Phases (Ordered)](#implementation-phases)
   - [Phase 1: Text Normalizer Core](#phase-1-text-normalizer-core)
   - [Phase 2: Boilerplate Removal](#phase-2-boilerplate-removal)
   - [Phase 3: Content Classification](#phase-3-content-classification)
   - [Phase 4: Parser Integration](#phase-4-parser-integration)
   - [Phase 5: Sentence Segmentation](#phase-5-sentence-segmentation)
   - [Phase 6: Testing & Validation](#phase-6-testing--validation)
3. [Character Mapping Reference](#character-mapping-reference)
4. [Pattern Reference](#pattern-reference)
5. [Architecture Overview](#architecture-overview)
6. [Timeline & Priorities](#timeline--priorities)

---

## Current State Analysis

### Existing Code

**Location**: `lib/infra/epub_parser.dart`

Current capabilities:
- Uses `epubx` package for EPUB parsing
- `_stripHtmlToText()` - Removes HTML tags
- `_decodeHtmlEntities()` - Basic entity decoding

Missing capabilities:
- Unicode/typography normalization
- Front matter detection
- Boilerplate removal
- Smart sentence segmentation

### Problems Found in Sample Books

From `local_dev/dev_books/` analysis:

| Character | Unicode | Found In |
|-----------|---------|----------|
| ' (curly apostrophe) | U+2019 | Gideon The Ninth, Kindred |
| " " (curly quotes) | U+201C/D | Most books |
| — (em-dash) | U+2014 | All books |
| … (ellipsis) | U+2026 | Most books |
| ﬁ ﬂ (ligatures) | U+FB01/02 | Some PDFs |

---

## Implementation Phases

### Why This Order?

1. **Text Normalizer** first - It's the foundation; all other features need clean text
2. **Boilerplate Removal** second - Must happen before content analysis (PG headers confuse classifiers)
3. **Content Classification** third - Depends on clean text to analyze content
4. **Parser Integration** fourth - Wires everything together
5. **Sentence Segmentation** fifth - Refinement layer, needs all above working
6. **Testing** last - Validates the complete pipeline

---

## Phase 1: Text Normalizer Core

**Goal**: Create a utility that normalizes typography for TTS compatibility.

**File**: `lib/utils/text_normalizer.dart`

### 1.1 Design

```dart
/// Normalizes text for TTS consumption.
/// Handles: quotes, dashes, ligatures, spaces, symbols
class TextNormalizer {
  // Compiled patterns for performance
  static final _quotePattern = RegExp(r'[\u2018\u2019\u201A\u201B\u0060\u00B4]');
  static final _doubleQuotePattern = RegExp(r'[\u201C\u201D\u201E\u201F\u00AB\u00BB]');
  static final _dashPattern = RegExp(r'[\u2014\u2013\u2010\u2011\u2212]');
  static final _zeroWidthPattern = RegExp(r'[\u200B\u200C\u200D\uFEFF]');
  static final _spacePattern = RegExp(r'[\u00A0\u202F\u2009\u200A\u2002\u2003\u2007]');
  
  /// Main entry point - applies all normalizations
  static String normalize(String text) {
    if (text.isEmpty) return text;
    
    var result = text;
    
    // Order matters: simpler replacements first
    result = _normalizeQuotes(result);
    result = _normalizeDashes(result);
    result = _normalizeEllipsis(result);
    result = _normalizeLigatures(result);
    result = _normalizeSpaces(result);
    result = _normalizeSymbols(result);
    result = _cleanWhitespace(result);
    
    return result;
  }
  
  static String _normalizeQuotes(String text) {
    var result = text.replaceAll(_quotePattern, "'");
    return result.replaceAll(_doubleQuotePattern, '"');
  }
  
  static String _normalizeDashes(String text) {
    // Em-dash with spaces for natural TTS pause
    var result = text.replaceAll('\u2014', ' - ');
    // Other dashes to hyphen
    return result.replaceAll(_dashPattern, '-');
  }
  
  static String _normalizeEllipsis(String text) {
    return text.replaceAll('\u2026', '...');
  }
  
  static String _normalizeLigatures(String text) {
    return text
      .replaceAll('\uFB01', 'fi')
      .replaceAll('\uFB02', 'fl')
      .replaceAll('\uFB00', 'ff')
      .replaceAll('\uFB03', 'ffi')
      .replaceAll('\uFB04', 'ffl')
      .replaceAll('\u0152', 'OE')
      .replaceAll('\u0153', 'oe')
      .replaceAll('\u00C6', 'AE')
      .replaceAll('\u00E6', 'ae');
  }
  
  static String _normalizeSpaces(String text) {
    // Remove zero-width characters
    var result = text.replaceAll(_zeroWidthPattern, '');
    // Normalize various spaces to regular space
    return result.replaceAll(_spacePattern, ' ');
  }
  
  static String _normalizeSymbols(String text) {
    return text
      .replaceAll('\u00BD', '1/2')
      .replaceAll('\u00BC', '1/4')
      .replaceAll('\u00BE', '3/4')
      .replaceAll('\u00A9', '(c)')
      .replaceAll('\u00AE', '(R)')
      .replaceAll('\u2122', '(TM)')
      .replaceAll('\u2116', 'No.')
      .replaceAll('\u2022', '*')
      .replaceAll('\u2023', '*')
      .replaceAll('\u00B7', '.');
  }
  
  static String _cleanWhitespace(String text) {
    // Collapse multiple spaces
    var result = text.replaceAll(RegExp(r' {2,}'), ' ');
    // Collapse multiple newlines (keep paragraph breaks)
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return result.trim();
  }
}
```

### 1.2 Test File

**File**: `test/utils/text_normalizer_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/utils/text_normalizer.dart';

void main() {
  group('TextNormalizer', () {
    group('quotes', () {
      test('normalizes curly single quotes', () {
        expect(TextNormalizer.normalize("it's"), equals("it's"));
        expect(TextNormalizer.normalize("'hello'"), equals("'hello'"));
      });
      
      test('normalizes curly double quotes', () {
        expect(TextNormalizer.normalize('"hello"'), equals('"hello"'));
      });
      
      test('normalizes guillemets', () {
        expect(TextNormalizer.normalize('«bonjour»'), equals('"bonjour"'));
      });
    });
    
    group('dashes', () {
      test('normalizes em-dash with spaces', () {
        expect(TextNormalizer.normalize('word—word'), equals('word - word'));
      });
      
      test('normalizes en-dash', () {
        expect(TextNormalizer.normalize('pages 1–5'), equals('pages 1-5'));
      });
    });
    
    group('ellipsis', () {
      test('expands unicode ellipsis', () {
        expect(TextNormalizer.normalize('wait…'), equals('wait...'));
      });
    });
    
    group('ligatures', () {
      test('expands fi ligature', () {
        expect(TextNormalizer.normalize('ﬁnd'), equals('find'));
      });
      
      test('expands fl ligature', () {
        expect(TextNormalizer.normalize('ﬂow'), equals('flow'));
      });
    });
    
    group('spaces', () {
      test('removes zero-width characters', () {
        expect(TextNormalizer.normalize('hel\u200Blo'), equals('hello'));
      });
      
      test('normalizes non-breaking space', () {
        expect(TextNormalizer.normalize('hello\u00A0world'), equals('hello world'));
      });
    });
    
    group('whitespace', () {
      test('collapses multiple spaces', () {
        expect(TextNormalizer.normalize('hello    world'), equals('hello world'));
      });
      
      test('preserves paragraph breaks', () {
        expect(TextNormalizer.normalize('para1\n\npara2'), equals('para1\n\npara2'));
      });
    });
  });
}
```

### 1.3 Deliverables

- [ ] `lib/utils/text_normalizer.dart`
- [ ] `test/utils/text_normalizer_test.dart`
- [ ] All tests passing

**Estimated Time**: 2-3 hours

---

## Phase 2: Boilerplate Removal

**Goal**: Remove Project Gutenberg headers/footers and other ebook boilerplate.

**File**: `lib/utils/boilerplate_remover.dart`

### Why Before Content Classification?

Project Gutenberg files have headers like:
```
*** START OF THIS PROJECT GUTENBERG EBOOK PRIDE AND PREJUDICE ***
```

If we try to classify content before removing this, the copyright/license text confuses our classifiers.

### 2.1 Design

```dart
/// Removes boilerplate text from ebook content.
/// Handles: Project Gutenberg, scanner notes, source attribution
class BoilerplateRemover {
  // Project Gutenberg markers
  static final _pgStartMarkers = [
    RegExp(r'\*{3}\s*START OF (THIS|THE) PROJECT GUTENBERG EBOOK.*?\*{3}', 
           caseSensitive: false, dotAll: true),
    RegExp(r'The Project Gutenberg E-?[Bb]ook of[^.]+\.', caseSensitive: false),
    RegExp(r'This eBook is for the use of anyone anywhere', caseSensitive: false),
  ];
  
  static final _pgEndMarkers = [
    RegExp(r'\*{3}\s*END OF (THIS|THE) PROJECT GUTENBERG EBOOK.*?\*{3}', 
           caseSensitive: false),
    RegExp(r'End of (the )?Project Gutenberg', caseSensitive: false),
  ];
  
  // Content-based boilerplate indicators
  static final _boilerplateIndicators = [
    RegExp(r'produced by', caseSensitive: false),
    RegExp(r'this file should be named', caseSensitive: false),
    RegExp(r'www\.gutenberg\.org', caseSensitive: false),
    RegExp(r'public domain', caseSensitive: false),
    RegExp(r'scanned by', caseSensitive: false),
    RegExp(r'proofread by', caseSensitive: false),
    RegExp(r'digitized by', caseSensitive: false),
    RegExp(r'ocr\s*(errors|quality)', caseSensitive: false),
    RegExp(r'z-library', caseSensitive: false),
    RegExp(r'libgen', caseSensitive: false),
    RegExp(r'^\s*\d+\s*$'), // Page numbers only
  ];
  
  /// Remove boilerplate from full book text
  static String removeFromBook(String content) {
    var result = content;
    
    // Find and remove PG header (everything before START marker)
    for (final pattern in _pgStartMarkers) {
      final match = pattern.firstMatch(result);
      if (match != null) {
        result = result.substring(match.end).trimLeft();
        break;
      }
    }
    
    // Find and remove PG footer (everything after END marker)
    for (final pattern in _pgEndMarkers) {
      final match = pattern.firstMatch(result);
      if (match != null) {
        result = result.substring(0, match.start).trimRight();
        break;
      }
    }
    
    return result;
  }
  
  /// Remove boilerplate paragraphs from chapter content
  static String cleanChapter(String content) {
    final paragraphs = content.split(RegExp(r'\n\s*\n'));
    
    // Filter leading boilerplate (max 3 paragraphs)
    int startIdx = 0;
    for (int i = 0; i < paragraphs.length && i < 3; i++) {
      if (_isBoilerplate(paragraphs[i])) {
        startIdx = i + 1;
      } else {
        break;
      }
    }
    
    // Filter trailing boilerplate (max 3 paragraphs)
    int endIdx = paragraphs.length;
    for (int i = paragraphs.length - 1; i >= startIdx && i >= paragraphs.length - 3; i--) {
      if (_isBoilerplate(paragraphs[i])) {
        endIdx = i;
      } else {
        break;
      }
    }
    
    if (startIdx >= endIdx) return content; // Safety: don't remove everything
    
    return paragraphs.sublist(startIdx, endIdx).join('\n\n');
  }
  
  static bool _isBoilerplate(String paragraph) {
    final trimmed = paragraph.trim();
    if (trimmed.isEmpty) return true;
    if (trimmed.length < 10) return false; // Too short to judge
    
    for (final pattern in _boilerplateIndicators) {
      if (pattern.hasMatch(trimmed)) return true;
    }
    return false;
  }
  
  /// Detect repeated text across chapters (statistical approach)
  static String? detectRepeatedPrefix(List<String> chapterContents) {
    if (chapterContents.length < 3) return null;
    
    final prefixes = <String, int>{};
    for (final content in chapterContents) {
      final firstLine = content.split('\n').first.trim();
      if (firstLine.length > 10 && firstLine.length < 200) {
        prefixes[firstLine] = (prefixes[firstLine] ?? 0) + 1;
      }
    }
    
    // If same prefix in >50% of chapters, it's boilerplate
    for (final entry in prefixes.entries) {
      if (entry.value > chapterContents.length * 0.5) {
        return entry.key;
      }
    }
    return null;
  }
}
```

### 2.2 Test File

**File**: `test/utils/boilerplate_remover_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/utils/boilerplate_remover.dart';

void main() {
  group('BoilerplateRemover', () {
    group('removeFromBook', () {
      test('removes Project Gutenberg header', () {
        const input = '''
The Project Gutenberg EBook of Test, by Author

*** START OF THIS PROJECT GUTENBERG EBOOK TEST ***

Chapter 1

The story begins here.
''';
        final result = BoilerplateRemover.removeFromBook(input);
        expect(result, startsWith('Chapter 1'));
        expect(result, isNot(contains('Project Gutenberg')));
      });
      
      test('removes Project Gutenberg footer', () {
        const input = '''
The end of the story.

*** END OF THIS PROJECT GUTENBERG EBOOK TEST ***

This file should be named test.txt
''';
        final result = BoilerplateRemover.removeFromBook(input);
        expect(result, endsWith('The end of the story.'));
      });
    });
    
    group('cleanChapter', () {
      test('removes scanner notes from chapter start', () {
        const input = '''
Scanned by Archive.org

Chapter 1

The story begins.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, startsWith('Chapter 1'));
      });
      
      test('preserves valid content', () {
        const input = '''
Chapter 1

The story begins here.

And continues here.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, equals(input.trim()));
      });
    });
  });
}
```

### 2.3 Deliverables

- [ ] `lib/utils/boilerplate_remover.dart`
- [ ] `test/utils/boilerplate_remover_test.dart`
- [ ] All tests passing

**Estimated Time**: 2-3 hours

---

## Phase 3: Content Classification

**Goal**: Identify and filter front matter, body matter, and back matter.

**File**: `lib/utils/content_classifier.dart`

### 3.1 Research Summary

From Standard Ebooks Tools and zlibrary-mcp:

**Front Matter** (skip):
- Cover, title page, copyright, dedication, acknowledgments
- Table of contents, epigraph, half-title
- "Also by this author", foreword (sometimes)

**Body Matter** (keep):
- Prologue, chapters, parts, interludes
- Epilogue (usually)

**Back Matter** (skip):
- About the author, acknowledgments (when at end)
- Bibliography, notes, index, appendix

### 3.2 Detection Strategy

Priority order (most reliable first):

1. **EPUB3 Landmarks** - Explicit `epub:type` attributes
2. **Chapter Titles** - Pattern matching on titles
3. **Filename Patterns** - Naming conventions
4. **Content Analysis** - First 500 chars of each chapter

### 3.3 Design

```dart
/// Content classification for EPUB chapters
enum ContentType {
  frontMatter,
  bodyMatter,
  backMatter,
}

/// Classifies chapters into front/body/back matter
class ContentClassifier {
  // Title patterns for front matter
  static final _frontMatterTitles = [
    RegExp(r'^cover$', caseSensitive: false),
    RegExp(r'^title\s*page$', caseSensitive: false),
    RegExp(r'^copyright', caseSensitive: false),
    RegExp(r'^table\s*of\s*contents$', caseSensitive: false),
    RegExp(r'^contents$', caseSensitive: false),
    RegExp(r'^dedication$', caseSensitive: false),
    RegExp(r'^acknowledgments?$', caseSensitive: false),
    RegExp(r'^about\s*the\s*author$', caseSensitive: false),
    RegExp(r'^also\s*by', caseSensitive: false),
    RegExp(r'^epigraph$', caseSensitive: false),
    RegExp(r'^foreword$', caseSensitive: false),
    RegExp(r'^half[\s-]?title', caseSensitive: false),
  ];
  
  // Title patterns for back matter
  static final _backMatterTitles = [
    RegExp(r'^about\s*the\s*author', caseSensitive: false),
    RegExp(r'^acknowledgments?$', caseSensitive: false),
    RegExp(r'^bibliography$', caseSensitive: false),
    RegExp(r'^notes$', caseSensitive: false),
    RegExp(r'^end\s*notes?$', caseSensitive: false),
    RegExp(r'^index$', caseSensitive: false),
    RegExp(r'^appendix', caseSensitive: false),
    RegExp(r'^glossary$', caseSensitive: false),
    RegExp(r'^also\s*by', caseSensitive: false),
    RegExp(r'^further\s*reading', caseSensitive: false),
  ];
  
  // Filename patterns for front matter
  static final _frontMatterFiles = [
    RegExp(r'cover\.', caseSensitive: false),
    RegExp(r'title', caseSensitive: false),
    RegExp(r'copyright', caseSensitive: false),
    RegExp(r'toc\.', caseSensitive: false),
    RegExp(r'contents', caseSensitive: false),
    RegExp(r'dedication', caseSensitive: false),
    RegExp(r'front', caseSensitive: false),
    RegExp(r'epigraph', caseSensitive: false),
    RegExp(r'halftitle', caseSensitive: false),
  ];
  
  // Content patterns for front matter
  static final _frontMatterContent = [
    RegExp(r'copyright\s*©', caseSensitive: false),
    RegExp(r'all\s*rights\s*reserved', caseSensitive: false),
    RegExp(r'\bISBN\b', caseSensitive: false),
    RegExp(r'published\s*by', caseSensitive: false),
    RegExp(r'library\s*of\s*congress', caseSensitive: false),
    RegExp(r'printed\s*in', caseSensitive: false),
    RegExp(r'first\s*(edition|published)', caseSensitive: false),
  ];
  
  /// Classify a single chapter
  static ContentType classify({
    required String filename,
    required String title,
    required String contentSnippet,
    String? epubType,
  }) {
    // 1. EPUB3 landmarks (highest priority)
    if (epubType != null) {
      if (epubType.contains('frontmatter') || 
          epubType.contains('cover') ||
          epubType.contains('titlepage') ||
          epubType.contains('copyright') ||
          epubType.contains('toc')) {
        return ContentType.frontMatter;
      }
      if (epubType.contains('backmatter') ||
          epubType.contains('appendix') ||
          epubType.contains('glossary') ||
          epubType.contains('index')) {
        return ContentType.backMatter;
      }
      if (epubType.contains('bodymatter') ||
          epubType.contains('chapter') ||
          epubType.contains('part')) {
        return ContentType.bodyMatter;
      }
    }
    
    // 2. Title matching
    final normalizedTitle = title.trim();
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
    
    // 4. Content analysis (first 500 chars)
    final snippet = contentSnippet.length > 500 
        ? contentSnippet.substring(0, 500) 
        : contentSnippet;
    for (final pattern in _frontMatterContent) {
      if (pattern.hasMatch(snippet)) return ContentType.frontMatter;
    }
    
    // 5. Default to body matter
    return ContentType.bodyMatter;
  }
  
  /// Filter chapters to extract body matter only
  /// Returns a tuple of (startIndex, endIndex) for the body matter range
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
    int endIndex = chapters.length;
    for (int i = chapters.length - 1; i >= startIndex; i--) {
      final type = classify(
        filename: chapters[i].filename,
        title: chapters[i].title,
        contentSnippet: chapters[i].contentSnippet,
        epubType: chapters[i].epubType,
      );
      if (type != ContentType.backMatter) {
        endIndex = i + 1;
        break;
      }
    }
    
    return (startIndex, endIndex);
  }
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
```

### 3.4 Test File

**File**: `test/utils/content_classifier_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/utils/content_classifier.dart';

void main() {
  group('ContentClassifier', () {
    group('classify', () {
      test('identifies copyright page by title', () {
        final result = ContentClassifier.classify(
          filename: 'page1.xhtml',
          title: 'Copyright',
          contentSnippet: 'Some text here',
        );
        expect(result, equals(ContentType.frontMatter));
      });
      
      test('identifies chapter as body matter', () {
        final result = ContentClassifier.classify(
          filename: 'chapter1.xhtml',
          title: 'Chapter 1',
          contentSnippet: 'The story begins on a dark night.',
        );
        expect(result, equals(ContentType.bodyMatter));
      });
      
      test('identifies about the author as back matter', () {
        final result = ContentClassifier.classify(
          filename: 'author.xhtml',
          title: 'About the Author',
          contentSnippet: 'Jane Smith lives in New York.',
        );
        expect(result, equals(ContentType.backMatter));
      });
      
      test('detects ISBN in content', () {
        final result = ContentClassifier.classify(
          filename: 'page2.xhtml',
          title: '',
          contentSnippet: 'Published 2023. ISBN 978-0-123456-78-9',
        );
        expect(result, equals(ContentType.frontMatter));
      });
      
      test('respects epub:type over other signals', () {
        final result = ContentClassifier.classify(
          filename: 'chapter.xhtml',
          title: 'Chapter 1',
          contentSnippet: 'Story content',
          epubType: 'frontmatter',
        );
        expect(result, equals(ContentType.frontMatter));
      });
    });
    
    group('findBodyMatterRange', () {
      test('skips front matter and back matter', () {
        final chapters = [
          ChapterInfo(filename: 'cover.xhtml', title: 'Cover', contentSnippet: ''),
          ChapterInfo(filename: 'copyright.xhtml', title: 'Copyright', contentSnippet: 'All rights reserved'),
          ChapterInfo(filename: 'ch1.xhtml', title: 'Chapter 1', contentSnippet: 'Story begins'),
          ChapterInfo(filename: 'ch2.xhtml', title: 'Chapter 2', contentSnippet: 'Story continues'),
          ChapterInfo(filename: 'about.xhtml', title: 'About the Author', contentSnippet: 'Bio'),
        ];
        
        final (start, end) = ContentClassifier.findBodyMatterRange(chapters);
        expect(start, equals(2)); // Chapter 1
        expect(end, equals(4));   // After Chapter 2
      });
    });
  });
}
```

### 3.5 Deliverables

- [ ] `lib/utils/content_classifier.dart`
- [ ] `test/utils/content_classifier_test.dart`
- [ ] All tests passing

**Estimated Time**: 3-4 hours

---

## Phase 4: Parser Integration

**Goal**: Wire all utilities into the EPUB parser pipeline.

**File**: Modify `lib/infra/epub_parser.dart`

### 4.1 Integration Points

The parsing pipeline order:

```
1. Extract chapters from EPUB (existing)
2. Remove boilerplate from full book (if single-file format)
3. Classify chapters → find body matter range
4. Filter to body matter only
5. Clean each chapter (remove chapter-level boilerplate)
6. Normalize text in each chapter
7. Return cleaned chapters
```

### 4.2 Changes to epub_parser.dart

```dart
import '../utils/text_normalizer.dart';
import '../utils/boilerplate_remover.dart';
import '../utils/content_classifier.dart';

// In the parsing method:
Future<ParsedEpub> parseFromFile({...}) async {
  // ... existing EPUB extraction ...
  
  // Build chapter info for classification
  final chapterInfos = chapters.map((c) => ChapterInfo(
    filename: c.id,
    title: c.title,
    contentSnippet: c.content.substring(0, min(500, c.content.length)),
    epubType: c.epubType, // If available from parsing
  )).toList();
  
  // Find body matter range
  final (startIdx, endIdx) = ContentClassifier.findBodyMatterRange(chapterInfos);
  
  // Filter to body matter
  var bodyChapters = chapters.sublist(startIdx, endIdx);
  
  // Clean and normalize each chapter
  bodyChapters = bodyChapters.map((chapter) {
    var content = chapter.content;
    
    // Remove boilerplate
    content = BoilerplateRemover.cleanChapter(content);
    
    // Normalize text
    content = TextNormalizer.normalize(content);
    
    return Chapter(
      id: chapter.id,
      number: chapter.number,
      title: chapter.title,
      content: content,
    );
  }).toList();
  
  // Renumber chapters from 1
  final renumbered = bodyChapters.asMap().entries.map((e) => 
    Chapter(
      id: e.value.id,
      number: e.key + 1,
      title: e.value.title,
      content: e.value.content,
    )
  ).toList();
  
  return ParsedEpub(
    title: title,
    author: author,
    coverPath: coverPath,
    chapters: renumbered,
  );
}
```

### 4.3 PDF Parser (if exists)

Apply same pattern to PDF parser if present.

### 4.4 Deliverables

- [ ] Modified `lib/infra/epub_parser.dart`
- [ ] Modified `lib/infra/pdf_parser.dart` (if exists)
- [ ] Integration test with sample book

**Estimated Time**: 2-3 hours

---

## Phase 5: Sentence Segmentation

**Goal**: Improve sentence boundary detection for TTS synthesis.

**File**: `lib/utils/sentence_segmenter.dart`

### 5.1 Challenges

- Abbreviations: "Dr. Smith" - don't split after "Dr."
- Decimals: "3.14" - don't split at decimal
- Ellipsis: "Wait..." - may or may not be sentence end
- Initials: "J.K. Rowling" - don't split
- Quotes: `"Hello." she said.` - complex boundaries

### 5.2 Design

```dart
/// Segments text into sentences for TTS processing
class SentenceSegmenter {
  // Common abbreviations that don't end sentences
  static const _abbreviations = {
    'dr', 'mr', 'mrs', 'ms', 'prof', 'sr', 'jr',
    'vs', 'etc', 'inc', 'ltd', 'co',
    'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
    'st', 'ave', 'blvd', 'rd',
    'i.e', 'e.g', 'cf', 'viz',
  };
  
  // Sentence-ending punctuation
  static final _sentenceEnd = RegExp(r'[.!?]');
  
  // Pattern for potential sentence break
  static final _breakCandidate = RegExp(
    r'([.!?])(\s+)([A-Z\"\'])',
    multiLine: true,
  );
  
  /// Segment text into sentences
  static List<String> segment(String text) {
    if (text.trim().isEmpty) return [];
    
    final sentences = <String>[];
    var remaining = text;
    
    while (remaining.isNotEmpty) {
      final match = _breakCandidate.firstMatch(remaining);
      if (match == null) {
        // No more breaks found
        sentences.add(remaining.trim());
        break;
      }
      
      // Check if this is a real sentence break
      final beforePunc = remaining.substring(0, match.start);
      if (_isAbbreviation(beforePunc) || _isDecimal(beforePunc)) {
        // Not a real break - skip this match
        final nextStart = match.end - 1;
        if (nextStart >= remaining.length) {
          sentences.add(remaining.trim());
          break;
        }
        remaining = remaining.substring(nextStart);
        continue;
      }
      
      // Real sentence break
      final sentence = remaining.substring(0, match.start + 1).trim();
      if (sentence.isNotEmpty) {
        sentences.add(sentence);
      }
      remaining = remaining.substring(match.start + match.group(2)!.length + 1);
    }
    
    return sentences.where((s) => s.isNotEmpty).toList();
  }
  
  static bool _isAbbreviation(String textBefore) {
    final words = textBefore.split(RegExp(r'\s+'));
    if (words.isEmpty) return false;
    final lastWord = words.last.toLowerCase().replaceAll('.', '');
    return _abbreviations.contains(lastWord);
  }
  
  static bool _isDecimal(String textBefore) {
    return RegExp(r'\d$').hasMatch(textBefore);
  }
}
```

### 5.3 Test File

**File**: `test/utils/sentence_segmenter_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/utils/sentence_segmenter.dart';

void main() {
  group('SentenceSegmenter', () {
    test('splits simple sentences', () {
      const input = 'Hello world. This is a test. Goodbye.';
      final result = SentenceSegmenter.segment(input);
      expect(result, equals(['Hello world.', 'This is a test.', 'Goodbye.']));
    });
    
    test('handles abbreviations', () {
      const input = 'Dr. Smith went home. He was tired.';
      final result = SentenceSegmenter.segment(input);
      expect(result, equals(['Dr. Smith went home.', 'He was tired.']));
    });
    
    test('handles decimals', () {
      const input = 'Pi is 3.14. It is irrational.';
      final result = SentenceSegmenter.segment(input);
      expect(result, equals(['Pi is 3.14.', 'It is irrational.']));
    });
    
    test('handles exclamation marks', () {
      const input = 'Stop! Do not move.';
      final result = SentenceSegmenter.segment(input);
      expect(result, equals(['Stop!', 'Do not move.']));
    });
    
    test('handles question marks', () {
      const input = 'How are you? I am fine.';
      final result = SentenceSegmenter.segment(input);
      expect(result, equals(['How are you?', 'I am fine.']));
    });
  });
}
```

### 5.4 Deliverables

- [ ] `lib/utils/sentence_segmenter.dart`
- [ ] `test/utils/sentence_segmenter_test.dart`
- [ ] All tests passing

**Estimated Time**: 2-3 hours

---

## Phase 6: Testing & Validation

**Goal**: Validate the complete pipeline with real books.

### 6.1 Test Books

From `local_dev/dev_books/`:

| Book | Expected Challenges |
|------|---------------------|
| Gideon The Ninth | Smart quotes, em-dashes, modern formatting |
| 1984 | Spanish EPUB structure, Parts/Chapters |
| Kindred | Prologue, front matter |
| Project Gutenberg books | Boilerplate headers/footers |

### 6.2 Validation Checklist

For each test book:

- [ ] Front matter skipped (copyright, title, dedication)
- [ ] Story starts at correct chapter/prologue
- [ ] Back matter skipped (about author, notes)
- [ ] No Project Gutenberg boilerplate
- [ ] Smart quotes normalized
- [ ] Em-dashes normalized with spaces
- [ ] No ligatures in output
- [ ] Sentences segment correctly

### 6.3 Integration Test

**File**: `test/integration/parser_integration_test.dart`

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/infra/epub_parser.dart';

void main() {
  group('EPUB Parser Integration', () {
    test('parses sample book with correct filtering', () async {
      final parser = EpubParser();
      final file = File('local_dev/dev_books/sample.epub');
      
      final result = await parser.parseFromFile(path: file.path);
      
      // Verify no front matter in chapter list
      expect(result.chapters.first.title, isNot(contains('Copyright')));
      expect(result.chapters.first.title, isNot(contains('Cover')));
      
      // Verify no smart quotes
      for (final chapter in result.chapters) {
        expect(chapter.content, isNot(contains('"')));
        expect(chapter.content, isNot(contains('"')));
        expect(chapter.content, isNot(contains(''')));
      }
      
      // Verify no Gutenberg boilerplate
      for (final chapter in result.chapters) {
        expect(chapter.content, isNot(contains('Project Gutenberg')));
      }
    });
  });
}
```

### 6.4 Deliverables

- [ ] Integration tests with sample books
- [ ] Manual validation of TTS output quality
- [ ] Documentation of any edge cases found

**Estimated Time**: 3-4 hours

---

## Character Mapping Reference

### Quotes

| Character | Unicode | Name | Output |
|-----------|---------|------|--------|
| ' | U+2018 | Left single quote | ' |
| ' | U+2019 | Right single quote | ' |
| ‚ | U+201A | Single low-9 quote | ' |
| ‛ | U+201B | Single reversed-9 quote | ' |
| " | U+201C | Left double quote | " |
| " | U+201D | Right double quote | " |
| „ | U+201E | Double low-9 quote | " |
| ‟ | U+201F | Double reversed-9 quote | " |
| « | U+00AB | Left guillemet | " |
| » | U+00BB | Right guillemet | " |
| ` | U+0060 | Backtick | ' |
| ´ | U+00B4 | Acute accent | ' |

### Dashes

| Character | Unicode | Name | Output |
|-----------|---------|------|--------|
| — | U+2014 | Em-dash | ` - ` (with spaces) |
| – | U+2013 | En-dash | - |
| ‐ | U+2010 | Hyphen | - |
| ‑ | U+2011 | Non-breaking hyphen | - |
| − | U+2212 | Minus sign | - |

### Ligatures

| Character | Unicode | Name | Output |
|-----------|---------|------|--------|
| ﬁ | U+FB01 | fi ligature | fi |
| ﬂ | U+FB02 | fl ligature | fl |
| ﬀ | U+FB00 | ff ligature | ff |
| ﬃ | U+FB03 | ffi ligature | ffi |
| ﬄ | U+FB04 | ffl ligature | ffl |
| Œ | U+0152 | OE ligature | OE |
| œ | U+0153 | oe ligature | oe |
| Æ | U+00C6 | AE ligature | AE |
| æ | U+00E6 | ae ligature | ae |

### Spaces

| Character | Unicode | Name | Output |
|-----------|---------|------|--------|
| (nbsp) | U+00A0 | Non-breaking space | (space) |
| | U+202F | Narrow no-break space | (space) |
| | U+2009 | Thin space | (space) |
| | U+200A | Hair space | (space) |
| | U+2002 | En space | (space) |
| | U+2003 | Em space | (space) |
| | U+2007 | Figure space | (space) |
| | U+200B | Zero-width space | (remove) |
| | U+200C | Zero-width non-joiner | (remove) |
| | U+200D | Zero-width joiner | (remove) |
| | U+FEFF | BOM/ZWNBSP | (remove) |

### Symbols

| Character | Unicode | Name | Output |
|-----------|---------|------|--------|
| … | U+2026 | Ellipsis | ... |
| ½ | U+00BD | One half | 1/2 |
| ¼ | U+00BC | One quarter | 1/4 |
| ¾ | U+00BE | Three quarters | 3/4 |
| © | U+00A9 | Copyright | (c) |
| ® | U+00AE | Registered | (R) |
| ™ | U+2122 | Trademark | (TM) |
| № | U+2116 | Numero | No. |
| • | U+2022 | Bullet | * |
| · | U+00B7 | Middle dot | . |

---

## Pattern Reference

### Front Matter Title Patterns

```regex
^cover$
^title\s*page$
^copyright
^table\s*of\s*contents$
^contents$
^dedication$
^acknowledgments?$
^about\s*the\s*author$
^also\s*by
^epigraph$
^foreword$
^preface$
^half[\s-]?title
```

### Back Matter Title Patterns

```regex
^about\s*the\s*author
^acknowledgments?$
^bibliography$
^notes$
^end\s*notes?$
^index$
^appendix
^glossary$
^also\s*by
^further\s*reading
```

### Boilerplate Content Patterns

```regex
\*{3}\s*START OF (THIS|THE) PROJECT GUTENBERG EBOOK.*?\*{3}
\*{3}\s*END OF (THIS|THE) PROJECT GUTENBERG EBOOK.*?\*{3}
produced by
www\.gutenberg\.org
scanned by
proofread by
public domain
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                       EPUB/PDF Parser                           │
│                    lib/infra/epub_parser.dart                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Extract chapters from file (existing epubx code)           │
│                          ↓                                      │
│  2. BoilerplateRemover.removeFromBook() (if single-file)       │
│                          ↓                                      │
│  3. ContentClassifier.findBodyMatterRange()                    │
│                          ↓                                      │
│  4. Filter chapters to body matter range                        │
│                          ↓                                      │
│  5. For each chapter:                                          │
│     ├── BoilerplateRemover.cleanChapter()                      │
│     └── TextNormalizer.normalize()                             │
│                          ↓                                      │
│  6. Renumber chapters (1, 2, 3...)                             │
│                          ↓                                      │
│  7. Return ParsedEpub                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      Utility Classes                            │
├──────────────────────┬──────────────────────┬───────────────────┤
│   TextNormalizer     │  BoilerplateRemover  │ ContentClassifier │
│   lib/utils/         │  lib/utils/          │ lib/utils/        │
├──────────────────────┼──────────────────────┼───────────────────┤
│ • normalizeQuotes()  │ • removeFromBook()   │ • classify()      │
│ • normalizeDashes()  │ • cleanChapter()     │ • findBodyRange() │
│ • normalizeLigatures │ • detectRepeated()   │                   │
│ • normalizeSpaces()  │ • isBoilerplate()    │                   │
│ • normalizeSymbols() │                      │                   │
└──────────────────────┴──────────────────────┴───────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    SentenceSegmenter                            │
│                  lib/utils/ (Phase 5)                           │
├─────────────────────────────────────────────────────────────────┤
│ Used by TTS engine for chunking, not during parsing            │
│ • segment(text) → List<String>                                 │
│ • Handles abbreviations, decimals, quotes                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Timeline & Priorities

| Phase | Description | Priority | Effort | Dependencies |
|-------|-------------|----------|--------|--------------|
| 1 | Text Normalizer | HIGH | 2-3 hrs | None |
| 2 | Boilerplate Remover | HIGH | 2-3 hrs | None |
| 3 | Content Classifier | HIGH | 3-4 hrs | None |
| 4 | Parser Integration | HIGH | 2-3 hrs | Phases 1-3 |
| 5 | Sentence Segmenter | MEDIUM | 2-3 hrs | Phase 1 |
| 6 | Testing & Validation | HIGH | 3-4 hrs | All above |

**Total Estimate**: 15-20 hours

### Recommended Order

1. **Phase 1** (Text Normalizer) - Foundation for all text processing
2. **Phase 2** (Boilerplate Remover) - Clean data for classification
3. **Phase 3** (Content Classifier) - Smart filtering
4. **Phase 4** (Parser Integration) - Wire it all together
5. **Phase 6** (Testing) - Validate with real books
6. **Phase 5** (Sentence Segmenter) - Refinement (can be done later)

---

## Success Criteria

- [ ] All unit tests passing
- [ ] Sample books parse without errors
- [ ] No smart quotes in TTS output
- [ ] No em-dashes without spaces in TTS output
- [ ] No ligatures in TTS output
- [ ] No Project Gutenberg boilerplate in TTS output
- [ ] Audiobook starts at story content, not copyright/title
- [ ] Audiobook ends at story conclusion, not "About the Author"
- [ ] TTS synthesis sounds natural (manual verification)

---

## Files Summary

### New Files

| File | Description |
|------|-------------|
| `lib/utils/text_normalizer.dart` | Typography normalization |
| `lib/utils/boilerplate_remover.dart` | Boilerplate detection/removal |
| `lib/utils/content_classifier.dart` | Front/body/back matter classification |
| `lib/utils/sentence_segmenter.dart` | Sentence boundary detection |
| `test/utils/text_normalizer_test.dart` | Unit tests |
| `test/utils/boilerplate_remover_test.dart` | Unit tests |
| `test/utils/content_classifier_test.dart` | Unit tests |
| `test/utils/sentence_segmenter_test.dart` | Unit tests |
| `test/integration/parser_integration_test.dart` | Integration tests |

### Modified Files

| File | Changes |
|------|---------|
| `lib/infra/epub_parser.dart` | Integrate all utilities |
| `lib/infra/pdf_parser.dart` | Integrate utilities (if exists) |

---

## Notes

### Edge Cases to Watch

1. **Prologues** - Usually body matter, but classification may mis-label
2. **Introductions** - Could be front matter (editor) or body matter (author)
3. **Books without chapters** - May have no clear "Chapter 1" marker
4. **Multi-volume books** - "Part I", "Book One" structure
5. **Non-English books** - Different front/back matter terms

### Future Enhancements

1. **User settings** - Toggle for "include front matter"
2. **Chapter preview** - Show classification before import
3. **Learning system** - Remember user corrections
4. **PDF layout analysis** - Header/footer removal for PDFs
