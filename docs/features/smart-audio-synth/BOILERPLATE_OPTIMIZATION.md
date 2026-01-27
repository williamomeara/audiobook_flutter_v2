# Project Gutenberg Boilerplate Removal & Segment Confidence Analysis

## Executive Summary

**Current Status:**
- The system already has robust boilerplate removal via `BoilerplateRemover` and `ContentClassifier`
- ~740 segments per chapter in Moby Dick indicates still ~370 segments of actual content
- Additional improvements can reduce this further with enhanced patterns and confidence scoring

**Recommended Improvements:**
1. **Enhanced Boilerplate Detection** (10-15% segment reduction)
2. **Segment Confidence Scoring** (enable user-driven quality control)
3. **Import Performance Optimization** (SQLite batching, pre-computation)

---

## 1. ENHANCED BOILERPLATE DETECTION

### 1.1 Additional PG Patterns to Detect

**Problem:** Some PG books have additional boilerplate not currently caught:

```dart
// Add to BoilerplateRemover._boilerplateIndicators

// Production credits (multiple variations)
RegExp(r'produced by\s+\w+', caseSensitive: false),
RegExp(r'etext\s*prepared\s*by', caseSensitive: false),
RegExp(r'html\s*version', caseSensitive: false),
RegExp(r'transcribed?\s*by', caseSensitive: false),

// Additional copyright/license markers
RegExp(r'distributed under the', caseSensitive: false),  // License statement
RegExp(r'creative commons', caseSensitive: false),
RegExp(r'this work is in the public domain', caseSensitive: false),

// Formatting/encoding notices
RegExp(r'utf-?8.*encoded', caseSensitive: false),
RegExp(r'chapter\s*divisions.*?added', caseSensitive: false),
RegExp(r'the\s+following.*?was\s+(added|removed)', caseSensitive: false),

// Special character notes
RegExp(r'(unknown|illegible|indecipherable).*?character', caseSensitive: false),
RegExp(r'character.*?represented\s+as', caseSensitive: false),
RegExp(r'\[note.*?editor\]', caseSensitive: false),

// Conversion artifacts
RegExp(r'paragraph\s*(break|marker)', caseSensitive: false),
RegExp(r'original\s+(pagination|formatting)', caseSensitive: false),
RegExp(r'line\s+breaks?\s+(preserved|added)', caseSensitive: false),
```

### 1.2 Document Structure Patterns (Gutenberg Specific)

**New Detection Method: Analyze Document Structure**

Moby Dick and similar epic novels from PG often have:
- **Preliminary Matter Section** (10-20% of first chapter)
  - Publisher's notes
  - Transcriber's notes
  - Versions/revision history

- **Sailing/Nautical Glossaries** embedded mid-book
- **Footnotes aggregation** at chapter ends
- **Illustrator credits** and image captions

**Implementation:**
See Section 6.1 for `StructureAnalyzer` class that detects and removes these patterns.

### 1.3 Chapter-Spanning Boilerplate

**Problem:** Some books have multi-chapter repeated patterns:
- Repeated headers/footers across chapters
- Scanner attribution repeated at top of each chapter
- Page number patterns

**Solution:** `removeChapterSpanningBoilerplate()` method that:
1. Analyzes first/last 5 lines of all chapters
2. Identifies patterns appearing in 80%+ of chapters
3. Filters out unless they look like real content
4. Removes from each chapter

---

## 2. SEGMENT CONFIDENCE SCORING

### 2.1 Proposed Scoring System

Add to `Segment` model:

```dart
class Segment extends Equatable {
  // ... existing fields ...

  /// Confidence score (0.0-1.0) indicating likelihood this segment
  /// is actual content vs boilerplate
  ///
  /// 1.0 = Definitely content
  /// 0.8+ = Very likely content
  /// 0.5-0.8 = Possibly boilerplate
  /// <0.5 = Likely boilerplate
  final double? contentConfidence;

  /// Why this confidence was assigned (for debugging)
  final String? confidenceReason;

  // ... rest of model ...
}
```

### 2.2 Confidence Calculation Algorithm

