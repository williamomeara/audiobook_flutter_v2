// Unit tests for PDF text processing utilities
// These test the PDF-specific text cleaning functions that don't require pdfrx

import 'package:flutter_test/flutter_test.dart';

// We import the functions to test - but since _cleanPdfText is private,
// we'll test via public methods or create a test helper.

// For now, let's test the text cleaning logic directly by duplicating it here
// (in a real scenario, we'd either make the function package-private or
// create a testable wrapper)

void main() {
  group('PDF Text Cleaning', () {
    group('Page Number Removal', () {
      test('removes standalone page numbers at start of line', () {
        expect(
          cleanPdfText('42\nThe quick brown fox'),
          'The quick brown fox',
        );
      });

      test('removes page numbers with surrounding whitespace', () {
        expect(
          cleanPdfText('   123  \nSome content'),
          'Some content',
        );
      });

      test('preserves numbers that are part of text', () {
        expect(
          cleanPdfText('Chapter 42\nContent here'),
          'Chapter 42\nContent here',
        );
      });

      test('removes page numbers in middle of text', () {
        expect(
          cleanPdfText('End of page.\n\n42\n\nStart of next page.'),
          'End of page.\n\nStart of next page.',
        );
      });

      test('handles multiple page numbers', () {
        final input = '''First paragraph.

42

Second paragraph.

43

Third paragraph.''';
        final expected = '''First paragraph.

Second paragraph.

Third paragraph.''';
        expect(cleanPdfText(input), expected);
      });
    });

    group('Hyphenated Word Rejoining', () {
      test('rejoins simple hyphenated word across lines', () {
        expect(
          cleanPdfText('The quick brown fox jumped over the la-\nzy dog.'),
          'The quick brown fox jumped over the lazy dog.',
        );
      });

      test('handles multiple hyphenated words', () {
        expect(
          cleanPdfText('pro-\ngramming and soft-\nware'),
          'programming and software',
        );
      });

      test('preserves intentional hyphens', () {
        expect(
          cleanPdfText('self-aware robots'),
          'self-aware robots',
        );
      });

      test('preserves hyphens not followed by lowercase letter', () {
        expect(
          cleanPdfText('The end-\n\nChapter 2'),
          'The end-\n\nChapter 2',
        );
      });

      test('handles hyphen at end of word before newline with lowercase continuation', () {
        final input = 'The implementa-\ntion of the algo-\nrithm was complex.';
        final expected = 'The implementation of the algorithm was complex.';
        expect(cleanPdfText(input), expected);
      });
    });

    group('Form Feed Removal', () {
      test('removes form feed characters', () {
        expect(
          cleanPdfText('Page one content.\fPage two content.'),
          'Page one content.\nPage two content.',
        );
      });

      test('handles multiple form feeds', () {
        expect(
          cleanPdfText('A\fB\fC'),
          'A\nB\nC',
        );
      });
    });

    group('Copyright Footer Removal', () {
      test('removes standard copyright lines', () {
        expect(
          cleanPdfText('Content here.\nCopyright © 2024 Author Name'),
          'Content here.',
        );
      });

      test('removes copyright with date range', () {
        expect(
          cleanPdfText('Some text.\nCopyright 2020-2024 Publisher'),
          'Some text.',
        );
      });

      test('removes © symbol only copyright', () {
        expect(
          cleanPdfText('Main content.\n© 2024 Some Company Inc.'),
          'Main content.',
        );
      });

      test('preserves copyright in main content', () {
        // Copyright mentioned as part of narrative should be kept
        final input = 'He held the copyright to the design.\nMore text here.';
        expect(cleanPdfText(input), input);
      });
    });

    group('Whitespace Normalization', () {
      test('collapses multiple blank lines', () {
        expect(
          cleanPdfText('Paragraph one.\n\n\n\n\nParagraph two.'),
          'Paragraph one.\n\nParagraph two.',
        );
      });

      test('collapses multiple spaces', () {
        expect(
          cleanPdfText('Too    many     spaces'),
          'Too many spaces',
        );
      });

      test('trims leading and trailing whitespace', () {
        expect(
          cleanPdfText('   Content here   '),
          'Content here',
        );
      });
    });

    group('Publishing System Artifacts', () {
      test('removes QXP timestamp artifacts', () {
        expect(
          cleanPdfText('Chapter content here. chapters 1-4.qxp 9/16/2010 3:09 PM Page 10'),
          'Chapter content here.',
        );
      });

      test('removes InDesign timestamp artifacts', () {
        expect(
          cleanPdfText('More content here. book-layout.indd 12/25/2023 10:30 AM Page 42'),
          'More content here.',
        );
      });

      test('removes standalone Page N at end of line', () {
        expect(
          cleanPdfText('End of this chapter Page 123\nNext paragraph'),
          'End of this chapter\nNext paragraph',
        );
      });

      test('handles combined artifacts', () {
        final input = '''Some good content here.
chapters 1-4.qxp 9/16/2010 3:09 PM Page 10

More content follows. Page 11''';
        final expected = '''Some good content here.

More content follows.''';
        expect(cleanPdfText(input), expected);
      });
    });

    group('Combined Processing', () {
      test('handles typical PDF page text', () {
        final input = '''
42

The implementa-
tion of this algo-
rithm requires careful considera-
tion of edge cases.

43

More content follows here.

Copyright © 2024 Publisher
''';
        final expected = '''The implementation of this algorithm requires careful consideration of edge cases.

More content follows here.''';
        expect(cleanPdfText(input), expected);
      });

      test('handles clean text without issues', () {
        final input = 'This is clean text.\n\nWith proper formatting.';
        expect(cleanPdfText(input), input);
      });
    });
  });

  group('Chapter Title Extraction', () {
    test('extracts title from filename with author in parentheses', () {
      expect(
        extractTitleFromPath('SQL Antipatterns (Bill Karwin).pdf'),
        'SQL Antipatterns',
      );
    });

    test('extracts title from simple filename', () {
      expect(
        extractTitleFromPath('Basic Economics.pdf'),
        'Basic Economics',
      );
    });

    test('handles filename with brackets', () {
      expect(
        extractTitleFromPath('Book Title [Publisher Edition].pdf'),
        'Book Title',
      );
    });

    test('handles filename with trailing dash', () {
      expect(
        extractTitleFromPath('Book Title - .pdf'),
        'Book Title',
      );
    });

    test('handles path with directory separators', () {
      expect(
        extractTitleFromPath('/path/to/books/My Book.pdf'),
        'My Book',
      );
    });
  });
}

