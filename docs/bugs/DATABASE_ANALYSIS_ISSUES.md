# Database Analysis: Parsing and Metadata Issues

**Date:** January 2026  
**Database:** eist_audiobook.db (version 7)  
**Books Analyzed:** 15  
**Total Segments:** 81,287

---

## Executive Summary

Analysis of the audiobook database reveals several critical issues across three main categories:

1. **HTML Tag Contamination** - EPUB HTML attributes leaking into segment text
2. **Metadata Quality Problems** - Missing/incorrect title and author information
3. **Chapter Header Redundancy** - Book/chapter titles prepended to every chapter's first segment

---

## Issue 1: HTML Tag Attribute Contamination (CRITICAL)

### Description
Project Gutenberg EPUBs have HTML element IDs leaking into the segment text. The pattern `id="pgepubid#####">` appears at the start of many segments.

### Affected Books
| Book | Contaminated Segments | Total Segments | % Contaminated |
|------|----------------------|----------------|----------------|
| Moby Dick | 135+ | 8,075 | 1.7% |
| Pride and Prejudice | 56+ | 5,111 | 1.1% |
| A Christmas Carol | 12 | 1,010 | 1.2% |
| Frankenstein | 0 | 2,977 | 0% |

### Examples
```
# Moby Dick chapter starts:
id="pgepubid00006"> CHAPTER 1. Loomings. Call me Ishmael.

# Pride and Prejudice chapter starts:
id="pgepubid00002"> PRIDE. and PREJUDICE by Jane Austen...
id="pgepubid00033"> He rode a black horse. CHAPTER III. OT all that Mrs.
```

### Root Cause
The HTML parser is not properly stripping element attributes before extracting text content. This only affects certain EPUB formats (Project Gutenberg with `pgepubid` attributes).

**Specifically in `_extractAnchorContent()` (line 380 of epub_parser.dart):**
```dart
// BUG: startPos points to the START of id="anchor", not the content after the tag
final startPos = anchorPositions[currentAnchor]!;  // Points to: id="pgepubid00006"
final segment = html.substring(startPos, endPos);  // Starts with: id="pgepubid00006">...
```

The regex `RegExp('id=["\']${anchor}["\']')` finds `id="pgepubid00006"` but the code extracts from `match.start`, which includes the attribute itself. The `_stripHtmlToText()` function only removes full `<tag>` patterns, not partial attribute text like `id="pgepubid00006">`.

### Impact
- TTS will read "id equals pgepubid00006" at chapter beginnings
- Ruins audiobook listening experience
- 203+ segments across 3 books confirmed affected

### Recommended Fix
In EPUB parser (`epub_parser.dart`), fix `_extractAnchorContent()` to find the START of the containing tag, not just the anchor attribute:

```dart
// Option A: Find the opening < of the tag containing the anchor
for (final pattern in patterns) {
  final match = pattern.firstMatch(html);
  if (match != null) {
    // Walk backwards to find the < that starts this tag
    var tagStart = match.start;
    while (tagStart > 0 && html[tagStart] != '<') {
      tagStart--;
    }
    // Walk forwards to find the > that ends this tag
    var tagEnd = match.end;
    while (tagEnd < html.length && html[tagEnd] != '>') {
      tagEnd++;
    }
    anchorPositions[anchor] = tagEnd + 1;  // Start AFTER the closing >
    break;
  }
}

// Option B (simpler): Strip attribute remnants in _stripHtmlToText
text = text.replaceAll(RegExp(r'id="[^"]*">\s*'), '');
text = text.replaceAll(RegExp(r'name="[^"]*">\s*'), '');
```

---

## Issue 2: Code/Template Contamination in Technical Books (MODERATE)

### Description
Technical PDFs (programming books) have code blocks and template syntax leaking into segments that will be read by TTS.

### Affected Books
| Book | Contaminated Segments | Examples |
|------|----------------------|----------|
| Django for Professionals | 89 | Django template tags like `{% url 'login' %}`, HTML tags |
| AI Engineering | 15 | XML-like prompts `<chunk>`, `{{CHUNK_CONTENT}}` |

### Examples
```
# Django PDF segment:
<p>Hi {{ user.email }}!</p> <p><a href="{% url 'logout' %}">Log Out</a></p>

# AI Engineering PDF segment:
<chunk> {{CHUNK_CONTENT}} </chunk> Please give a short succinct context...
```

