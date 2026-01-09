# Smart EPUB/PDF Parser Implementation Plan

## Overview

This feature improves text extraction quality from EPUB and PDF files for TTS (Text-to-Speech) processing. The goal is to handle various text encoding issues, typographic characters, and formatting problems that can cause poor TTS output.

## Problem Statement

When extracting text from EPUB and PDF files for TTS synthesis, several issues can occur:

1. **Smart/Curly Quotes**: Typography uses `"` `"` `'` `'` instead of straight quotes `"` `'`
2. **Special Dashes**: Em-dashes (—), en-dashes (–) instead of hyphens (-)
3. **Ellipsis**: Unicode ellipsis (…) vs three periods (...)
4. **Ligatures**: Combined characters like ﬁ (fi), ﬂ (fl), ﬀ (ff)
5. **Non-breaking Spaces**: \u00A0 instead of regular spaces
6. **Encoding Issues**: Garbled text from font-specific or non-Unicode encodings
7. **Special Punctuation**: Bullet points, fractions, mathematical symbols
8. **HTML Entities**: Unescaped or partially decoded entities

## Research Findings

### Common Special Characters Found in Sample Books

From analysis of books in `local_dev/dev_books/`:
- Smart single quotes: `'` (U+2019) - commonly used as apostrophe
- Em-dashes: `—` (U+2014)
- Ellipsis: `…` (U+2026)
- Smart double quotes: `"` (U+201C) `"` (U+201D)

### Unicode Normalization

- **NFC**: Canonical Composition (default, good for display)
- **NFKC**: Compatibility Composition (aggressive, normalizes ligatures and stylistic forms)
- For TTS: **NFKC** is recommended as it simplifies text to canonical forms

### Current Parser State

Located in: `lib/infra/epub_parser.dart`
- Uses `epubx` package for EPUB parsing
- Has `_stripHtmlToText()` method for HTML tag removal
- Has `_decodeHtmlEntities()` for basic entity handling
- **Missing**: Unicode normalization, smart character handling

## Implementation Plan

### Phase 1: Text Normalizer Utility

Create a dedicated text normalization utility class that can be used across EPUB and PDF parsers.

**File**: `lib/utils/text_normalizer.dart`

```dart
class TextNormalizer {
  /// Main normalization entry point
  static String normalize(String text) {
    var result = text;
    result = normalizeQuotes(result);
    result = normalizeDashes(result);
    result = normalizeEllipsis(result);
    result = normalizeLigatures(result);
    result = normalizeSpaces(result);
    result = normalizeUnicode(result);
    result = cleanWhitespace(result);
    return result;
  }
  
  // Individual normalization methods...
}
```

### Phase 2: Character Normalization Rules

#### 2.1 Quote Normalization
| Input | Unicode | Output |
|-------|---------|--------|
| ' (left single) | U+2018 | ' |
| ' (right single) | U+2019 | ' |
| ‚ (low-9 single) | U+201A | ' |
| ‛ (reversed-9 single) | U+201B | ' |
| " (left double) | U+201C | " |
| " (right double) | U+201D | " |
| „ (low-9 double) | U+201E | " |
| ‟ (reversed-9 double) | U+201F | " |
| « (left guillemet) | U+00AB | " |
| » (right guillemet) | U+00BB | " |
| ` (backtick) | U+0060 | ' |
| ´ (acute accent) | U+00B4 | ' |

#### 2.2 Dash Normalization
| Input | Unicode | Output |
|-------|---------|--------|
| — (em-dash) | U+2014 | - |
| – (en-dash) | U+2013 | - |
| ‐ (hyphen) | U+2010 | - |
| ‑ (non-breaking hyphen) | U+2011 | - |
| ⁃ (hyphen bullet) | U+2043 | - |
| − (minus sign) | U+2212 | - |

**Note**: Consider keeping em-dashes as ` - ` (space-dash-space) for better TTS pacing.

#### 2.3 Ellipsis Normalization
| Input | Unicode | Output |
|-------|---------|--------|
| … | U+2026 | ... |

#### 2.4 Ligature Decomposition
| Input | Unicode | Output |
|-------|---------|--------|
| ﬁ | U+FB01 | fi |
| ﬂ | U+FB02 | fl |
| ﬀ | U+FB00 | ff |
| ﬃ | U+FB03 | ffi |
| ﬄ | U+FB04 | ffl |
| ﬅ | U+FB05 | st |
| ﬆ | U+FB06 | st |
| Œ | U+0152 | OE |
| œ | U+0153 | oe |
| Æ | U+00C6 | AE |
| æ | U+00E6 | ae |

#### 2.5 Space Normalization
| Input | Unicode | Output |
|-------|---------|--------|
| (non-breaking space) | U+00A0 | (space) |
| (narrow no-break space) | U+202F | (space) |
| (thin space) | U+2009 | (space) |
| (hair space) | U+200A | (space) |
| (en space) | U+2002 | (space) |
| (em space) | U+2003 | (space) |
| (figure space) | U+2007 | (space) |
| (zero-width space) | U+200B | (remove) |
| (zero-width joiner) | U+200D | (remove) |
| (zero-width non-joiner) | U+200C | (remove) |

#### 2.6 Other Symbols
| Input | Description | Output |
|-------|-------------|--------|
| • | bullet | * |
| · | middle dot | . |
| ‣ | triangular bullet | * |
| ⁃ | hyphen bullet | - |
| ½ | fraction half | 1/2 |
| ¼ | fraction quarter | 1/4 |
| ¾ | fraction three-quarters | 3/4 |
| © | copyright | (c) |
| ® | registered | (R) |
| ™ | trademark | (TM) |
| № | numero | No. |

### Phase 3: Integration with EPUB Parser

Modify `lib/infra/epub_parser.dart`:

```dart
import '../utils/text_normalizer.dart';

