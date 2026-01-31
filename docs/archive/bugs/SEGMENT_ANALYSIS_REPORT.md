# Segment Analysis Report

**Date:** January 2026  
**Database:** eist_audiobook.db (device at 192.168.1.151:8082)  
**Schema Version:** 8

---

## Executive Summary

Analyzed 9 imported books (7 EPUBs, 2 PDFs) with **51,977 total segments**. The parsing pipeline is working well for core text extraction. Key findings:

### ✅ What's Working Well
1. **Figure extraction from EPUBs** - 586 figure segments with dimensions
2. **Text segmentation** - Proper sentence-boundary splitting (~100-300 chars)
3. **Metadata preservation** - Figure paths, dimensions, alt text stored correctly
4. **Chapter detection** - Working for both EPUBs and PDFs

### ⚠️ Issues Found

| Priority | Issue | Impact | Books Affected |
|----------|-------|--------|----------------|
| **HIGH** | Code blocks not detected as `code` type | Code read aloud unnecessarily | Django (82 segments), Go |
| **MEDIUM** | HTML artifacts leaking into segments | Garbled TTS | Christmas Carol |
| **LOW** | Many "header" chapters with 1 segment | UX clutter | Most EPUBs |
| **LOW** | No figures in PDFs | Expected limitation | Django, Basic Economics |

---

## Detailed Findings

### 1. Segment Type Distribution

| Type | Count | Percentage |
|------|-------|------------|
| text | 51,391 | 98.87% |
| figure | 586 | 1.13% |
| code | 0 | 0% |
| table | 0 | 0% |

**Issue:** No code segments despite programming books in the library. The `SegmentTypeDetector` runs at **runtime** (playback), not at import time. The stored `segment_type` is only `text` or `figure`.

### 2. Code Detection Gap (Django Book)

82 segments start with "Code #" prefix indicating code blocks, but all are stored as `segment_type='text'`:

```
Example segments:
- "Code # pages/views.py from django.http import HttpResponse def home_page_view(request): return HttpResponse('Hello, World!')"
- "Code # users/models.py from django.contrib.auth.models import AbstractUser..."
```

**Root Cause:** TextSegmenter only detects figures at import. Code detection happens via `SegmentTypeDetector.detect()` at playback time.

**Recommendation:** Either:
1. Accept runtime detection (current behavior works but wastes storage opportunity)
2. Add code detection to TextSegmenter at import time

### 3. HTML Artifacts in Segments

Found raw HTML fragments in Christmas Carol segments:

```
"09\"> STAVE ONE. <h4"
"12\"> STAVE TWO. <h4"
```

**Root Cause:** EPUB HTML stripping not fully removing all tags.

**Location:** `lib/infra/epub_parser.dart` - `_stripHtmlToText()` function

### 4. Minimal Chapters (Header-Only)

42 chapters have ≤3 segments. Most are legitimate:
- Part dividers ("PART I", "PART II")
- Section headers ("STAVE ONE.", "STAVE TWO.")
- Front matter ("TITLE PAGE", "CONTENTS", "DEDICATION")

These are expected for EPUBs with detailed TOC. Consider:
- Auto-hiding chapters with only 1 figure segment when `showImages=false` ✅ (implemented)
- Potentially merging very short chapters into adjacent ones (future enhancement)

### 5. Figure Segment Quality

Figure segments are well-formed with dimensions:

```json
{
  "imagePath": "/data/.../images/img_0012.jpg",
  "altText": "image",
  "width": 697,
  "height": 1048
}
```

**Note:** Many figures have generic "image" alt text. This is EPUB source issue, not parser issue.

### 6. Segment Size Distribution

| Book | Tiny (<10) | Small (10-50) | Very Long (>500) |
|------|------------|---------------|------------------|
| Django | 0 | 185 | 0 |
| Strength of Few | 151 | 1,984 | 0 |
| Go Programming | 3 | 16 | 0 |
| Basic Economics | 0 | 450 | 0 |
| Pride and Prejudice | 156 | 634 | 0 |
| Christmas Carol | 0 | 120 | 0 |
| Conjuring of Light | 268 | 923 | 0 |
| Moby Dick | 0 | 761 | 0 |
| Frankenstein | 0 | 215 | 0 |

**Tiny segments** correlate exactly with figure counts - figures use alt text ("image" = 5 chars).

---

## Book-by-Book Status

### EPUBs with Figures ✅
- **The Strength of the Few**: 14,320 segments, 151 figures - GOOD
- **A Conjuring of Light**: 7,679 segments, 268 figures - GOOD
- **Pride and Prejudice**: 5,299 segments, 158 figures - GOOD
- **A Christmas Carol**: 1,014 segments, 6 figures - HTML ARTIFACTS
- **Go Programming**: 426 segments, 3 figures - Inline code not detected

### EPUBs without Figures
- **Moby Dick**: 8,072 segments - GOOD
- **Frankenstein**: 2,971 segments - GOOD

### PDFs (No Figure Support)
- **Django**: 2,402 segments - CODE NOT TYPED
- **Basic Economics**: 9,794 segments - GOOD

---

## Recommendations

### Immediate (Pre-MVP)
1. **Fix HTML artifact stripping** in epub_parser.dart
2. Consider adding "skip chapter if ≤1 text segment" logic

### Post-MVP
1. **Code detection at import time** - Add to TextSegmenter
2. **PDF image extraction** - Already documented as GitHub issue
3. **Smarter alt text generation** - Use OCR or filename parsing

---

## Technical Notes

### Database Queries Used
```sql
-- Segment type distribution
SELECT segment_type, COUNT(*) FROM segments GROUP BY segment_type;

-- Code-prefixed segments
SELECT COUNT(*) FROM segments 
WHERE book_id = (SELECT id FROM books WHERE title LIKE '%Django%') 
AND text LIKE 'Code %';

-- Minimal chapters
SELECT title, COUNT(s.id) as segment_count 
FROM chapters c JOIN segments s ON ...
GROUP BY c.id HAVING segment_count <= 3;
```

### Files to Investigate
- `lib/infra/epub_parser.dart` - HTML stripping
- `packages/core_domain/lib/src/utils/text_segmenter.dart` - Import-time segmentation
- `packages/core_domain/lib/src/utils/segment_type_detector.dart` - Runtime detection
