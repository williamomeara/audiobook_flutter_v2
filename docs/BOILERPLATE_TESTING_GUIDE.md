# Boilerplate Detection Testing & Analysis Guide

This guide explains how to use the comprehensive testing infrastructure for validating boilerplate removal effectiveness and preventing false positives.

## Overview

The testing system includes:
1. **Enhanced Analysis Tool** - Compares boilerplate removal before/after StructureAnalyzer
2. **Synthetic EPUB Generator** - Creates reproducible test cases with known patterns
3. **Test Database Builder** - Sets up SQLite database with test data for integration testing
4. **Detailed Reports** - JSON and Markdown output comparing effectiveness

## Quick Start

### Generate Synthetic Test EPUBs

```bash
dart run test/synthetic_epub_generator.dart
```

Creates three test books in `test/fixtures/synthetic_epubs/`:
- `heavy_boilerplate.epub` - Every pattern from the enhanced detection list
- `light_boilerplate.epub` - Minimal Project Gutenberg boilerplate
- `edge_cases.epub` - Edge cases and repeated headers (tests false positives)

### Create Test Database

```bash
dart run test/test_database_builder.dart
```

Creates `test/fixtures/test_audiobook.db` with:
- 3 test books (heavy, light, clean)
- 9 total chapters with realistic content
- Schema matching your app's database

### Run Comparison Analysis

#### On Real Project Gutenberg EPUBs

```bash
dart test/epub_comparison_analysis_test.dart
```

Requires: EPUB files in `local_dev/dev_books/epub/`

Generates:
- `test/epub_analysis_output/comparison_results_detailed.json` - Full per-chapter data
- `test/epub_analysis_output/comparison_report.md` - Human-readable summary

#### On Synthetic Test EPUBs

```bash
# First generate the synthetic EPUBs
dart run test/synthetic_epub_generator.dart

# Then move them to the test directory
mv test/fixtures/synthetic_epubs/*.epub local_dev/dev_books/epub/

# Run the analysis
dart test/epub_comparison_analysis_test.dart
```

## Understanding the Output

### Comparison Results (JSON)

```json
{
  "book.epub": {
    "title": "Book Title",
    "author": "Author Name",
    "chapterCount": 10,
    "chapters": [
      {
        "number": 1,
        "title": "Chapter 1",
        "wordCounts": {
          "raw": 5000,
          "normalized": 4950,
          "oldPipeline": 4800,
          "newPipeline": 4650
        },
        "reductions": {
          "oldPipelinePercent": 4.0,
          "newPipelinePercent": 7.0,
          "additionalPercent": 3.125,
          "wordsSavedByNew": 150
        },
        "contentComparison": {
          "oldPipelineFirst100": "...",
          "newPipelineFirst100": "...",
          "oldPipelineLast100": "...",
          "newPipelineLast100": "..."
        },
        "falsePositiveCheck": {
          "oldUnchangedFromNew": false,
          "significantAdditionalRemoval": false
        }
      }
    ],
    "summary": {
      "chaptersAnalyzed": 10,
      "totalRawWords": 50000,
      "oldPipelineReduction": 4.2,
      "newPipelineReduction": 7.1,
      "additionalReduction": 2.9,
      "totalWordsRemovedByNew": 1450,
      "chaptersWithAdditionalRemoval": 8
    }
  }
}
```

### Key Metrics Explained

- **oldPipelineReduction** (%)
  - Content removed by existing BoilerplateRemover
  - Baseline to compare against

- **newPipelineReduction** (%)
  - Content removed by new pipeline (including StructureAnalyzer)
  - Target: 3-5% additional reduction on PG books

- **additionalReduction** (%)
  - Extra content removed only by new pipeline
  - Check for false positives if >20% on any chapter

- **contentComparison**
  - First/last 100 words before and after
  - Manually review to verify no story content removed

- **falsePositiveCheck**
  - `significantAdditionalRemoval: true` = manual review needed
  - `oldUnchangedFromNew: true` = new pipeline made no changes

## False Positive Detection Strategy

### Warning Signs

1. **Chapter loses >50% content**
   ```json
   "significantAdditionalRemoval": true
   ```
   → Review `contentComparison.oldPipelineFirst100` vs `newPipelineFirst100`

2. **Last 100 words differ significantly**
   ```
   Old:  "...and the story concludes with resolution."
   New:  "..."  (empty or truncated)
   ```
   → Likely removed ending - regression!

3. **Natural content removed**
   - If `newPipelineFirst100` contains dialogue or narrative
   - If patterns match legitimate content (e.g., "Chapter 5 Epilogue")

### Verification Workflow

1. **Run analysis** on target books
2. **Check summary report** for `additionalReduction` by book
3. **For high-removal books** (>5% additional):
   - Review full JSON for per-chapter data
   - Look at `contentComparison` samples
   - Manually check if content is actually boilerplate