### Impact
- TTS reads code syntax aloud ("less than p greater than Hi curly brace curly brace...")
- Particularly bad for technical books with lots of code examples

### Recommended Fix
- Consider filtering out obvious code blocks
- Or provide user option to "skip code sections" 
- Mark segments with high code density for different handling

---

## Issue 3: Missing Metadata / Unknown Author (MODERATE)

### Description
Books imported from files without embedded metadata default to "Unknown Author" and ugly titles like `1984 _George Orwell_ _Z-Library_`.

### Affected Books (5 total)
| Title | Author | Should Be |
|-------|--------|-----------|
| 1984 _George Orwell_ _Z-Library_ | Unknown author | 1984 / George Orwell |
| AI Engineering Building Applications... _Chip Huyen_ _Z-Library_ | Unknown Author | AI Engineering / Chip Huyen |
| Django for Professionals... _William S. Vincent_ _Z-Library_ | Unknown Author | Django for Professionals / William S. Vincent |
| account-statement_2024-01-01... | Unknown Author | (correct - not a book) |
| Balance Confirmation | Unknown Author | (correct - not a book) |

### Analysis: Google Books API Integration
The code **does** attempt Google Books API lookup for all imports (line 154 in `library_controller.dart`):
```dart
final metadata = await BookMetadataService().searchBook(title, author);
```

**Why it failed:**
1. **Confidence threshold too strict**: Books with messy titles use 0.7 threshold, but search query is polluted with `_Z-Library_` suffix
2. **Search query pollution**: Searching "1984 _George Orwell_ _Z-Library_" returns poor matches
3. **No filename parsing fallback**: Could extract author from filename patterns like `Title (Author) (Z-Library).epub`

### When API Should Have Been Called
| Book | API Called? | Should Have Worked? | Why Failed |
|------|-------------|---------------------|------------|
| 1984 (Z-Library) | ✅ Yes | No | Search query polluted with `_Z-Library_` |
| Harry Potter | ✅ Yes | ✅ Yes | Clean title, API found match |
| Say Nothing | ✅ Yes | ✅ Yes | Clean embedded metadata |
| To Green Angel Tower | ✅ Yes | ✅ Yes | Clean embedded metadata |

### Recommended Fixes
1. **Clean search query before API call**: Strip common suffixes like `_Z-Library_`, `(Z-Library)`, underscores for spaces
2. **Parse filename for author**: Pattern `Title (Author) (Z-Library).epub` is very common
3. **Lower confidence threshold for polluted inputs**: If title contains `Z-Library`, be more lenient with matches

---

## Issue 4: Redundant Chapter Headers (LOW)

### Description
Every chapter's first segment includes the book title or chapter marker prefix, leading to repetitive TTS output.

### Examples
```
# Frankenstein (every chapter):
"Frankenstein | Project Gutenberg Letter 1 To Mrs. Saville..."
"Frankenstein | Project Gutenberg Chapter 1 I am by birth..."

# Harry Potter (every chapter):  
"Unknown Chapter 1 The Boy Who Lived Mr. and Mrs..."
"Unknown Chapter 2 The Vanishing Glass..."
```

### Analysis
- Frankenstein has 28 chapters, ALL start with "Frankenstein | Project Gutenberg"
- Harry Potter has 17 chapters, ALL start with "Unknown Chapter N"
- This is intentional for context but clutters TTS output

### Impact
- User hears "Frankenstein Project Gutenberg Chapter 5" at start of every chapter
- "Unknown Chapter" prefix is confusing

### Recommended Fix
- Store chapter title separately from chapter content
- Only speak chapter title once at chapter start (configurable)
- Remove "Unknown" from chapter titles - use just "Chapter N" or the real title

---

## Issue 5: Very Short Segments (LOW)

### Description
Some books have many segments under 20 characters, which may cause choppy TTS with unnecessary pauses.

### Statistics
| Book | Very Short Segments (<20 chars) | % of Total |
|------|--------------------------------|------------|
| To Green Angel Tower | 249 | 1.1% |
| AI Engineering | 84 | 1.0% |
| The Beach | 79 | 1.3% |

