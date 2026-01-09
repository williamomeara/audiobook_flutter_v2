# PDF Parser Implementation Plan

## Executive Summary

This document outlines the implementation plan for adding PDF parsing support to the audiobook app, enabling users to import PDF books for TTS conversion.

## Current State

- **pdfrx dependency**: Already in pubspec.yaml (`pdfrx: ^1.0.95`)
- **EPUB parser**: Fully functional (`lib/infra/epub_parser.dart`)
- **Smart text utilities**: Complete (TextNormalizer, BoilerplateRemover, ContentClassifier, SentenceSegmenter)
- **Sample PDFs**: 6 PDFs in `local_dev/dev_books/pdf/`

## Research Findings

### pdfrx Capabilities

pdfrx (based on PDFium) provides:
- `PdfDocument.openFile()` - Open PDF from file path
- `document.pages` - Access all pages
- `page.loadText()` - Extract plain text from page
- `page.loadStructuredText()` - Extract text with character bounding boxes
- `document.outline` - PDF bookmarks/outline for chapter detection

### Alternative Libraries Considered

| Library | Pros | Cons |
|---------|------|------|
| **pdfrx** (chosen) | Already a dependency, good API, cross-platform | Limited layout analysis |
| Syncfusion Flutter PDF | Excellent text extraction with font/bounds | Licensing for commercial |
| Python backends | Best-in-class layout analysis | Requires server, complex |

### PDF Challenges vs EPUB

1. **No semantic structure**: PDFs are visual, not semantic like EPUB
2. **Headers/footers repeat**: Every page may have page numbers, titles
3. **Multi-column layouts**: Text order can be wrong
4. **Hyphenation**: Words split across lines
5. **No explicit chapters**: Must infer from outline or headings

---

## Implementation Phases

### Phase 1: Basic PDF Parser (Core)

**File**: `lib/infra/pdf_parser.dart`

**Goals**:
- Open PDF files with pdfrx
- Extract text from all pages
- Detect chapters from PDF outline/bookmarks
- Return Book model compatible with existing app

**Implementation**:

```dart
class PdfParser {
  final AppPaths _paths;
  
  const PdfParser(this._paths);
  
  Future<Book> parseFromFile({required String path}) async {
    final document = await PdfDocument.openFile(path);
    
    try {
      // Extract metadata
      final title = document.title ?? _extractTitleFromPath(path);
      final author = document.author ?? 'Unknown Author';
      
      // Get outline (chapters)
      final outline = await document.loadOutline();
      
      // Extract chapters based on outline or pages
      final chapters = await _extractChapters(document, outline);
      
      // Process chapters with smart utilities
      final processedChapters = _processChapters(chapters);
      
      // Save to database
      return _saveBook(title, author, processedChapters, path);
    } finally {
      document.dispose();
    }
  }
  
  Future<List<Chapter>> _extractChapters(
    PdfDocument doc, 
    List<PdfOutlineNode>? outline
  ) async {
    if (outline != null && outline.isNotEmpty) {
      // Use outline for chapter detection
      return _extractFromOutline(doc, outline);
    } else {
      // Fallback: treat entire document as one chapter
      // or use page ranges
      return _extractFromPages(doc);
    }
  }
}
```

**Deliverables**:
- [ ] `lib/infra/pdf_parser.dart`
- [ ] Unit tests for basic extraction
- [ ] Integration with library import flow

### Phase 2: Header/Footer Detection

**Goals**:
- Detect repeating content at top/bottom of pages
- Remove detected headers/footers from extracted text
- Handle page numbers in various formats

**Algorithm**:

```dart
class PdfHeaderFooterDetector {
  // Sample first N pages
  static const _sampleSize = 10;
  
  // Height thresholds (percentage of page)
  static const _headerZone = 0.1; // Top 10%
  static const _footerZone = 0.9; // Bottom 10%
  
  /// Detect repeating headers/footers across pages
  static Future<PdfPageZones> detect(PdfDocument doc) async {
    // 1. Extract text with positions from sample pages
    // 2. Group text by vertical position
    // 3. Find text that appears on >70% of pages in header/footer zones
    // 4. Return patterns to exclude
  }
}
```

**Patterns to detect**:
- Page numbers: "123", "- 123 -", "[123]", "Page 123"
- Running headers: Book title, chapter title repeated
- Publisher info: Copyright, edition info at bottom

**Deliverables**:
- [ ] `lib/utils/pdf_header_footer_detector.dart`
- [ ] Tests with sample PDFs
- [ ] Integration with PDF parser

### Phase 3: Layout Analysis (Advanced)

**Goals**:
- Handle multi-column layouts
- Preserve reading order
- Handle text blocks and paragraphs

**Approach**:

```dart
class PdfLayoutAnalyzer {
  /// Analyze page layout and determine reading order
  static Future<List<TextBlock>> analyzePageLayout(PdfPage page) async {
    final text = await page.loadStructuredText();
    
    // 1. Group characters into words, lines, blocks
    // 2. Detect columns by horizontal gaps
    // 3. Order blocks by reading order (top-to-bottom, left-to-right per column)
    // 4. Return ordered text blocks
  }
  
  /// Detect if page has multi-column layout
  static bool isMultiColumn(List<TextBlock> blocks) {
    // Check for significant horizontal gaps
    // Multiple blocks at similar Y positions
  }
}
```