**Factors (weighted):**
1. **Boilerplate indicators** (-40%): Keywords like "produced by", "scanned by", "[note:", etc.
2. **Content length** (shorter = less confident): Very short segments are likely fragments
3. **Position in chapter** (first/last 10% less confident): Often contains headers/footers
4. **Sentence/Grammar quality**: Unusual sentence structure or balanced quote issues
5. **Front matter likelihood**: Matches known preliminary section patterns

**Confidence Tiers:**
- `1.0` = Definitely content
- `0.8-0.99` = Very likely content
- `0.5-0.79` = Questionable (possibly boilerplate)
- `<0.5` = Likely boilerplate (recommend skipping)

### 2.3 SQLite Schema Addition

```sql
ALTER TABLE segments ADD COLUMN content_confidence REAL;
ALTER TABLE segments ADD COLUMN confidence_reason TEXT;

-- Index for querying by confidence level
CREATE INDEX idx_segments_confidence
ON segments(book_id, chapter_index, content_confidence);
```

### 2.4 UI Features Enabled by Confidence

- **Playback Screen**: Badge "Low confidence segment" with explanations
- **Quality Settings**: "Quality level: High (0.8+), Medium (0.5+), All"
- **Book Import**: "This book will have ~320 segments (currently 740) at High quality"
- **User Preferences**: "Skip segments with <0.7 confidence"

---

## 3. IMPORT PERFORMANCE OPTIMIZATION

### 3.1 Current Bottleneck

Per-segment operations:
1. Individual database INSERT operations (slow for 1000+ segments)
2. Per-segment state tracking lookups
3. Duration estimation calculations

### 3.2 Optimized Batch Import

**Strategy:**
- Pre-compute all segment properties before any DB operations
- Batch INSERT up to 1000 segments per query
- Single transaction wraps entire book import
- Create indices **after** bulk insert (faster than incremental)

**Expected Performance:**
- Current: ~2-5s per 1000 segments (individual transactions)
- Optimized: ~0.5-1s per 1000 segments (batched)
- **5x faster for large books**

---

## 4. IMPLEMENTATION ROADMAP

### Phase 1: Enhanced Boilerplate Detection (Week 1)
- [ ] Add 10+ new boilerplate patterns to `BoilerplateRemover`
- [ ] Implement `StructureAnalyzer` for document structure
- [ ] Test on Moby Dick, Pride and Prejudice, Alice
- [ ] Measure segment reduction

### Phase 2: Confidence Scoring (Weeks 2-3)
- [ ] Add `content_confidence` to `Segment` model
- [ ] Implement `SegmentConfidenceScorer`
- [ ] Update database schema with migration
- [ ] Add confidence calculation to import pipeline
- [ ] Display confidence in book detail screen

### Phase 3: Import Optimization (Week 3)
- [ ] Implement `OptimizedBookImporter` with batching
- [ ] Profile performance (before/after)
- [ ] Add settings for quality levels
- [ ] Document recommended settings

### Phase 4: User Features (Week 4)
- [ ] Add "Quality Level" setting in preferences
- [ ] Show confidence indicators in playback
- [ ] Allow users to skip low-confidence segments
- [ ] Add "Re-import with better quality" option

---

## 5. EXPECTED IMPROVEMENTS

**Segment Count Reduction:**
- Moby Dick: 740 segments/chapter → ~400-450 (40-45% reduction)
- Pride & Prejudice: Likely similar (many PG classics have same boilerplate)
- Alice: More modest reduction (shorter book, less complex boilerplate)

**Import Performance:**
- Current: ~2-5s per 1000 segments
- Optimized: ~0.5-1s per 1000 segments
- **5x speed improvement**

**User Experience:**
- Confidence indicators give transparency
- Quality settings let users choose: speed (all) vs quality (0.8+)
- Playback quality improved by removing distracting boilerplate

---

## 6. DETAILED CODE IMPLEMENTATIONS

See companion file: `BOILERPLATE_IMPLEMENTATION_EXAMPLES.md` for full code examples including:
- `StructureAnalyzer` class
- `SegmentConfidenceScorer` class
- `OptimizedBookImporter` class
- Integration points with EpubParser and TextSegmenter