### Examples from To Green Angel Tower
```
"It was midnight."
"Be content."
"Very nice."
"Who was it?"
"Let us now go."
```

### Impact
- These are legitimate dialogue/prose, not errors
- May cause choppy playback if TTS pauses between segments
- Current minimum is 10 characters (acceptable)

### Assessment
**NOT A BUG** - Short sentences are valid prose. Current segmentation handles this reasonably. Consider batching very short segments together for smoother TTS flow.

---

## Issue 6: Rich Content Type Support (FEATURE REQUEST)

### Description
Technical books and some fiction contain rich content beyond plain text:
- **Code blocks** - Programming code, terminal commands, configuration files
- **Tables** - Data tables, comparison charts
- **Images/Figures** - Diagrams, charts, photos with captions
- **Math equations** - LaTeX, formulas

Currently ALL content is extracted as plain text and rendered uniformly. The user requests segment type differentiation for visual display and optional TTS skip.

### Current State: How Content Is Extracted

**EPUB Parser** (`lib/infra/epub_parser.dart`):
- `_stripHtmlToText()` removes ALL HTML tags: `text.replaceAll(RegExp(r'<[^>]+>'), '')`
- Images (`<img>`) are completely stripped - no alt text preserved
- Tables (`<table>`) become garbled text - cells concatenated without structure
- Code blocks (`<pre>`, `<code>`) lose formatting, become plain text

**PDF Parser** (`lib/infra/pdf_parser.dart`):
- Uses `pdfrx` to extract text layer from PDF
- Images are NOT in text layer - completely invisible
- Tables become garbled text as PDFs have no semantic structure
- Code blocks are plain text (monospace font not detected)

**What Gets Lost:**
| Content Type | EPUB | PDF |
|-------------|------|-----|
| Images | ❌ Stripped (no alt text) | ❌ Not in text layer |
| Tables | ⚠️ Garbled | ⚠️ Garbled |
| Code | ⚠️ Plain text | ⚠️ Plain text |
| Math | ⚠️ Plain text or symbols | ⚠️ Plain text or symbols |

### Proposed Solution: Segment Types

Add a `segmentType` enum to classify content:

```dart
enum SegmentType {
  text,       // Normal prose
  code,       // Code block - monospace, skip option
  table,      // Table data - visual display, skip option  
  figure,     // Image/figure - show placeholder, skip audio
  heading,    // Chapter/section header
  quote,      // Block quote - italic styling
  math,       // Mathematical formula
}

class Segment {
  final String text;
  final int index;
  final SegmentType type;          // NEW
  final String? imagePath;         // NEW - for figure type
  final Map<String, dynamic>? metadata; // NEW - for table structure etc.
  // ...
}
```

### Implementation Phases

#### Phase 1: Code Block Detection (3-4 hours)
**Effort: LOW | Value: HIGH**

1. Add detection heuristic in parsers (see Issue 6 above for regex patterns)
2. Add `flags` column to segments table
3. Conditionally render monospace styling in `segment_tile.dart`

#### Phase 2: Image/Figure Support - EPUB Only (6-8 hours)
**Effort: MEDIUM | Value: MEDIUM**

1. Modify EPUB parser to detect `<img>` tags
2. Extract and save images to book directory
3. Create `FigureSegment` with `imagePath` reference
4. Create `FigureSegmentWidget` that displays image inline
5. Generate "[Figure: alt text]" for TTS or skip entirely

**EPUB-specific approach:**
```dart
// In _stripHtmlToText, instead of stripping img:
final imgMatches = RegExp(r'<img[^>]*src="([^"]*)"[^>]*alt="([^"]*)"[^>]*>').allMatches(html);
for (final match in imgMatches) {
  final src = match.group(1);
  final alt = match.group(2);
  // Save image, create figure segment
}
```

#### Phase 3: Table Detection (4-6 hours)
**Effort: MEDIUM | Value: LOW**

1. Detect `<table>` in EPUB, heuristic patterns in PDF
2. Extract table structure if possible (EPUB has semantic HTML)
3. Render as styled widget or skip entirely
4. For TTS: "Table: [caption]" or skip

**Challenges:**
- PDF tables have NO semantic structure - very hard to reconstruct
- EPUB tables vary widely in HTML quality
- Recommendation: Start with simple "This is a table" detection + skip