**Deliverables**:
- [ ] `lib/utils/pdf_layout_analyzer.dart`
- [ ] Multi-column detection algorithm
- [ ] Tests with various PDF layouts

### Phase 4: Text Processing Integration

**Goals**:
- Apply existing smart text utilities to PDF content
- Handle PDF-specific issues (hyphenation, line breaks)

**PDF-Specific Processing**:

```dart
class PdfTextProcessor {
  /// Process raw PDF text for TTS
  static String process(String rawText) {
    var result = rawText;
    
    // 1. Dehyphenation (merge split words)
    result = _dehyphenate(result);
    
    // 2. Fix line breaks (PDF often has hard breaks)
    result = _fixLineBreaks(result);
    
    // 3. Apply standard normalization
    result = TextNormalizer.normalize(result);
    
    // 4. Clean boilerplate
    result = BoilerplateRemover.cleanChapter(result);
    
    return result;
  }
  
  /// Merge words split by hyphen at line end
  static String _dehyphenate(String text) {
    // Pattern: "word-\nend" -> "wordend"
    return text.replaceAllMapped(
      RegExp(r'(\w+)-\s*\n\s*(\w+)'),
      (m) => '${m[1]}${m[2]}',
    );
  }
  
  /// Convert hard line breaks to spaces where appropriate
  static String _fixLineBreaks(String text) {
    // Replace single newlines (not paragraph breaks) with spaces
    return text.replaceAllMapped(
      RegExp(r'(\S)\n(\S)'),
      (m) => '${m[1]} ${m[2]}',
    );
  }
}
```

**Deliverables**:
- [ ] `lib/utils/pdf_text_processor.dart`
- [ ] Dehyphenation algorithm
- [ ] Line break fixing
- [ ] Tests with real PDF text

### Phase 5: PDF Analysis Tool

**Goals**:
- Analyze sample PDFs similar to EPUB analysis
- Report on text quality, structure, issues
- Guide further improvements

**File**: `test/pdf_text_analysis_test.dart`

```dart
void main() async {
  final pdfDir = Directory('local_dev/dev_books/pdf');
  
  for (final entry in pdfDir.listSync(recursive: true)) {
    if (entry.path.endsWith('.pdf')) {
      print('Processing: ${basename(entry.path)}');
      
      final doc = await PdfDocument.openFile(entry.path);
      
      // Analyze
      final analysis = PdfAnalysisResult(
        pageCount: doc.pages.length,
        hasOutline: (await doc.loadOutline())?.isNotEmpty ?? false,
        hasHeadersFooters: await _detectHeadersFooters(doc),
        textQuality: await _assessTextQuality(doc),
      );
      
      // Report
      print(analysis.toJson());
      
      doc.dispose();
    }
  }
}
```

**Deliverables**:
- [ ] `test/pdf_text_analysis_test.dart`
- [ ] Analysis results in JSON format
- [ ] Summary of issues found

### Phase 6: Integration & Testing

**Goals**:
- Full integration with app
- UI for PDF import
- Comprehensive testing

**Deliverables**:
- [ ] Update library controller to handle PDFs
- [ ] File picker filter for PDF files
- [ ] Integration tests
- [ ] Documentation

---

## Timeline Estimate

| Phase | Effort | Priority |
|-------|--------|----------|
| Phase 1: Basic Parser | 4-6 hours | High |
| Phase 2: Header/Footer Detection | 3-4 hours | High |
| Phase 3: Layout Analysis | 6-8 hours | Medium |
| Phase 4: Text Processing | 2-3 hours | High |
| Phase 5: Analysis Tool | 2-3 hours | Medium |
| Phase 6: Integration | 3-4 hours | High |

**Total**: 20-28 hours

---

## Technical Decisions

### Why pdfrx over Syncfusion?

1. **Already a dependency**: Reduces additional bloat
2. **PDFium-based**: Mature, well-tested PDF engine
3. **MIT-compatible**: No licensing concerns
4. **Sufficient for TTS**: Text extraction is adequate; don't need advanced features

### Why not pure Python backend?

1. **Complexity**: Would require server or background process
2. **Latency**: Network round-trip for each PDF
3. **Offline**: App wouldn't work offline
4. **Good enough**: pdfrx is sufficient for book-length text extraction

### Reading Order Strategy

For multi-column detection:
1. Use horizontal gap analysis
2. Group text blocks by X position
3. Sort groups left-to-right
4. Sort within groups top-to-bottom
5. Merge groups for final reading order

---

## Related Issues

- #30: PDF layout analysis (sub-task of this plan)
- #32: Implement PDF parser using pdfrx (main issue)

---

## Success Criteria

1. PDFs from `local_dev/dev_books/pdf/` parse successfully
2. Chapter detection works for PDFs with outlines
3. Headers/footers removed from extracted text
4. Text normalization produces TTS-friendly output
5. No regressions in EPUB parsing
6. All tests pass
