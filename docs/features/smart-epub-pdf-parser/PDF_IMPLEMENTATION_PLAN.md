# PDF Parser Implementation Plan

## Overview

Add PDF parsing support to the audiobook app, enabling users to import PDF books for TTS playback. The PDF parser will mirror the EPUB parser API and reuse the smart text utilities (TextNormalizer, BoilerplateRemover, ContentClassifier).

## Current State

| Component | Status |
|-----------|--------|
| pdfrx dependency | ✅ In pubspec.yaml (`pdfrx: ^1.0.95`) |
| EPUB parser | ✅ Working (`lib/infra/epub_parser.dart`) |
| Text utilities | ✅ Complete (normalizer, boilerplate, classifier) |
| Sample PDFs | ✅ 6 PDFs in `local_dev/dev_books/pdf/` |
| PDF parser | ✅ Complete (`lib/infra/pdf_parser.dart`) |
| App integration | ✅ Complete - PDF import working |

## Architecture

### Parser Structure

```
lib/infra/
├── epub_parser.dart    # Existing EPUB parser
└── pdf_parser.dart     # New PDF parser (same API pattern)
```

### API Design

```dart
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

class PdfParser {
  const PdfParser(this._paths);
  
  final AppPaths _paths;
  
  Future<ParsedPdf> parseFromFile({
    required String pdfPath,
    required String bookId,
  }) async { ... }
}
```

---

## Implementation Phases

### Phase 1: Basic PDF Parser ✅

**Goal**: Open PDFs and extract text page-by-page.

**Status**: COMPLETE

**Tasks**:
- [x] Create `lib/infra/pdf_parser.dart`
- [x] Open PDF with `PdfDocument.openFile()`
- [x] Extract metadata (title from filename, author placeholder)
- [x] Extract text from all pages
- [x] Return `ParsedPdf` result
- [x] Build chapters by grouping pages (20 pages per chapter default)

**Code Outline**:
```dart
import 'dart:io';
import 'package:pdfrx/pdfrx.dart';
import 'package:core_domain/core_domain.dart';
import '../app/app_paths.dart';

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

class PdfParser {
  const PdfParser(this._paths);
  final AppPaths _paths;
  
  Future<ParsedPdf> parseFromFile({
    required String pdfPath,
    required String bookId,
  }) async {
    final document = await PdfDocument.openFile(pdfPath);
    
    try {
      // Extract metadata
      final title = document.title?.isNotEmpty == true 
          ? document.title! 
          : _extractTitleFromPath(pdfPath);
      final author = document.author?.isNotEmpty == true 
          ? document.author! 
          : 'Unknown Author';
      
      // Extract text from all pages
      final pageTexts = <String>[];
      for (var i = 0; i < document.pages.count; i++) {
        final page = document.pages[i];
        final text = await page.loadText();
        pageTexts.add(text?.fullText ?? '');
      }
      
      // Combine into chapters
      final chapters = _buildChapters(pageTexts, bookId);
      
      return ParsedPdf(
        title: title,
        author: author,
        coverPath: null, // Phase 3
        chapters: chapters,
      );
    } finally {
      document.dispose();
    }
  }
}
```

### Phase 2: Chapter Detection ✅

**Goal**: Split PDF into logical chapters using outline/bookmarks or heuristics.

**Status**: COMPLETE

**Tasks**:
- [x] Load PDF outline with `document.loadOutline()`
- [x] Flatten nested outline structure with `_flattenOutline()`
- [x] Map outline entries to page numbers
- [x] Sort and deduplicate outline entries
- [x] Group pages into chapters based on outline
- [x] Fallback: Split every 20 pages if no outline

**Code Outline**:
```dart
Future<List<Chapter>> _extractChaptersWithOutline(
  PdfDocument document, 
  String bookId,
) async {
  final outline = await document.loadOutline();
  
  if (outline == null || outline.isEmpty) {
    // Fallback to page-based splitting
    return _extractChaptersByPages(document, bookId);
  }
  
  final chapters = <Chapter>[];
  for (var i = 0; i < outline.length; i++) {
    final entry = outline[i];
    final startPage = entry.dest?.pageNumber ?? 0;
    final endPage = (i + 1 < outline.length) 
        ? (outline[i + 1].dest?.pageNumber ?? document.pages.count) - 1
        : document.pages.count - 1;
    
    // Extract text for this chapter
    final text = await _extractPagesText(document, startPage, endPage);
    
    chapters.add(Chapter(
      id: '$bookId-ch-${i + 1}',
      number: i + 1,
      title: entry.title ?? 'Chapter ${i + 1}',
      content: text,
    ));
  }
  
  return chapters;
}
```

### Phase 3: Smart Text Processing ✅

**Goal**: Apply the same text processing pipeline as EPUB parser.

**Status**: COMPLETE

**Tasks**:
- [x] Import and use TextNormalizer
- [x] Import and use BoilerplateRemover
- [x] Import and use ContentClassifier
- [x] Filter front/back matter via `findBodyMatterRange()`
- [x] Remove repeated headers/footers via `detectRepeatedPrefix()`
- [x] Normalize text (quotes, dashes, ligatures)
- [x] Renumber chapters after filtering

