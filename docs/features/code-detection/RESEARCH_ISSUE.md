# Code Block Detection - Research for Future

## Current State

The app has a basic `SegmentTypeDetector` class that attempts to detect code blocks using heuristic patterns (def/class keywords, import statements, shell commands, etc.). This works at **runtime** during playback as a fallback mechanism.

### What Works
- Basic detection of code patterns (Python def/class, imports, shell commands)
- Detection of figure placeholders (`[FIGURE:]`)
- Table detection (markdown tables with `|` separators)

### Current Issues Discovered

1. **Different books use different formats:**
   - **Django for Professionals (PDF)**: Uses explicit markers like "Code #" and "Command Line $" to prefix code blocks
   - **Go Programming Language (PDF)**: Has no markers - code is inline within paragraphs
   - Each book publisher/author uses their own formatting conventions

2. **PDF text extraction loses formatting:**
   - PDFs don't preserve semantic structure like "this is code"
   - Visual formatting (monospace fonts, indentation) is lost in text extraction
   - Code blocks become indistinguishable from prose at the text level

3. **Segmentation happens before detection:**
   - `TextSegmenter` groups text by sentence count (~100 chars)
   - If ANY part of a grouped segment has code patterns, the whole segment is marked as code
   - This causes code segments to include surrounding explanatory text

## Research Areas for Future

### 1. EPUB vs PDF Handling
- EPUBs preserve HTML structure - `<pre>`, `<code>` tags could be used for detection
- PDFs need different strategies (visual analysis, font detection, layout parsing)
- Consider different import paths for each format

### 2. Better Code Marker Detection
- Build a library of publisher-specific patterns
- Allow users to configure patterns for their books
- Machine learning approach to learn from user corrections

### 3. Segment-Level Classification
- Classify each segment independently AFTER segmentation
- Use confidence thresholds that can be tuned
- Consider context (previous/next segment types)

### 4. User Control
- Allow users to mark segments as code/text
- Persist user corrections for learning
- Option to disable code detection entirely per book

### 5. Alternative Approaches
- Visual page analysis using computer vision
- OCR with layout awareness
- Integration with publisher APIs (if available)

## Why Deprioritized for MVP

1. Most audiobook content is fiction/non-fiction prose without code
2. Technical books are a niche use case
3. The core TTS playback works regardless of segment type classification
4. Users can still listen to code segments - they just won't be visually highlighted differently

## Files Involved

- `packages/core_domain/lib/src/utils/segment_type_detector.dart` - Pattern-based detection
- `packages/core_domain/lib/src/utils/text_segmenter.dart` - Text segmentation
- `lib/app/playback_providers.dart` - Runtime detection fallback (lines ~792, ~966)

## Labels

- `enhancement`
- `research-needed`
- `technical-books`
- `post-mvp`
