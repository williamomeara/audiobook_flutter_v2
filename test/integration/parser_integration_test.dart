/// Integration tests for the smart EPUB parser pipeline.
///
/// These tests validate the complete parsing pipeline:
/// - Text normalization (quotes, dashes, ligatures)
/// - Boilerplate removal (Project Gutenberg headers)
/// - Content classification (front/body/back matter)
/// - Sentence segmentation
///
/// Note: These tests require sample EPUB files in local_dev/dev_books/epub/
/// They are skipped if the files don't exist.
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/utils/text_normalizer.dart';
import 'package:audiobook_flutter_v2/utils/boilerplate_remover.dart';
import 'package:audiobook_flutter_v2/utils/content_classifier.dart';
import 'package:audiobook_flutter_v2/utils/sentence_segmenter.dart';

void main() {
  final booksDir = Directory('local_dev/dev_books/epub');
  final pgBooksDir = Directory('local_dev/dev_books/epub/project_gutenberg');

  group('EPUB Parser Integration', () {
    setUpAll(() {
      if (!booksDir.existsSync()) {
        fail('Test books directory not found: ${booksDir.path}');
      }
    });

    group('Text Normalization', () {
      test('normalizes smart quotes to ASCII', () {
        // Use double quotes for string to include curly single quotes
        const input = "\u201CHello,\u201D she said. \u2018It\u2019s nice.\u2019";
        final result = TextNormalizer.normalize(input);

        expect(result, contains('"'));
        expect(result, isNot(contains('\u201C'))); // Left double quote
        expect(result, isNot(contains('\u201D'))); // Right double quote
        expect(result, isNot(contains('\u2018'))); // Left single quote
        expect(result, isNot(contains('\u2019'))); // Right single quote
      });

      test('normalizes em-dashes with spaces', () {
        const input = 'word\u2014word'; // em-dash
        final result = TextNormalizer.normalize(input);

        // Em-dash replaced with space-hyphen-space for natural TTS pause
        expect(result, equals('word - word'));
      });

      test('normalizes ellipsis', () {
        const input = 'wait…';
        final result = TextNormalizer.normalize(input);

        expect(result, equals('wait...'));
      });

      test('removes ligatures', () {
        const input = 'ﬁnd and ﬂow';
        final result = TextNormalizer.normalize(input);

        expect(result, equals('find and flow'));
      });
    });

    group('Boilerplate Removal', () {
      test('detects Project Gutenberg start pattern', () {
        const content = '''
The Project Gutenberg eBook of Pride and Prejudice

This eBook is for the use of anyone anywhere in the United States.

Chapter 1

It is a truth universally acknowledged...
''';
        final cleaned = BoilerplateRemover.cleanChapter(content);

        expect(cleaned, isNot(contains('Project Gutenberg')));
        expect(cleaned, contains('Chapter 1'));
      });

      test('detects Project Gutenberg end pattern', () {
        // cleanChapter removes trailing boilerplate only if ALL trailing paragraphs
        // match boilerplate patterns. Mixed content is preserved.
        const content = '''
The End.

*** END OF THE PROJECT GUTENBERG EBOOK ***
''';
        final cleaned = BoilerplateRemover.cleanChapter(content);

        // Trailing boilerplate paragraph should be removed
        expect(cleaned, isNot(contains('PROJECT GUTENBERG')));
        expect(cleaned, contains('The End.'));
      });

      test('detects repeated prefix headers', () {
        final chapters = [
          'Book Title | Publisher\n\nChapter 1 content',
          'Book Title | Publisher\n\nChapter 2 content',
          'Book Title | Publisher\n\nChapter 3 content',
        ];

        final prefix = BoilerplateRemover.detectRepeatedPrefix(chapters);

        expect(prefix, isNotNull);
        expect(prefix, contains('Book Title'));
      });
    });

    group('Content Classification', () {
      test('classifies front matter correctly', () {
        // Cover
        expect(
            ContentClassifier.classify(
                filename: 'cover.xhtml', title: 'Cover', contentSnippet: ''),
            ContentType.frontMatter);
        // Table of Contents
        expect(
            ContentClassifier.classify(
                filename: 'toc.xhtml', title: 'Contents', contentSnippet: ''),
            ContentType.frontMatter);
        // Chapter (body matter)
        expect(
            ContentClassifier.classify(
                filename: 'ch01.xhtml', title: 'Chapter 1', contentSnippet: ''),
            ContentType.bodyMatter);
      });

      test('classifies back matter correctly', () {
        expect(
            ContentClassifier.classify(
                filename: 'notes.xhtml',
                title: 'Author\'s Note',
                contentSnippet: ''),
            ContentType.backMatter);
        expect(
            ContentClassifier.classify(
                filename: 'about.xhtml',
                title: 'About the Author',
                contentSnippet: ''),
            ContentType.backMatter);
        expect(
            ContentClassifier.classify(
                filename: 'ack.xhtml',
                title: 'Acknowledgments',
                contentSnippet: ''),
            ContentType.backMatter);
      });

      test('finds body matter range', () {
        final chapters = [
          ChapterInfo(
              filename: 'cover.xhtml', title: 'Cover', contentSnippet: ''),
          ChapterInfo(
              filename: 'ch01.xhtml', title: 'Chapter 1', contentSnippet: ''),
          ChapterInfo(
              filename: 'ch02.xhtml', title: 'Chapter 2', contentSnippet: ''),
          ChapterInfo(
              filename: 'about.xhtml',
              title: 'About the Author',
              contentSnippet: ''),
        ];

        final (startIndex, endIndex) =
            ContentClassifier.findBodyMatterRange(chapters);

        expect(startIndex, equals(1));
        expect(endIndex, equals(3)); // Exclusive end
      });
    });

    group('Sentence Segmentation', () {
      test('segments with abbreviations', () {
        const input = 'Dr. Smith arrived. He looked tired.';
        final sentences = SentenceSegmenter.segment(input);

        expect(sentences.length, equals(2));
        expect(sentences[0], equals('Dr. Smith arrived.'));
        expect(sentences[1], equals('He looked tired.'));
      });

      test('segments with quotations', () {
        const input = 'She said, "Hello." He waved back.';
        final sentences = SentenceSegmenter.segment(input);

        expect(sentences.length, equals(2));
      });

      test('handles ellipsis', () {
        const input = 'He paused... Then continued.';
        final sentences = SentenceSegmenter.segment(input);

        expect(sentences.length, equals(2));
      });
    });

    group('Pipeline Smoke Test', () {
      test('full pipeline processes text correctly', () {
        // Sample text with various issues - using curly quotes, ligatures, etc.
        // Using Unicode escapes for curly quotes to avoid string parsing issues
        final rawText = '''
The Project Gutenberg eBook of Test Book

Chapter 1

\u201CHello,\u201D said Mr. Smith. \u201CHow are you today?\u201D

She replied, \u201CI\u2019m \uFB01ne\u2014thank you for asking\u2026\u201D

The end.

*** END OF THE PROJECT GUTENBERG EBOOK ***
''';

        // Step 1: Remove boilerplate
        final cleaned = BoilerplateRemover.cleanChapter(rawText);
        expect(cleaned, isNot(contains('Project Gutenberg')));

        // Step 2: Normalize text
        final normalized = TextNormalizer.normalize(cleaned);
        expect(normalized, isNot(contains('\u201C'))); // Left curly double quote
        expect(normalized, isNot(contains('\u201D'))); // Right curly double quote
        expect(normalized, isNot(contains('\uFB01'))); // fi ligature
        expect(normalized, isNot(contains('\u2026'))); // ellipsis
        expect(normalized, isNot(contains('\u2014'))); // em-dash

        // Step 3: Segment sentences
        final sentences = SentenceSegmenter.segment(normalized);
        expect(sentences.length, greaterThan(1));

        // Verify Mr. abbreviation didn't cause false split
        expect(sentences[0], contains('Mr. Smith'));
      });
    });

    group('Real EPUB File Tests', () {
      test('Project Gutenberg books directory exists',
          skip: !pgBooksDir.existsSync() ? 'No PG books directory' : null, () {
        final pgBooks = pgBooksDir
            .listSync()
            .where((f) => f.path.endsWith('.epub'))
            .toList();

        expect(pgBooks, isNotEmpty,
            reason: 'Should have at least one Project Gutenberg EPUB');
      });

      test('Modern books directory exists',
          skip: !booksDir.existsSync() ? 'No books directory' : null, () {
        final modernBooks = booksDir
            .listSync()
            .where(
                (f) => f.path.endsWith('.epub') && f.path.contains('Z-Library'))
            .toList();

        expect(modernBooks, isNotEmpty,
            reason: 'Should have at least one Z-Library EPUB');
      });
    });
  });
}