**Code Outline**:
```dart
import '../utils/text_normalizer.dart' as tts_normalizer;
import '../utils/boilerplate_remover.dart';
import '../utils/content_classifier.dart';

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
  
  // Find body matter range
  final (startIdx, endIdx) = ContentClassifier.findBodyMatterRange(chapterInfos);
  var bodyChapters = rawChapters.sublist(startIdx, endIdx);
  
  // Clean and normalize each chapter
  bodyChapters = bodyChapters.map((chapter) {
    var content = chapter.content;
    
    // Remove PDF-specific boilerplate (page numbers, headers)
    content = _removePdfBoilerplate(content);
    
    // Remove per-chapter boilerplate
    content = BoilerplateRemover.cleanChapter(content);
    
    // Normalize text
    content = tts_normalizer.TextNormalizer.normalize(content);
    
    return chapter.copyWith(content: content);
  }).toList();
  
  return bodyChapters;
}
```

### Phase 4: PDF-Specific Cleaning ✅

**Goal**: Handle PDF-specific issues not present in EPUBs.

**Status**: COMPLETE

**Tasks**:
- [x] Remove standalone page numbers
- [x] Fix hyphenated words at line breaks
- [x] Remove form feed characters
- [x] Clean up copyright/ISBN lines
- [x] Collapse excessive whitespace

**Code Outline**:
```dart
String _removePdfBoilerplate(String content) {
  var result = content;
  
  // Remove standalone page numbers (common pattern)
  result = result.replaceAll(RegExp(r'^\d+\s*$', multiLine: true), '');
  
  // Fix hyphenated words at line breaks
  result = result.replaceAllMapped(
    RegExp(r'(\w+)-\s*\n\s*(\w+)'),
    (m) => '${m[1]}${m[2]}',
  );
  
  // Collapse excessive whitespace
  result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  result = result.replaceAll(RegExp(r' {2,}'), ' ');
  
  return result.trim();
}
```

### Phase 5: Cover Image Extraction ✅

**Goal**: Extract cover image from PDF first page.

**Status**: COMPLETE

**Tasks**:
- [x] Render first page to image at ~600px width
- [x] Convert RGBA pixels to image package format
- [x] Encode as JPEG (quality 85)
- [x] Save to book directory as cover.jpg
- [x] Return cover path

**Code Outline**:
```dart
Future<String?> _extractCover(
  PdfDocument document, 
  String bookId,
) async {
  if (document.pages.isEmpty) return null;
  
  final firstPage = document.pages[0];
  final image = await firstPage.render(
    width: 400,
    height: 600,
  );
  
  if (image == null) return null;
  
  final dir = _paths.bookDir(bookId);
  await dir.create(recursive: true);
  final dest = File('${dir.path}/cover.jpg');
  
  // Convert to JPEG and save
  final jpgBytes = img.encodeJpg(img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: image.pixels.buffer,
  ));
  
  await dest.writeAsBytes(jpgBytes);
  return dest.path;
}
```

### Phase 6: Integration ✅

**Goal**: Wire PDF parser into the app.

**Status**: COMPLETE

**Tasks**:
- [x] Add PdfParser provider (in pdf_parser.dart)
- [x] Update file picker to accept .pdf files
- [x] Dispatch to correct parser based on file extension
- [x] Add PDF format indicator in UI

**Files updated**:
- `lib/infra/pdf_parser.dart` - Added `pdfParserProvider`
- `lib/app/library_controller.dart` - Updated import, dispatch to correct parser
- `lib/ui/screens/library_screen.dart` - File picker accepts ['epub', 'pdf']

---

## Testing Strategy

### Unit Tests

```
test/infra/pdf_parser_test.dart
```

**Test cases**:
- Parse PDF with outline → chapters match outline
- Parse PDF without outline → page-based chapters
- Text normalization applied
- Empty/corrupt PDF handling
- Metadata extraction

### Integration Tests

```
test/integration/pdf_integration_test.dart
```

**Note**: pdfrx requires native PDFium library. Tests must run on:
- Real Android device
- Desktop (Linux/macOS/Windows)
- NOT in Flutter test harness

---

## PDF Challenges & Mitigations

| Challenge | Mitigation |
|-----------|------------|
| No semantic structure | Use outline; fallback to page groups |
| Repeated headers/footers | Pattern detection and removal |
| Hyphenated words | Regex to rejoin across lines |
| Page numbers in text | Remove standalone number lines |
| Multi-column layout | Accept some text ordering issues |
| No explicit chapters | Use outline or fixed page chunks |

---

## Sample PDFs for Testing

Location: `local_dev/dev_books/pdf/`

| File | Type | Notes |
|------|------|-------|
| The Pragmatic Programmer | Programming | Has outline, clean text |
| SQL Antipatterns | Programming | Tables may cause issues |
| Django for Professionals | Programming | Code blocks |
| AI Engineering | Programming | Modern, good structure |
| Basic Economics | Business | Long chapters, formal |
| The Thinking Machine | Business | Narrative, good TTS target |

---

## Timeline

| Phase | Effort | Priority |
|-------|--------|----------|
| Phase 1: Basic parser | 2-3 hours | High |
| Phase 2: Chapter detection | 2-3 hours | High |
| Phase 3: Smart processing | 1-2 hours | High |
| Phase 4: PDF cleaning | 2-3 hours | Medium |
| Phase 5: Cover extraction | 1 hour | Low |
| Phase 6: Integration | 2-3 hours | High |

**Total estimated: 10-15 hours**

---

## Dependencies

```yaml
# Already in pubspec.yaml
pdfrx: ^1.0.95
image: ^3.3.0  # For cover image processing
```

---

## Success Criteria

1. PDFs from `local_dev/dev_books/pdf/` parse successfully
2. Chapters aligned with PDF outline (when present)
3. Text suitable for TTS (no page numbers, rejoined words)
4. Cover image extracted for library display
5. Same UX as EPUB import