#### Phase 4: PDF Image Extraction (8-12 hours)
**Effort: HIGH | Value: LOW**

PDF images require different approach:
1. Use `pdfrx` to render page regions as images
2. Detect image regions via whitespace/text analysis
3. Extract and save bitmap regions
4. Associate with nearby text segments

**Why this is hard:**
- PDFs don't have "image" markers in text layer
- Need visual analysis to find image regions
- May extract decorative elements by mistake
- Recommendation: **Skip for now** - focus on EPUB first

### Recommended Roadmap

| Phase | Feature | Effort | Priority | Impact |
|-------|---------|--------|----------|--------|
| 1 | Code detection + monospace styling | 3h | HIGH | Immediate improvement for tech books |
| 2 | EPUB image extraction + display | 6h | MEDIUM | Nice visual enhancement |
| 3 | Table detection + skip option | 4h | LOW | Minor improvement |
| 4 | PDF image extraction | 12h+ | LOW | Complex, limited value |

**Start with Phase 1** - 80% of the value for 20% of the effort.

### UI Display Mockup

```
┌─────────────────────────────────────────┐
│ [Normal text flows naturally here...]   │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ def calculate_total(items):         │ │  ← CODE: Monospace, dark bg
│ │     return sum(i.price for i in...) │ │     [Skip Code] button
│ └─────────────────────────────────────┘ │
│                                         │
│ [Text continues after code block...]    │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │        [Figure 2.1]                 │ │  ← FIGURE: Image display
│ │     ┌─────────────────┐             │ │     Extracted from EPUB
│ │     │   (diagram)     │             │ │
│ │     └─────────────────┘             │ │
│ │  "Architecture overview"            │ │  ← Caption
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ TABLE: Performance Benchmarks       │ │  ← TABLE: Collapsed view
│ │ [Tap to expand] [Skip in playback]  │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ [Text continues...]                     │
└─────────────────────────────────────────┘
```

### Database Schema Changes

```sql
-- Add type and metadata to segments
ALTER TABLE segments ADD COLUMN segment_type TEXT DEFAULT 'text';
ALTER TABLE segments ADD COLUMN metadata TEXT; -- JSON for table structure, image path, etc.

-- Index for quick filtering
CREATE INDEX idx_segments_type ON segments(book_id, segment_type);
```

### Settings to Add

```dart
// In SettingsController
bool skipCodeBlocks = false;      // Auto-skip code during playback
bool skipTables = false;          // Auto-skip tables during playback
bool skipFigures = true;          // Auto-skip figures (default: skip images)
bool showCodeInline = true;       // Show code visually vs collapse
```

---

## Database Schema Observations

### Books Table
- No `import_source` column to track where book came from (Gutenberg, file, etc.)
- No `original_filename` column to preserve import filename for metadata parsing
- `gutenberg_id` only tracks Gutenberg imports (null for file imports)

### Segments Table
- No flags for "contains code" or "should skip"
- No original HTML preserved for debugging

### Recommended Schema Additions
```sql
ALTER TABLE books ADD COLUMN import_source TEXT; -- 'gutenberg', 'file', 'url'
ALTER TABLE books ADD COLUMN original_filename TEXT;
ALTER TABLE segments ADD COLUMN flags INTEGER DEFAULT 0; -- bitmask for skip, code, etc.
```

---

## Priority Ranking

| Priority | Issue | Impact | Effort |
|----------|-------|--------|--------|
| 1 | HTML Tag Contamination | HIGH | LOW |
| 2 | Missing Metadata (API query cleanup) | MEDIUM | LOW |
| 3 | Code Block Visual Display | MEDIUM | MEDIUM |
| 4 | Code Contamination in Tech Books | MEDIUM | MEDIUM |
| 5 | Redundant Chapter Headers | LOW | MEDIUM |
| 6 | Very Short Segments | LOW | LOW |

---

## Appendix A: Parsing Pipeline Analysis

### Current Architecture

The parsing pipeline is sophisticated and well-designed:

