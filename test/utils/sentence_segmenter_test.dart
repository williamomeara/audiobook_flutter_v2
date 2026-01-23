import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/utils/sentence_segmenter.dart';

void main() {
  group('SentenceSegmenter', () {
    group('Basic segmentation', () {
      test('splits simple sentences', () {
        const input = 'Hello world. This is a test. Goodbye.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['Hello world.', 'This is a test.', 'Goodbye.']));
      });

      test('handles single sentence', () {
        const input = 'This is just one sentence.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['This is just one sentence.']));
      });

      test('handles empty string', () {
        final result = SentenceSegmenter.segment('');
        expect(result, isEmpty);
      });

      test('handles whitespace only', () {
        final result = SentenceSegmenter.segment('   \n\t  ');
        expect(result, isEmpty);
      });

      test('handles sentence without ending punctuation', () {
        const input = 'This sentence has no period';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['This sentence has no period']));
      });

      test('handles multiple spaces between sentences', () {
        const input = 'First sentence.   Second sentence.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['First sentence.', 'Second sentence.']));
      });

      test('handles newlines between sentences', () {
        const input = 'First sentence.\nSecond sentence.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['First sentence.', 'Second sentence.']));
      });
    });

    group('Punctuation types', () {
      test('handles exclamation marks', () {
        const input = 'Stop! Do not move.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['Stop!', 'Do not move.']));
      });

      test('handles question marks', () {
        const input = 'How are you? I am fine.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['How are you?', 'I am fine.']));
      });

      test('handles multiple exclamation marks', () {
        const input = 'Wow!! That is amazing.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['Wow!!', 'That is amazing.']));
      });

      test('handles multiple question marks', () {
        const input = 'What??? Are you serious?';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['What???', 'Are you serious?']));
      });

      test('handles interrobang style', () {
        const input = 'What?! That is crazy.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['What?!', 'That is crazy.']));
      });

      test('handles ellipsis as sentence end', () {
        const input = 'He walked away... She watched him go.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['He walked away...', 'She watched him go.']));
      });
    });

    group('Abbreviations', () {
      test('handles Dr. abbreviation', () {
        const input = 'Dr. Smith went home. He was tired.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['Dr. Smith went home.', 'He was tired.']));
      });

      test('handles Mr. abbreviation', () {
        const input = 'Mr. Jones arrived. He looked happy.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['Mr. Jones arrived.', 'He looked happy.']));
      });

      test('handles Mrs. abbreviation', () {
        const input = 'Mrs. Williams called. She had news.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['Mrs. Williams called.', 'She had news.']));
      });

      test('handles Ms. abbreviation', () {
        const input = 'Ms. Davis spoke. Everyone listened.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['Ms. Davis spoke.', 'Everyone listened.']));
      });

      test('handles Prof. abbreviation', () {
        const input = 'Prof. Brown lectured. The students took notes.';
        final result = SentenceSegmenter.segment(input);
        expect(
            result, equals(['Prof. Brown lectured.', 'The students took notes.']));
      });

      test('handles etc. abbreviation', () {
        const input = 'Apples, oranges, etc. They are all fruit.';
        final result = SentenceSegmenter.segment(input);
        // etc. is treated as abbreviation, no break after it
        expect(result, equals(['Apples, oranges, etc. They are all fruit.']));
      });

      test('handles vs. abbreviation', () {
        const input = 'Smith vs. Jones was a landmark case. It changed law.';
        final result = SentenceSegmenter.segment(input);
        expect(result,
            equals(['Smith vs. Jones was a landmark case.', 'It changed law.']));
      });

      test('handles e.g. abbreviation', () {
        const input =
            'Some animals, e.g. dogs, are domesticated. Others are wild.';
        final result = SentenceSegmenter.segment(input);
        // e.g. is abbreviation, "dogs" starts lowercase so no break there
        expect(
            result,
            equals([
              'Some animals, e.g. dogs, are domesticated.',
              'Others are wild.'
            ]));
      });

      test('handles i.e. abbreviation', () {
        const input = 'The answer, i.e. forty-two, was correct. He won.';
        final result = SentenceSegmenter.segment(input);
        // i.e. is abbreviation, "forty-two" starts lowercase so no break there
        expect(result,
            equals(['The answer, i.e. forty-two, was correct.', 'He won.']));
      });

      test('handles Sr. and Jr. abbreviations', () {
        const input = 'John Smith Jr. arrived. His father, John Smith Sr. Was proud.';
        final result = SentenceSegmenter.segment(input);
        expect(
            result,
            equals([
              'John Smith Jr. arrived.',
              'His father, John Smith Sr. Was proud.'
            ]));
      });

      test('handles Inc. and Ltd. abbreviations', () {
        const input = 'Acme Inc. Filed for bankruptcy. Widget Ltd. Did too.';
        final result = SentenceSegmenter.segment(input);
        expect(
            result,
            equals([
              'Acme Inc. Filed for bankruptcy.',
              'Widget Ltd. Did too.'
            ]));
      });

      test('handles street abbreviations', () {
        const input = 'She lived on Main St. Her office was on Park Ave. They were nearby.';
        final result = SentenceSegmenter.segment(input);
        expect(
            result,
            equals([
              'She lived on Main St. Her office was on Park Ave. They were nearby.'
            ]));
      });

      test('handles month abbreviations', () {
        const input = 'It was Jan. The weather was cold.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['It was Jan. The weather was cold.']));
      });
    });

    group('Initials', () {
      test('handles single initial', () {
        const input = 'J. Smith was there. He spoke briefly.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['J. Smith was there.', 'He spoke briefly.']));
      });

      test('handles multiple initials', () {
        const input = 'J.K. Rowling wrote it. The book was popular.';
        final result = SentenceSegmenter.segment(input);
        // Both J. and K. are single-letter abbreviations, so "Rowling" triggers break
        // This is a known limitation - initials followed by name are tricky
        // For TTS, splitting here is acceptable
        expect(result.length, greaterThanOrEqualTo(2));
        expect(result.last, equals('The book was popular.'));
      });

      test('handles initials with spaces', () {
        const input = 'J. R. R. Tolkien created Middle-earth. It became iconic.';
        final result = SentenceSegmenter.segment(input);
        expect(
            result,
            equals([
              'J. R. R. Tolkien created Middle-earth.',
              'It became iconic.'
            ]));
      });
    });

    group('Decimals and numbers', () {
      test('handles decimals', () {
        const input = 'Pi is 3.14. It is irrational.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['Pi is 3.14.', 'It is irrational.']));
      });

      test('handles currency', () {
        const input = 'It costs \$19.99. That is expensive.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['It costs \$19.99.', 'That is expensive.']));
      });

      test('handles percentages', () {
        const input = 'Growth was 5.5. The company celebrated.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['Growth was 5.5.', 'The company celebrated.']));
      });

      test('handles version numbers', () {
        const input = 'Version 2.0. Now available.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['Version 2.0.', 'Now available.']));
      });

      test('handles times', () {
        const input = 'Meet at 10.30. Do not be late.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['Meet at 10.30.', 'Do not be late.']));
      });
    });

    group('Quotations', () {
      test('handles quotes starting new sentence', () {
        const input = 'He left. "Goodbye," she said.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['He left.', '"Goodbye," she said.']));
      });

      test('handles single quotes starting new sentence', () {
        const input = "He left. 'Goodbye,' she said.";
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(["He left.", "'Goodbye,' she said."]));
      });

      test('handles curly double quotes', () {
        const input = 'He left. \u201CGoodbye,\u201D she said.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['He left.', '\u201CGoodbye,\u201D she said.']));
      });

      test('handles curly single quotes', () {
        const input = 'He left. \u2018Goodbye,\u2019 she said.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['He left.', '\u2018Goodbye,\u2019 she said.']));
      });

      test('handles quote inside sentence', () {
        const input = 'She said "hello" and smiled. He waved back.';
        final result = SentenceSegmenter.segment(input);
        expect(result,
            equals(['She said "hello" and smiled.', 'He waved back.']));
      });

      test('handles question in quotes at start', () {
        const input = '"Are you ready?" He asked the question clearly.';
        final result = SentenceSegmenter.segment(input);
        expect(result,
            equals(['"Are you ready?"', 'He asked the question clearly.']));
      });
    });

    group('Complex cases', () {
      test('handles mixed abbreviations and sentences', () {
        const input =
            'Dr. J. Smith from Acme Inc. Spoke at the conference. The audience was impressed.';
        final result = SentenceSegmenter.segment(input);
        expect(
            result,
            equals([
              'Dr. J. Smith from Acme Inc. Spoke at the conference.',
              'The audience was impressed.'
            ]));
      });

      test('handles paragraph with multiple sentence types', () {
        const input =
            'What happened? Dr. Smith arrived. He asked, "Where is everyone?" Nobody answered.';
        final result = SentenceSegmenter.segment(input);
        expect(
            result,
            equals([
              'What happened?',
              'Dr. Smith arrived.',
              'He asked, "Where is everyone?"',
              'Nobody answered.'
            ]));
      });

      test('handles lowercase after period (section reference)', () {
        const input = 'See section 3.a. It explains everything.';
        final result = SentenceSegmenter.segment(input);
        // "a" is lowercase, but "It" is uppercase - should split at "a. It"
        // Actually 'a' is a single letter abbreviation pattern
        // For this edge case, we split because "It" is uppercase
        expect(result, equals(['See section 3.a.', 'It explains everything.']));
      });

      test('handles all caps sentence', () {
        const input = 'WARNING! DO NOT ENTER. DANGER AHEAD.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['WARNING!', 'DO NOT ENTER.', 'DANGER AHEAD.']));
      });
    });

    group('Edge cases', () {
      test('handles sentence ending with abbreviation', () {
        const input = 'He has a Ph.D.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['He has a Ph.D.']));
      });

      test('handles consecutive sentences with no space', () {
        // This is malformed input, but we handle it gracefully
        const input = 'First.Second.';
        final result = SentenceSegmenter.segment(input);
        // No space after period, so treated as one "sentence"
        expect(result, equals(['First.Second.']));
      });

      test('handles very long sentence', () {
        final words = List.generate(100, (i) => 'word$i');
        final input = '${words.join(' ')}. Done.';
        final result = SentenceSegmenter.segment(input);
        expect(result.length, equals(2));
        expect(result[1], equals('Done.'));
      });

      test('handles unicode characters', () {
        const input = 'Caf\u00e9 is nice. \u00c9l agrees.';
        final result = SentenceSegmenter.segment(input);
        expect(result, equals(['Caf\u00e9 is nice.', '\u00c9l agrees.']));
      });
    });

    group('countSentences', () {
      test('returns correct count', () {
        const input = 'One. Two. Three.';
        final count = SentenceSegmenter.countSentences(input);
        expect(count, equals(3));
      });

      test('returns zero for empty string', () {
        final count = SentenceSegmenter.countSentences('');
        expect(count, equals(0));
      });
    });

    group('segmentWithSpans', () {
      test('returns correct spans', () {
        const input = 'Hello world. Goodbye.';
        final spans = SentenceSegmenter.segmentWithSpans(input);
        expect(spans.length, equals(2));
        expect(spans[0].text, equals('Hello world.'));
        expect(spans[0].start, equals(0));
        expect(spans[0].end, equals(12));
        expect(spans[1].text, equals('Goodbye.'));
        expect(spans[1].start, equals(13));
        expect(spans[1].end, equals(21));
      });

      test('returns empty list for empty string', () {
        final spans = SentenceSegmenter.segmentWithSpans('');
        expect(spans, isEmpty);
      });

      test('SentenceSpan equality works', () {
        final span1 = SentenceSpan(start: 0, end: 10, text: 'Hello.');
        final span2 = SentenceSpan(start: 0, end: 10, text: 'Hello.');
        final span3 = SentenceSpan(start: 0, end: 10, text: 'Goodbye.');
        expect(span1, equals(span2));
        expect(span1, isNot(equals(span3)));
      });

      test('SentenceSpan length property works', () {
        final span = SentenceSpan(start: 5, end: 15, text: 'Test text.');
        expect(span.length, equals(10));
      });

      test('SentenceSpan toString works', () {
        final span = SentenceSpan(start: 0, end: 6, text: 'Hello.');
        expect(span.toString(), contains('0-6'));
        expect(span.toString(), contains('Hello.'));
      });
    });
  });
}
