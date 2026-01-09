import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/utils/text_normalizer.dart';

void main() {
  group('TextNormalizer', () {
    group('normalize (full pipeline)', () {
      test('normalizes text with multiple issues', () {
        // Using Unicode escapes: " (201C) " (201D) ' (2019) — (2014) ﬁ (FB01) … (2026)
        const input = '\u201CHello,\u201D she said\u2014\u201Cit\u2019s a \uFB01ne day\u2026\u201D';
        final result = TextNormalizer.normalize(input);
        expect(result, equals('"Hello," she said - "it\'s a fine day..."'));
      });

      test('handles empty string', () {
        expect(TextNormalizer.normalize(''), equals(''));
      });

      test('returns unchanged ASCII text', () {
        const input = 'Hello world. This is plain ASCII text.';
        expect(TextNormalizer.normalize(input), equals(input));
      });
    });

    group('normalizeQuotes', () {
      test('normalizes left single quote', () {
        expect(TextNormalizer.normalizeQuotes('\u2018hello'), equals("'hello"));
      });

      test('normalizes right single quote (curly apostrophe)', () {
        expect(TextNormalizer.normalizeQuotes("it\u2019s"), equals("it's"));
      });

      test('normalizes single low-9 quote', () {
        expect(TextNormalizer.normalizeQuotes('\u201Ahello'), equals("'hello"));
      });

      test('normalizes reversed single quote', () {
        expect(TextNormalizer.normalizeQuotes('\u201Bhello'), equals("'hello"));
      });

      test('normalizes left double quote', () {
        expect(TextNormalizer.normalizeQuotes('\u201Chello'), equals('"hello'));
      });

      test('normalizes right double quote', () {
        expect(TextNormalizer.normalizeQuotes('hello\u201D'), equals('hello"'));
      });

      test('normalizes double low-9 quote', () {
        expect(TextNormalizer.normalizeQuotes('\u201Ehello'), equals('"hello'));
      });

      test('normalizes reversed double quote', () {
        expect(TextNormalizer.normalizeQuotes('\u201Fhello'), equals('"hello'));
      });

      test('normalizes left guillemet', () {
        expect(TextNormalizer.normalizeQuotes('\u00ABbonjour'), equals('"bonjour'));
      });

      test('normalizes right guillemet', () {
        expect(TextNormalizer.normalizeQuotes('bonjour\u00BB'), equals('bonjour"'));
      });

      test('normalizes backtick', () {
        expect(TextNormalizer.normalizeQuotes('\u0060hello'), equals("'hello"));
      });

      test('normalizes acute accent', () {
        expect(TextNormalizer.normalizeQuotes('\u00B4hello'), equals("'hello"));
      });

      test('handles mixed quotes in sentence', () {
        const input = '\u201CHe said \u2018hello\u2019\u201D';
        expect(TextNormalizer.normalizeQuotes(input), equals('"He said \'hello\'"'));
      });
    });

    group('normalizeDashes', () {
      test('normalizes em-dash with spaces', () {
        expect(TextNormalizer.normalizeDashes('word\u2014word'),
            equals('word - word'));
      });

      test('normalizes en-dash to hyphen', () {
        expect(TextNormalizer.normalizeDashes('pages 1\u20135'),
            equals('pages 1-5'));
      });

      test('normalizes Unicode hyphen', () {
        expect(TextNormalizer.normalizeDashes('self\u2010aware'),
            equals('self-aware'));
      });

      test('normalizes non-breaking hyphen', () {
        expect(TextNormalizer.normalizeDashes('self\u2011aware'),
            equals('self-aware'));
      });

      test('normalizes minus sign', () {
        expect(TextNormalizer.normalizeDashes('5 \u2212 3 = 2'),
            equals('5 - 3 = 2'));
      });

      test('handles multiple dashes in sentence', () {
        const input = 'She\u2014the woman\u2014was there';
        expect(TextNormalizer.normalizeDashes(input),
            equals('She - the woman - was there'));
      });
    });

    group('normalizeEllipsis', () {
      test('expands Unicode ellipsis', () {
        expect(TextNormalizer.normalizeEllipsis('wait\u2026'),
            equals('wait...'));
      });

      test('handles multiple ellipses', () {
        expect(TextNormalizer.normalizeEllipsis('wait\u2026 what\u2026'),
            equals('wait... what...'));
      });

      test('preserves ASCII ellipsis', () {
        expect(TextNormalizer.normalizeEllipsis('wait...'), equals('wait...'));
      });
    });

    group('normalizeLigatures', () {
      test('expands fi ligature', () {
        expect(TextNormalizer.normalizeLigatures('\uFB01nd'), equals('find'));
      });

      test('expands fl ligature', () {
        expect(TextNormalizer.normalizeLigatures('\uFB02ow'), equals('flow'));
      });

      test('expands ff ligature', () {
        expect(TextNormalizer.normalizeLigatures('o\uFB00ice'),
            equals('office'));
      });

      test('expands ffi ligature', () {
        expect(TextNormalizer.normalizeLigatures('o\uFB03ce'),
            equals('office'));
      });

      test('expands ffl ligature', () {
        expect(TextNormalizer.normalizeLigatures('mu\uFB04e'),
            equals('muffle'));
      });

      test('expands st ligature (FB05)', () {
        expect(TextNormalizer.normalizeLigatures('fa\uFB05'),
            equals('fast'));
      });

      test('expands st ligature (FB06)', () {
        expect(TextNormalizer.normalizeLigatures('la\uFB06'),
            equals('last'));
      });

      test('expands uppercase OE ligature', () {
        expect(TextNormalizer.normalizeLigatures('\u0152dipus'),
            equals('OEdipus'));
      });

      test('expands lowercase oe ligature', () {
        expect(TextNormalizer.normalizeLigatures('hors d\'\u0153uvre'),
            equals('hors d\'oeuvre'));
      });

      test('expands uppercase AE ligature', () {
        expect(TextNormalizer.normalizeLigatures('\u00C6gean'),
            equals('AEgean'));
      });

      test('expands lowercase ae ligature', () {
        expect(TextNormalizer.normalizeLigatures('encyclop\u00E6dia'),
            equals('encyclopaedia'));
      });
    });

    group('normalizeSpaces', () {
      test('removes zero-width space', () {
        expect(TextNormalizer.normalizeSpaces('hel\u200Blo'),
            equals('hello'));
      });

      test('removes zero-width non-joiner', () {
        expect(TextNormalizer.normalizeSpaces('hel\u200Clo'),
            equals('hello'));
      });

      test('removes zero-width joiner', () {
        expect(TextNormalizer.normalizeSpaces('hel\u200Dlo'),
            equals('hello'));
      });

      test('removes BOM character', () {
        expect(TextNormalizer.normalizeSpaces('\uFEFFhello'),
            equals('hello'));
      });

      test('normalizes non-breaking space', () {
        expect(TextNormalizer.normalizeSpaces('hello\u00A0world'),
            equals('hello world'));
      });

      test('normalizes narrow no-break space', () {
        expect(TextNormalizer.normalizeSpaces('hello\u202Fworld'),
            equals('hello world'));
      });

      test('normalizes thin space', () {
        expect(TextNormalizer.normalizeSpaces('hello\u2009world'),
            equals('hello world'));
      });

      test('normalizes hair space', () {
        expect(TextNormalizer.normalizeSpaces('hello\u200Aworld'),
            equals('hello world'));
      });

      test('normalizes en space', () {
        expect(TextNormalizer.normalizeSpaces('hello\u2002world'),
            equals('hello world'));
      });

      test('normalizes em space', () {
        expect(TextNormalizer.normalizeSpaces('hello\u2003world'),
            equals('hello world'));
      });

      test('normalizes figure space', () {
        expect(TextNormalizer.normalizeSpaces('hello\u2007world'),
            equals('hello world'));
      });
    });

    group('normalizeSymbols', () {
      test('converts one-half fraction', () {
        expect(TextNormalizer.normalizeSymbols('1\u00BD cups'),
            equals('11/2 cups'));
      });

      test('converts one-quarter fraction', () {
        expect(TextNormalizer.normalizeSymbols('\u00BC cup'),
            equals('1/4 cup'));
      });

      test('converts three-quarters fraction', () {
        expect(TextNormalizer.normalizeSymbols('\u00BE full'),
            equals('3/4 full'));
      });

      test('converts one-third fraction', () {
        expect(TextNormalizer.normalizeSymbols('\u2153 of'),
            equals('1/3 of'));
      });

      test('converts two-thirds fraction', () {
        expect(TextNormalizer.normalizeSymbols('\u2154 done'),
            equals('2/3 done'));
      });

      test('converts copyright symbol', () {
        expect(TextNormalizer.normalizeSymbols('\u00A9 2024'),
            equals('(c) 2024'));
      });

      test('converts registered symbol', () {
        expect(TextNormalizer.normalizeSymbols('Brand\u00AE'),
            equals('Brand(R)'));
      });

      test('converts trademark symbol', () {
        expect(TextNormalizer.normalizeSymbols('TradeMark\u2122'),
            equals('TradeMark(TM)'));
      });

      test('converts numero sign', () {
        expect(TextNormalizer.normalizeSymbols('\u21165'),
            equals('No.5'));
      });

      test('converts bullet point', () {
        expect(TextNormalizer.normalizeSymbols('\u2022 item'),
            equals('* item'));
      });

      test('converts triangular bullet', () {
        expect(TextNormalizer.normalizeSymbols('\u2023 item'),
            equals('* item'));
      });

      test('converts hyphen bullet', () {
        expect(TextNormalizer.normalizeSymbols('\u2043 item'),
            equals('- item'));
      });

      test('converts middle dot', () {
        expect(TextNormalizer.normalizeSymbols('word\u00B7word'),
            equals('word.word'));
      });
    });

    group('cleanWhitespace', () {
      test('collapses multiple spaces', () {
        expect(TextNormalizer.cleanWhitespace('hello    world'),
            equals('hello world'));
      });

      test('preserves single space', () {
        expect(TextNormalizer.cleanWhitespace('hello world'),
            equals('hello world'));
      });

      test('preserves paragraph breaks (double newline)', () {
        expect(TextNormalizer.cleanWhitespace('para1\n\npara2'),
            equals('para1\n\npara2'));
      });

      test('collapses 3+ newlines to double', () {
        expect(TextNormalizer.cleanWhitespace('para1\n\n\npara2'),
            equals('para1\n\npara2'));
      });

      test('collapses many newlines to double', () {
        expect(TextNormalizer.cleanWhitespace('para1\n\n\n\n\npara2'),
            equals('para1\n\npara2'));
      });

      test('trims leading whitespace', () {
        expect(TextNormalizer.cleanWhitespace('   hello'),
            equals('hello'));
      });

      test('trims trailing whitespace', () {
        expect(TextNormalizer.cleanWhitespace('hello   '),
            equals('hello'));
      });

      test('handles mixed whitespace issues', () {
        expect(TextNormalizer.cleanWhitespace('  hello    world\n\n\n\ngoodbye  '),
            equals('hello world\n\ngoodbye'));
      });
    });

    group('real-world examples', () {
      test('normalizes typical ebook text', () {
        const input =
            '\u201CIt\u2019s a ﬁne day,\u201D she said\u2014\u201Cperhaps the ﬁnest.\u201D';
        final result = TextNormalizer.normalize(input);
        expect(result, equals('"It\'s a fine day," she said - "perhaps the finest."'));
      });

      test('normalizes Project Gutenberg style text', () {
        const input =
            'The Project Gutenberg EBook\u2026 \u00A9 2021';
        final result = TextNormalizer.normalize(input);
        expect(result, equals('The Project Gutenberg EBook... (c) 2021'));
      });

      test('handles French text with guillemets', () {
        const input = '\u00ABBonjour\u00BB, dit-il.';
        final result = TextNormalizer.normalize(input);
        expect(result, equals('"Bonjour", dit-il.'));
      });

      test('handles text with ligatures throughout', () {
        const input = 'The o\uFB03ce was half-\uFB01lled with \uFB02owers.';
        final result = TextNormalizer.normalize(input);
        expect(result, equals('The office was half-filled with flowers.'));
      });
    });
  });
}