```
EPUB/PDF File
    │
    ▼
┌──────────────────────────────────────────────────────────┐
│  PARSER (epub_parser.dart / pdf_parser.dart)             │
│  - Extract raw HTML/text                                  │
│  - Get metadata (title, author, cover)                    │
│  - Split into chapters by TOC or heuristics               │
└──────────────────────────────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────────────────────────────┐
│  BACKGROUND PROCESSING (background_chapter_processor.dart)│
│  Runs in isolate to avoid UI jank:                        │
│  1. ContentClassifier: Find body matter (skip front/back) │
│  2. BoilerplateRemover: Strip Gutenberg headers, Z-Library│
│  3. StructureAnalyzer: Remove transcriber notes           │
│  4. TextNormalizer: Fix quotes, dashes, entities          │
└──────────────────────────────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────────────────────────────┐
│  SEGMENTATION (sentence_segmenter.dart + core_domain)     │
│  - Split into TTS-friendly segments                       │
│  - Handle abbreviations, decimals, quotes                 │
│  - Target 100-300 chars per segment                       │
└──────────────────────────────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────────────────────────────┐
│  DATABASE (segment_dao.dart)                              │
│  - Store chapters and segments                            │
│  - Index by book_id, chapter_index, segment_index         │
└──────────────────────────────────────────────────────────┘
```

### Strengths of Current Implementation

1. **Isolate Processing**: CPU-intensive text processing runs off main thread
2. **Front/Back Matter Detection**: Skips copyright, TOC, about author sections
3. **Boilerplate Removal**: Comprehensive patterns for Gutenberg, Z-Library, scanner notes
4. **Abbreviation Handling**: Prevents bad splits at "Dr.", "etc.", decimal points
5. **Unicode Normalization**: Converts curly quotes, em-dashes, ligatures for TTS

### Known Limitations

| Limitation | Impact | Complexity to Fix |
|------------|--------|-------------------|
| Anchor extraction bug | HTML attrs in text | LOW (10 min) |
| No image extraction | Missing figures | MEDIUM |
| No table detection | Garbled data | MEDIUM |
| No code detection | Template syntax read | LOW |
| PDF has no structure | Everything is text | HIGH (fundamental) |

### Recommended Improvements (Quick Wins)

#### 1. Fix Anchor Extraction (10 min)
Already documented above - simple fix in `_extractAnchorContent()`.

#### 2. Add Alt Text Preservation (30 min)
In `_stripHtmlToText()`, before removing tags:
```dart
// Preserve image alt text as "[Image: description]"
text = text.replaceAllMapped(
  RegExp(r'<img[^>]*alt="([^"]*)"[^>]*>', caseSensitive: false),
  (m) => '[Figure: ${m.group(1)}] ',
);
```

#### 3. Clean Attribute Remnants (5 min)
Add to `_stripHtmlToText()`:
```dart
// Remove any remaining tag attributes that weren't stripped
text = text.replaceAll(RegExp(r'\w+="[^"]*">\s*'), '');
```

#### 4. Add Code Block Markers (15 min)
In `_stripHtmlToText()`, before removing tags:
```dart
// Mark code blocks for later detection
text = text.replaceAllMapped(
  RegExp(r'<(pre|code)[^>]*>([\s\S]*?)</\1>', caseSensitive: false),
  (m) => '[CODE]${m.group(2)}[/CODE]',
);
```

---

## Appendix B: Query Examples

### Find HTML-contaminated segments
```sql
SELECT b.title, COUNT(*) 
FROM books b JOIN segments s ON b.id = s.book_id 
WHERE s.text LIKE 'id="%' 
GROUP BY b.id;
```

### Find books with Unknown Author
```sql
SELECT title, author FROM books 
WHERE author LIKE '%Unknown%';
```

### Get segment statistics per book
```sql
SELECT b.title, 
       AVG(s.char_count) as avg_chars,
       MIN(s.char_count) as min_chars,
       MAX(s.char_count) as max_chars
FROM books b JOIN segments s ON b.id = s.book_id 
GROUP BY b.id;
```

---

## Appendix C: Recommended Packages

Based on research of pub.dev packages, here are the recommended tools for implementing rich content support:

### Syntax Highlighting for Code Blocks

| Package | Likes | Downloads | Notes |
|---------|-------|-----------|-------|
| **flutter_highlight** `^0.7.0` | 154 | 148k | ⭐ RECOMMENDED - Simple `HighlightView` widget, 189 themes |
| **syntax_highlight** `^0.5.0` | 63 | 21k | Returns `TextSpan` - good for existing RichText integration |
| **highlight** `^0.7.0` | 59 | 157k | Core Dart library (used by flutter_highlight) |
| **flutter_code_editor** `^0.3.5` | 222 | - | Code folding + syntax highlighting (overkill for display-only) |