4. **If false positives found**:
   - Note which pattern caused removal
   - Consider adjusting pattern or threshold
   - Add test case to prevent regression

## Testing Different Boilerplate Patterns

### Create Targeted Test Books

Edit `test/synthetic_epub_generator.dart` to test specific patterns:

```dart
// Add to boilerplate generation
String _generateBoilerplate(String intensity, int chapterNumber) {
  if (intensity == 'custom') {
    return '''
<p>PATTERN TO TEST HERE</p>
<p>This is what we're validating</p>
''';
  }
  // ... rest of function
}
```

Then generate and test:
```bash
dart run test/synthetic_epub_generator.dart
dart test/epub_comparison_analysis_test.dart
```

### Test Cases to Validate

1. **Production Credits**
   ```
   e-text prepared by Project Gutenberg volunteers
   HTML version created 2024
   Transcribed by volunteers
   ```

2. **License Markers**
   ```
   Distributed under Creative Commons License
   This work is in the public domain
   ```

3. **Encoding Notices**
   ```
   UTF-8 encoded
   Chapter divisions have been added
   ```

4. **Editor Notes**
   ```
   [Footnote: Transcriber's note]
   [Note by editor: Added for clarity]
   [Illustration: Figure caption]
   ```

5. **Chapter-Spanning Patterns**
   - Same header/footer in 80%+ of chapters
   - Should be detected by `detectChapterSpanningBoilerplate()`

## Database-Based Integration Testing

### Using Test Database in Dart Tests

```dart
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('import and segment book from database', () {
    final db = sqlite3.open('test/fixtures/test_audiobook.db');

    try {
      final books = db.select('SELECT * FROM books');
      expect(books.length, greaterThan(0));

      // Test import pipeline
      for (final book in books) {
        final chapters = db.select(
          'SELECT * FROM chapters WHERE book_id = ?',
          [book['id']],
        );

        // Process through segmentation pipeline
        // Verify no false positives
      }
    } finally {
      db.dispose();
    }
  });
}
```

### Database Schema

**Books Table**
```sql
id (TEXT PRIMARY KEY)
title (TEXT)
author (TEXT)
cover_path (TEXT nullable)
created_at (INTEGER)
updated_at (INTEGER)
```

**Chapters Table**
```sql
id (TEXT PRIMARY KEY)
book_id (TEXT FOREIGN KEY)
number (INTEGER)
title (TEXT nullable)
content (TEXT)
created_at (INTEGER)
```

## Continuous Validation

### Before Committing Boilerplate Changes

1. Generate synthetic EPUBs
2. Run comparison analysis
3. Review summary report for:
   - `additionalReduction` < 5% on normal books
   - No `significantAdditionalRemoval` warnings
4. Manually verify content samples don't contain story text
5. Run full test suite: `flutter test test/utils/`

### Regression Testing

Add chapters to `test/epub_comparison_analysis_test.dart` that were problematic:

```dart
// Store chapters that were false positives
const falsePositiveChapters = [
  'chapter_with_dialogue_starting_with_chapter.txt',
  'chapter_with_editor_names.txt',
];

// Create test cases that verify these still work
```

## Expected Results on Real Books

### Project Gutenberg Books (Heavy Boilerplate)

- **Additional Reduction**: 3-5%
- **Safe Pattern Detection**: >95% accuracy
- **False Positives**: <1% of chapters

### Sample Results

| Book | Old % | New % | Additional % | Notes |
|------|-------|-------|--------------|-------|
| Moby Dick | 4.2 | 7.1 | 2.9 | Excellent - as planned |
| Pride & Prejudice | 3.8 | 6.5 | 2.7 | Good |
| Jane Eyre | 4.1 | 6.8 | 2.7 | Good |

## Troubleshooting

### "EPUB directory not found" Error

```bash
# Create the expected directory
mkdir -p local_dev/dev_books/epub

# Add EPUB files to it, or generate synthetic ones
dart run test/synthetic_epub_generator.dart
mv test/fixtures/synthetic_epubs/* local_dev/dev_books/epub/
```

### Analyzer Errors in Test Files

Make sure `core_domain` package is available:
```bash
flutter pub get
```

### Database Already Exists

The builder automatically removes the old database, but if you have permission issues:
```bash
rm test/fixtures/test_audiobook.db
dart run test/test_database_builder.dart
```

## Next Steps

After validating the implementation:

1. **Phase 2**: Segment confidence scoring
2. **Phase 3**: Batch import optimization
3. **Phase 4**: User-configurable quality levels
4. **Phase 5**: Re-import pipeline for books with improved patterns

See `docs/features/smart-audio-synth/BOILERPLATE_IMPLEMENTATION_EXAMPLES.md` for detailed pattern examples.
