# GitHub Issue: PDF Image Extraction Support

## Title
**[Feature] Extract and display embedded images from PDF files**

## Labels
- `enhancement`
- `post-mvp`
- `low-priority`

## Milestone
Post-MVP / v2.0

---

## Description

Add support for extracting and displaying embedded images from PDF files during import, similar to the existing EPUB figure support.

### Current State
- EPUB parser extracts `<img>` tags and displays them as figure segments ✅
- PDF parser only extracts text layer via `pdfrx` - images are invisible
- Users who import image-heavy PDFs (textbooks, manuals, illustrated guides) see only text

### User Impact
- **Low**: Most PDF books people read are text-heavy (programming books, novels, business books)
- Image-heavy PDFs (textbooks, illustrated manuals) are a niche use case for audiobook conversion

---

## Technical Analysis

### The Core Challenge
PDFs don't have semantic "image" markers like EPUBs (`<img>` tags). Images are rendered visual elements stored as XObject streams. The `pdfrx` library only exposes:
- `PdfPage.render()` - renders the **entire page** to a bitmap
- `PdfPage.loadText()` - extracts text layer only
- **No API** to enumerate or extract individual embedded images

### Implementation Approaches

| Approach | Effort | Quality | Reliability |
|----------|--------|---------|-------------|
| **A. Render entire pages as images** | 4h | Low | High |
| **B. Visual region detection** | 30-40h | Medium | Low |
| **C. Alternative library** | 10-20h | High | Medium |

#### Approach A: Full Page Rendering
- Render each page as an image, treat as a figure segment
- Pros: Simple, reliable
- Cons: Not useful for TTS (no text/image distinction), huge file sizes

#### Approach B: Visual Region Detection (Computer Vision)
Steps required:
1. Analyze page layout using `loadStructuredText()` for character bounding boxes
2. Identify large rectangular gaps in text (likely image regions)
3. Render those specific rectangular regions using `render(x, y, width, height)`
4. Filter decorative elements (headers, logos, page numbers)
5. Associate extracted images with nearby text segments
6. Generate figure placeholders with positions

Challenges:
- Multi-column layouts confuse gap detection
- Inline small images get missed
- Decorative borders/lines create false positives
- Tables look like images to gap detection
- No alt text available (would need OCR or placeholder text)

#### Approach C: Use a Different PDF Library
- `syncfusion_flutter_pdf` - has image extraction but commercial license
- `pdf_text_extraction` - text only
- Native PDFium bindings - possible but requires FFI work
- `pdf-lib` (JavaScript) - would need platform channels

---

## Recommended Implementation (Post-MVP)

If pursuing this feature, **Approach B** is the only viable path:

### Phase 1: Gap Detection (8-12h)
```dart
Future<List<PdfImageRegion>> detectImageRegions(PdfPage page) async {
  final structuredText = await page.loadStructuredText();
  final charRects = structuredText.fragments.map((f) => f.bounds).toList();
  
  // Find large rectangular gaps not covered by text
  final gaps = _findGaps(
    pageWidth: page.width,
    pageHeight: page.height,
    textRects: charRects,
    minGapSize: 100, // pixels
  );
  
  return gaps.map((g) => PdfImageRegion(rect: g)).toList();
}
```

### Phase 2: Region Rendering (4-6h)
```dart
Future<Uint8List> extractImageRegion(PdfPage page, Rect region) async {
  final scale = 2.0; // 2x resolution
  final image = await page.render(
    x: (region.left * scale).round(),
    y: (region.top * scale).round(),
    width: (region.width * scale).round(),
    height: (region.height * scale).round(),
    fullWidth: page.width * scale,
    fullHeight: page.height * scale,
  );
  return img.encodePng(image);
}
```

### Phase 3: Integration (8-12h)
- Modify PDF parser to call gap detection per page
- Save extracted images to book directory
- Insert `[FIGURE:{path}:::{width}:{height}]` placeholders into chapter text
- Update TextSegmenter to handle these (already done for EPUB)

**Total Estimate: 20-30 hours** (not 12h as originally estimated)

---

## Acceptance Criteria

- [ ] PDF parser detects image regions on each page
- [ ] Image regions rendered and saved to book directory
- [ ] Figure placeholders inserted at correct positions in text
- [ ] Images display in playback screen when `showImages` is enabled
- [ ] TTS says "[Figure]" or skips based on settings
- [ ] No false positives for tables, headers, decorative elements (>90% accuracy)

---

## Alternatives Considered

### Don't Implement (Current Decision)
- EPUB figure support covers the primary use case
- Users with image-heavy PDFs can use dedicated PDF readers
- Focus MVP effort on core TTS experience

### Render Entire Pages
- Too coarse-grained for TTS use case
- Would need to display full pages between text segments
- File size explosion

---

## References

- Current EPUB figure implementation: `lib/infra/epub_parser.dart`
- Image display widget: `lib/ui/screens/playback/widgets/text_display/code_block_widget.dart`
- Related setting: `showImages` in `SettingsController`
- pdfrx documentation: https://pub.dev/packages/pdfrx

---

## Decision

**Postponed until post-MVP.** 

Rationale:
1. Low user value (niche use case)
2. High implementation complexity (20-30h vs other features)
3. Uncertain reliability (computer vision heuristics)
4. EPUB figure support already covers the cleaner case