/// PDF-specific text cleaning function (replicated for testing)
/// In production, this is in pdf_parser.dart as _cleanPdfText
String cleanPdfText(String text) {
  var result = text;

  // 1. Remove standalone page numbers (number alone on a line)
  result = result.replaceAll(RegExp(r'^\s*\d+\s*$', multiLine: true), '');

  // 2. Remove publishing system artifacts (QXP, InDesign, etc.)
  result = result.replaceAll(
    RegExp(
      r'[a-zA-Z0-9_\-\s]+\.(?:qxp|indd|qxd)\s+\d{1,2}/\d{1,2}/\d{2,4}\s+\d{1,2}:\d{2}\s*[AP]M\s+Page\s+\d+',
      caseSensitive: false,
    ),
    '',
  );

  // 3. Remove standalone "Page N" patterns at end of lines
  result = result.replaceAll(
    RegExp(r'\s+Page\s+\d+\s*$', multiLine: true),
    '',
  );

  // 4. Rejoin hyphenated words across line breaks
  result = result.replaceAllMapped(
    RegExp(r'(\w)-\n\s*([a-z])'),
    (m) => '${m[1]}${m[2]}',
  );

  // 5. Replace form feed with newline
  result = result.replaceAll('\f', '\n');

  // 6. Remove common PDF footer patterns (copyright lines at end)
  result = result.replaceAll(
    RegExp(r'\n(?:Copyright|©).*$', multiLine: true, caseSensitive: false),
    '',
  );

  // 7. Collapse excessive whitespace
  result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  result = result.replaceAll(RegExp(r' {2,}'), ' ');

  return result.trim();
}

/// Extract title from file path (replicated for testing)
/// In production, this is in pdf_parser.dart as _extractTitleFromPath
String extractTitleFromPath(String path) {
  // Get just the filename, handling both Unix and Windows paths
  final filename = path.split('/').last.split('\\').last;
  // Remove extension
  final nameWithoutExt = filename.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
  // Clean up common patterns like "(Author Name)" at the end
  final cleaned = nameWithoutExt
      .replaceAll(RegExp(r'\s*\([^)]+\)\s*$'), '') // Remove (Author) suffix
      .replaceAll(RegExp(r'\s*\[[^\]]+\]\s*$'), '') // Remove [Publisher] suffix
      .replaceAll(RegExp(r'\s*-\s*$'), '') // Remove trailing dash
      .trim();
  return cleaned.isNotEmpty ? cleaned : nameWithoutExt;
}