String _stripHtmlToText(String html) {
  // ... existing HTML stripping code ...
  
  // Add normalization at the end
  text = TextNormalizer.normalize(text);
  
  return text;
}
```

### Phase 4: PDF Parser Enhancement

If a PDF parser exists, apply the same normalization:

```dart
// In pdf_parser.dart
String extractText(/* ... */) {
  // ... PDF extraction logic ...
  return TextNormalizer.normalize(extractedText);
}
```

### Phase 5: Sentence Segmentation Improvement

Enhance sentence detection to handle:
- Abbreviations (Dr., Mr., Mrs., etc.)
- Decimal numbers (3.14)
- Ellipsis (both `...` and `…`)
- URLs and emails
- Quoted speech spanning sentences

**File**: `lib/utils/sentence_segmenter.dart`

```dart
class SentenceSegmenter {
  static const _abbreviations = ['Dr', 'Mr', 'Mrs', 'Ms', 'Prof', 'Jr', 'Sr', 'etc', 'vs', 'i.e', 'e.g'];
  
  static List<String> segment(String text) {
    // Smart sentence boundary detection
  }
}
```

### Phase 6: Testing

Create test cases for each normalization rule:

**File**: `test/utils/text_normalizer_test.dart`

```dart
void main() {
  group('TextNormalizer', () {
    test('normalizes smart quotes', () {
      expect(TextNormalizer.normalize('"Hello"'), equals('"Hello"'));
      expect(TextNormalizer.normalize("it's"), equals("it's"));
    });
    
    test('normalizes em-dashes', () {
      expect(TextNormalizer.normalize('word—word'), equals('word - word'));
    });
    
    // ... more tests
  });
}
```

### Phase 7: Real-World Testing

Test with sample books from `local_dev/dev_books/`:
1. Parse each EPUB
2. Extract chapters
3. Verify no weird characters in output
4. Test TTS synthesis quality

## File Changes Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `lib/utils/text_normalizer.dart` | New | Core normalization utility |
| `lib/utils/sentence_segmenter.dart` | New | Improved sentence detection |
| `lib/infra/epub_parser.dart` | Modify | Integrate TextNormalizer |
| `lib/infra/pdf_parser.dart` | Modify | Integrate TextNormalizer (if exists) |
| `test/utils/text_normalizer_test.dart` | New | Unit tests |
| `test/utils/sentence_segmenter_test.dart` | New | Unit tests |

## Technical Notes

### Dart Unicode Support
- Use `String.replaceAll()` for simple replacements
- Use `RegExp` with unicode flag for pattern matching
- Consider `package:characters` for grapheme cluster handling

### Performance Considerations
- Run normalization once after HTML stripping
- Compile RegExp patterns once (static)
- Consider chunking for very long texts

### Edge Cases to Handle
1. Mixed encoding in same file
2. Nested quotes: `"He said 'hello'"`
3. Possessive apostrophes: `James's`
4. Contractions: `don't`, `won't`, `'70s`
5. Dialogue tags: `—he said—`
6. Poetry/verse with intentional line breaks

## Timeline Estimate

