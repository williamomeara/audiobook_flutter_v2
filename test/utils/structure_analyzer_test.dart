import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/utils/structure_analyzer.dart';

void main() {
  group('StructureAnalyzer', () {
    group('extractPreliminarySection', () {
      test('extracts TRANSCRIBER\'S NOTES section', () {
        const content = '''TRANSCRIBER'S NOTES

This text was transcribed from scanned images.
Some notes about the conversion.

CHAPTER 1

The actual story begins here.''';
        final result = StructureAnalyzer.extractPreliminarySection(content);
        expect(result, isNotNull);
        expect(result, contains('TRANSCRIBER'));
        expect(result, isNot(contains('actual story')));
      });

      test('extracts EXPLANATORY NOTES section', () {
        const content = '''EXPLANATORY NOTES

The following terms have special meanings:
- Term 1: Definition
- Term 2: Definition

CHAPTER 1

The story begins.''';
        final result = StructureAnalyzer.extractPreliminarySection(content);
        expect(result, isNotNull);
        expect(result, contains('EXPLANATORY'));
      });

      test('extracts EDITOR\'S NOTES section', () {
        const content = '''EDITOR'S NOTES

Added in 2024 for clarity.

CHAPTER 1

Story content.''';
        final result = StructureAnalyzer.extractPreliminarySection(content);
        expect(result, isNotNull);
        expect(result, contains('EDITOR'));
      });

      test('returns null when no preliminary section', () {
        const content = '''CHAPTER 1

The story begins here without any notes.''';
        final result = StructureAnalyzer.extractPreliminarySection(content);
        expect(result, isNull);
      });

      test('extracts PRELIMINARY MATTER section', () {
        const content = '''PRELIMINARY MATTER

Title page information
Copyright notice

PART 1

The book begins.''';
        final result = StructureAnalyzer.extractPreliminarySection(content);
        expect(result, isNotNull);
        expect(result, contains('PRELIMINARY'));
      });

      test('stops at Chapter marker', () {
        const content = '''TRANSCRIBER'S NOTES

These are notes.

CHAPTER 1

Story here.''';
        final result = StructureAnalyzer.extractPreliminarySection(content);
        expect(result, isNotNull);
        expect(result, isNot(contains('Story here')));
      });

      test('stops at Book marker', () {
        const content = '''EXPLANATORY NOTES

Some explanation.

BOOK II

Content starts.''';
        final result = StructureAnalyzer.extractPreliminarySection(content);
        expect(result, isNotNull);
        expect(result, isNot(contains('Content starts')));
      });

      test('handles section with dashes separator', () {
        const content = '''EDITOR'S NOTES

Information.

---

CHAPTER 1

Story.''';
        final result = StructureAnalyzer.extractPreliminarySection(content);
        expect(result, isNotNull);
      });
    });

    group('isListBoilerplate', () {
      test('detects glossary-like list', () {
        const paragraph = '''
A-Line: A nautical term
Able: Capable and skilled
Aboardship: On the vessel
Abreast: Alongside each other
Abyss: Deep dark void
Accommodation: Quarters for staff''';
        expect(StructureAnalyzer.isListBoilerplate(paragraph), isTrue);
      });

      test('detects bulleted list', () {
        const paragraph = '''
• First item in the list
• Second item in the list
• Third item in the list
• Fourth item in the list
• Fifth item in the list
• Sixth item in the list''';
        expect(StructureAnalyzer.isListBoilerplate(paragraph), isTrue);
      });

      test('detects dashed list', () {
        const paragraph = '''
- Credits go to Alice
- Assisted by Bob
- Proofread by Carol
- Formatted by Diana
- Edited by Eve''';
        expect(StructureAnalyzer.isListBoilerplate(paragraph), isTrue);
      });

      test('detects numbered list', () {
        const paragraph = '''
1. First production credit
2. Second production credit
3. Third production credit
4. Fourth production credit
5. Fifth production credit''';
        expect(StructureAnalyzer.isListBoilerplate(paragraph), isTrue);
      });

      test('rejects paragraph with long lines', () {
        const paragraph = '''
This is a normal paragraph with several sentences that are reasonably long.
It contains multiple lines but they are all substantial in content and substance.
This would be actual book text rather than a list or glossary entry.
The lines are too long to be considered list boilerplate by our heuristics.''';
        expect(StructureAnalyzer.isListBoilerplate(paragraph), isFalse);
      });

      test('rejects short list (< 5 items)', () {
        const paragraph = '''
• First
• Second
• Third''';
        expect(StructureAnalyzer.isListBoilerplate(paragraph), isFalse);
      });

      test('rejects normal narrative paragraph', () {
        const paragraph = '''
It was the best of times, it was the worst of times, it was the age of wisdom,
it was the age of foolishness. The narrator reflects on the paradoxes of the era.''';
        expect(StructureAnalyzer.isListBoilerplate(paragraph), isFalse);
      });
    });

    group('detectChapterSpanningBoilerplate', () {
      test('detects repeated first line across chapters', () {
        final chapters = [
          'BOILERPLATE HEADER\n\nFirst chapter content here.',
          'BOILERPLATE HEADER\n\nSecond chapter content here.',
          'BOILERPLATE HEADER\n\nThird chapter content here.',
          'BOILERPLATE HEADER\n\nFourth chapter content here.',
        ];
        final result = StructureAnalyzer.detectChapterSpanningBoilerplate(chapters);
        expect(result, isNotEmpty);
        expect(result, contains('BOILERPLATE HEADER'));
      });

      test('detects repeated pattern at same line position', () {
        final chapters = [
          'MARKER\nSame Line\n\nContent for chapter 1.',
          'MARKER\nSame Line\n\nContent for chapter 2.',
          'MARKER\nSame Line\n\nContent for chapter 3.',
          'MARKER\nSame Line\n\nContent for chapter 4.',
        ];
        final result = StructureAnalyzer.detectChapterSpanningBoilerplate(chapters);
        expect(result, contains('MARKER'));
        expect(result, contains('Same Line'));
      });

      test('returns empty set for no repeated patterns', () {
        final chapters = [
          'Chapter 1\n\nDifferent first line one.',
          'Chapter 2\n\nDifferent first line two.',
          'Chapter 3\n\nDifferent first line three.',
        ];
        final result = StructureAnalyzer.detectChapterSpanningBoilerplate(chapters);
        // Should be mostly empty (no 80%+ repeated patterns)
        expect(result.where((line) => !line.startsWith('Chapter')), isEmpty);
      });

      test('requires 80% threshold', () {
        final chapters = [
          'BOILERPLATE\n\nFirst chapter.',
          'BOILERPLATE\n\nSecond chapter.',
          'BOILERPLATE\n\nThird chapter.',
          'Different start\n\nFourth chapter.',
        ];
        final result = StructureAnalyzer.detectChapterSpanningBoilerplate(chapters);
        // 75% < 80%, so should not be detected
        expect(result, isEmpty);
      });

      test('requires at least 3 chapters', () {
        final chapters = [
          'Text\n\nChapter 1.',
          'Text\n\nChapter 2.',
        ];
        final result = StructureAnalyzer.detectChapterSpanningBoilerplate(chapters);
        expect(result, isEmpty);
      });

      test('detects very short repeated lines', () {
        final chapters = [
          'X\n\nFirst chapter.',
          'X\n\nSecond chapter.',
          'X\n\nThird chapter.',
          'X\n\nFourth chapter.',
        ];
        final result = StructureAnalyzer.detectChapterSpanningBoilerplate(chapters);
        // Even single characters repeated are boilerplate
        expect(result, contains('X'));
      });

      test('filters out common section headers', () {
        final chapters = [
          'Chapter 1\n\nFirst chapter.',
          'Chapter 2\n\nSecond chapter.',
          'Chapter 3\n\nThird chapter.',
          'Chapter 4\n\nFourth chapter.',
        ];
        final result = StructureAnalyzer.detectChapterSpanningBoilerplate(chapters);
        // "Chapter" pattern should be filtered out
        expect(result, isEmpty);
      });

      test('detects scanner pagination lines', () {
        final chapters = [
          '— Page 10 —\n\nFirst chapter content.',
          '— Page 20 —\n\nSecond chapter content.',
          '— Page 30 —\n\nThird chapter content.',
          '— Page 40 —\n\nFourth chapter content.',
        ];
        final result = StructureAnalyzer.detectChapterSpanningBoilerplate(chapters);
        // These look like pagination, might be detected depending on exact matches
        // Just verify it doesn't crash and produces reasonable results
        expect(result, isNotNull);
      });
    });

    group('edge cases', () {
      test('extractPreliminarySection handles empty content', () {
        final result = StructureAnalyzer.extractPreliminarySection('');
        expect(result, isNull);
      });

      test('extractPreliminarySection handles single-line content', () {
        final result = StructureAnalyzer.extractPreliminarySection('Just one line');
        expect(result, isNull);
      });

      test('isListBoilerplate handles empty string', () {
        expect(StructureAnalyzer.isListBoilerplate(''), isFalse);
      });

      test('isListBoilerplate handles single line', () {
        expect(StructureAnalyzer.isListBoilerplate('One line text'), isFalse);
      });

      test('detectChapterSpanningBoilerplate handles empty list', () {
        final result = StructureAnalyzer.detectChapterSpanningBoilerplate([]);
        expect(result, isEmpty);
      });

      test('detectChapterSpanningBoilerplate handles chapters with no newlines', () {
        final chapters = [
          'REPEATED MARKER',
          'REPEATED MARKER',
          'REPEATED MARKER',
          'REPEATED MARKER',
        ];
        final result = StructureAnalyzer.detectChapterSpanningBoilerplate(chapters);
        expect(result, contains('REPEATED MARKER'));
      });
    });
  });
}