**Recommendation:** Use `flutter_highlight` for Phase 1 code display:

```dart
// Example usage:
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';

Widget buildCodeSegment(String code, String language) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.grey[900],
      borderRadius: BorderRadius.circular(8),
    ),
    child: HighlightView(
      code,
      language: language,  // 'python', 'dart', 'javascript', etc.
      theme: githubTheme,  // or githubDarkTheme, monokai, etc.
      padding: EdgeInsets.all(12),
      textStyle: TextStyle(fontFamily: 'monospace', fontSize: 14),
    ),
  );
}
```

**Features:**
- 189 built-in themes (GitHub, Monokai, VS Code, etc.)
- Auto-detection of language (optional)
- Pure Flutter widget, works on all platforms
- MIT license

### Markdown Rendering

| Package | Likes | Downloads | Notes |
|---------|-------|-----------|-------|
| **markdown_widget** `^2.3.2` | 406 | 6.5k | ⭐ BEST - TOC, code highlighting, custom tags, HTML support |
| flutter_markdown `^0.7.7` | 1.4k | 147k | ❌ DISCONTINUED - replaced by flutter_markdown_plus |
| **flutter_markdown_plus** | - | - | Successor to flutter_markdown |

**Recommendation:** Use `markdown_widget` if we need full Markdown rendering (less likely for this app):

```dart
// If we parse segments into Markdown format:
MarkdownWidget(
  data: segmentText,
  config: isDark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig,
);
```

**Features:**
- Built-in code highlighting (uses flutter_highlight internally)
- TOC generation
- Dark mode support
- Custom tag support for extensions
- LaTeX support possible

### EPUB Viewing Alternative

| Package | Likes | Notes |
|---------|-------|-------|
| **epub_view** `^3.2.0` | 158 | Full EPUB viewer widget with CFI navigation |

**Note:** Our app uses custom parsing for TTS, so `epub_view` isn't directly applicable. However, its approach to preserving rich content could inform our implementation.

### Table Display

For rendering extracted table data:

| Package | Notes |
|---------|-------|
| **data_table_2** | Enhanced DataTable widget with scrolling |
| **pluto_grid** | Excel-like grid for complex tables |
| Built-in `DataTable` | Simple option for basic tables |

**Recommendation:** For Phase 3, use built-in `DataTable` or `Table` widget since we only need display, not editing.

### Integration Plan

```yaml
# pubspec.yaml additions for Phase 1
dependencies:
  flutter_highlight: ^0.7.0  # Code syntax highlighting

# Optional for Phase 2+
  markdown_widget: ^2.3.2     # If converting segments to Markdown
```

### Implementation in segment_tile.dart

Current rendering is uniform:
```dart
// Current: All segments rendered the same
WidgetSpan(child: Text(segment.text, style: ...))
```

With packages:
```dart
// Enhanced: Type-aware rendering
Widget buildSegment(Segment segment) {
  switch (segment.type) {
    case SegmentType.code:
      return HighlightView(
        segment.text,
        language: segment.metadata?['language'] ?? 'plaintext',
        theme: githubDarkTheme,
      );
    case SegmentType.figure:
      return Column(
        children: [
          Image.file(File(segment.metadata!['imagePath'])),
          Text(segment.text, style: captionStyle),
        ],
      );
    case SegmentType.table:
      return Card(
        child: Column(
          children: [
            Text('TABLE: ${segment.metadata?["caption"] ?? "Data"}'),
            TextButton(onPressed: () => ..., child: Text('View Table')),
          ],
        ),
      );
    default:
      return Text(segment.text, style: normalStyle);
  }
}
```

### Package Evaluation Criteria

✅ **Selected based on:**
- Active maintenance (updated within last year)
- High pub.dev score
- Cross-platform support (including Android)
- Pure Flutter (no native dependencies)
- MIT or BSD license
- Good documentation

❌ **Avoided:**
- Discontinued packages (flutter_markdown)
- Complex dependencies
- Web-only solutions
- Packages requiring native setup