| Phase | Effort | Priority |
|-------|--------|----------|
| Phase 1: Text Normalizer | 2-3 hours | High |
| Phase 2: Character Rules | 1-2 hours | High |
| Phase 3: EPUB Integration | 30 min | High |
| Phase 4: PDF Integration | 30 min | Medium |
| Phase 5: Sentence Segmentation | 2-3 hours | Medium |
| Phase 6: Unit Tests | 1-2 hours | High |
| Phase 7: Real-World Testing | 2-3 hours | High |
| Phase 8: Front Matter Detection | 3-4 hours | High |

**Total Estimate**: 14-20 hours

## Success Criteria

1. All smart quotes converted to straight quotes
2. All dashes normalized appropriately
3. No ligatures in output text
4. No invisible Unicode characters
5. Clean sentence boundaries for TTS
6. Passes all unit tests
7. Works with all sample books without errors
8. **Audiobook starts at actual story content, not front matter**

---

## Phase 8: Smart Front Matter Detection & Filtering

### Problem

EPUB files contain sections that are not suitable for audiobook listening:
- Title page
- Copyright page
- Dedication
- Acknowledgments
- Table of Contents
- Preface/Foreword (sometimes)
- About the Author (at start or end)
- Also by this Author
- Epigraph (decorative quotes)

Users want to hear the story from "Chapter 1" or the actual narrative beginning.

### Detection Strategy

#### 8.1 Filename-Based Detection

EPUB chapter files often have predictable naming patterns:

**Skip patterns** (front matter):
```
/cover\./i
/title/i
/copyright/i
/toc\./i
/contents/i
/dedication/i
/acknowledgment/i
/foreword/i
/preface/i
/about.?the.?author/i
/also.?by/i
/frontmatter/i
/front_matter/i
/epigraph/i
/halftitle/i
```

**Keep patterns** (story content):
```
/chapter/i
/part\d/i
/prologue/i
/epilogue/i
/book\d/i
```

#### 8.2 Content-Based Detection

Analyze the first 200-500 characters of each chapter for indicators:

**Front matter indicators**:
- "Copyright ©"
- "All rights reserved"
- "Published by"
- "ISBN"
- "Library of Congress"
- "Printed in"
- "First edition"
- "Also by [Author]"
- "Table of Contents"
- "Dedication"
- "For my"
- "Acknowledgments"
- "About the Author"

**Story content indicators**:
- Dialogue (quoted speech)
- Narrative paragraphs (multiple sentences)
- Character names
- Scene descriptions

#### 8.3 Title-Based Detection

Chapter titles extracted from EPUB often indicate content type:

**Skip titles matching**:
```dart
final _frontMatterTitles = [
  RegExp(r'^copyright', caseSensitive: false),
  RegExp(r'^title\s*page', caseSensitive: false),
  RegExp(r'^table\s*of\s*contents', caseSensitive: false),
  RegExp(r'^contents$', caseSensitive: false),
  RegExp(r'^dedication', caseSensitive: false),
  RegExp(r'^acknowledgment', caseSensitive: false),
  RegExp(r'^about\s*the\s*author', caseSensitive: false),
  RegExp(r'^also\s*by', caseSensitive: false),
  RegExp(r'^foreword', caseSensitive: false),
  RegExp(r'^preface', caseSensitive: false),
  RegExp(r'^epigraph', caseSensitive: false),
  RegExp(r'^cover$', caseSensitive: false),
];
```

**Back matter (end of book)**:
```dart
final _backMatterTitles = [
  RegExp(r'^about\s*the\s*author', caseSensitive: false),
  RegExp(r'^acknowledgment', caseSensitive: false),
  RegExp(r'^bibliography', caseSensitive: false),
  RegExp(r'^notes$', caseSensitive: false),
  RegExp(r'^index$', caseSensitive: false),
  RegExp(r'^appendix', caseSensitive: false),
  RegExp(r'^also\s*by', caseSensitive: false),
  RegExp(r'^author', caseSensitive: false),
];
```

#### 8.4 EPUB Landmark Detection

EPUB3 files include navigation landmarks that explicitly mark content types:

```xml
<nav epub:type="landmarks">
  <ol>
    <li><a epub:type="cover" href="cover.xhtml">Cover</a></li>
    <li><a epub:type="toc" href="toc.xhtml">Table of Contents</a></li>
    <li><a epub:type="bodymatter" href="chapter1.xhtml">Start Reading</a></li>
  </ol>
</nav>
```

Parse the `nav` file to find `epub:type="bodymatter"` or `epub:type="chapter"`.

#### 8.5 Spine Order with Heuristics

EPUB spine defines reading order. Apply heuristics:
1. Skip first N items if they match front matter patterns
2. Find first item matching "chapter" or story pattern
3. Stop at items matching back matter patterns

### Implementation

**File**: `lib/utils/content_classifier.dart`

```dart
enum ContentType {
  frontMatter,
  bodyMatter,
  backMatter,
}

class ContentClassifier {
  /// Classify a chapter based on filename, title, and content
  static ContentType classify({
    required String filename,
    required String title,
    required String contentSnippet,
  }) {
    // Check filename patterns
    if (_matchesFrontMatter(filename)) return ContentType.frontMatter;
    
    // Check title patterns
    if (_isFrontMatterTitle(title)) return ContentType.frontMatter;
    if (_isBackMatterTitle(title)) return ContentType.backMatter;
    
    // Check content for copyright, ISBN, etc.
    if (_hasFrontMatterContent(contentSnippet)) return ContentType.frontMatter;
    
    return ContentType.bodyMatter;
  }
  
  /// Filter chapters to only include body matter
  static List<Chapter> filterToBodyMatter(List<Chapter> chapters) {
    var startIndex = 0;
    var endIndex = chapters.length;
    
    // Find first body matter chapter
    for (var i = 0; i < chapters.length; i++) {
      final type = classify(
        filename: chapters[i].id,
        title: chapters[i].title,
        contentSnippet: chapters[i].content.substring(0, min(500, chapters[i].content.length)),
      );
      if (type == ContentType.bodyMatter) {
        startIndex = i;
        break;
      }
    }
    
    // Find where back matter starts
    for (var i = chapters.length - 1; i >= startIndex; i--) {
      final type = classify(
        filename: chapters[i].id,
        title: chapters[i].title,
        contentSnippet: chapters[i].content.substring(0, min(500, chapters[i].content.length)),
      );
      if (type != ContentType.backMatter) {
        endIndex = i + 1;
        break;
      }
    }
    
    return chapters.sublist(startIndex, endIndex);
  }
}
```

### Integration with EPUB Parser

Modify `lib/infra/epub_parser.dart`:

```dart
import '../utils/content_classifier.dart';

Future<ParsedEpub> parseFromFile({...}) async {
  // ... existing parsing code ...
  
  // Filter out front/back matter
  final bodyChapters = ContentClassifier.filterToBodyMatter(chapters);
  
  // Renumber chapters
  final renumbered = bodyChapters.asMap().entries.map((e) => 
    Chapter(
      id: e.value.id,
      number: e.key + 1,  // Start from 1
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

### User Override Option

Some users may want to include front matter (e.g., forewords, prologues). Consider:

1. **Settings toggle**: "Skip front matter" (default: on)
2. **Manual chapter selection**: Allow users to select which chapters to include
3. **Preview before import**: Show detected chapters with classification labels

### Testing Strategy

Test with books that have various front matter structures:
1. Simple: Just copyright + title + chapters
2. Complex: Dedication, acknowledgments, foreword, prologue, etc.
3. Literary: Epigraphs, multiple title pages
4. Non-fiction: Table of contents, introduction, appendices

### Examples from Sample Books

From `local_dev/dev_books/`:

**Kindred (Octavia Butler)**:
- `Butl_*_cop_r1.htm` - Copyright (skip)
- `Butl_*_ded_r1.htm` - Dedication (skip)
- `Butl_*_prl_r1.htm` - Prologue (KEEP - story content)
- `Butl_*_c01_r1.htm` - Chapter 1 (KEEP)

**1984 (George Orwell)**:
- `cubierta.xhtml` - Cover (skip)
- `sinopsis.xhtml` - Synopsis (skip)
- `titulo.xhtml` - Title (skip)
- `PartePrimera.xhtml` - Part 1 heading (KEEP)
- `1-1.xhtml` - Chapter 1.1 (KEEP)

### Edge Cases

1. **Books without chapters**: Some books have no "Chapter X" labels
2. **Prologues**: Sometimes front matter, sometimes story content
3. **Introduction by editor**: Not the author, but may be valuable
4. **Epistolary novels**: May start with letters, not chapters
5. **Serialized novels**: May have "Part I" structure

### Fallback Behavior

If detection fails or is uncertain:
1. Include all chapters
2. Log warning for debugging
3. Consider prompting user to confirm
