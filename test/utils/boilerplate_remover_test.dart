import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/utils/boilerplate_remover.dart';

void main() {
  group('BoilerplateRemover', () {
    group('removeFromBook', () {
      test('removes Project Gutenberg START marker and everything before', () {
        const input = '''
The Project Gutenberg EBook of Test, by Author

This is some header text
More header text

*** START OF THIS PROJECT GUTENBERG EBOOK TEST ***

Chapter 1

The story begins here.
''';
        final result = BoilerplateRemover.removeFromBook(input);
        expect(result, startsWith('Chapter 1'));
        expect(result, isNot(contains('START OF THIS PROJECT GUTENBERG')));
        expect(result, isNot(contains('header text')));
      });

      test('removes Project Gutenberg END marker and everything after', () {
        const input = '''
The end of the story.

*** END OF THIS PROJECT GUTENBERG EBOOK TEST ***

This file should be named test.txt
Most people start at our Web site
''';
        final result = BoilerplateRemover.removeFromBook(input);
        expect(result, equals('The end of the story.'));
        expect(result, isNot(contains('END OF THIS PROJECT GUTENBERG')));
        expect(result, isNot(contains('file should be named')));
      });

      test('removes both START and END markers', () {
        const input = '''
*** START OF THE PROJECT GUTENBERG EBOOK SAMPLE ***

Chapter 1

The story.

*** END OF THE PROJECT GUTENBERG EBOOK SAMPLE ***

License text here.
''';
        final result = BoilerplateRemover.removeFromBook(input);
        expect(result, equals('Chapter 1\n\nThe story.'));
      });

      test('handles "End of the Project Gutenberg" alternative marker', () {
        const input = '''
The story ends here.

End of the Project Gutenberg EBook

License follows.
''';
        final result = BoilerplateRemover.removeFromBook(input);
        expect(result, equals('The story ends here.'));
      });

      test('handles "The Project Gutenberg EBook of" header', () {
        const input = '''
The Project Gutenberg EBook of Pride and Prejudice, by Jane Austen

Chapter 1

It is a truth universally acknowledged...
''';
        final result = BoilerplateRemover.removeFromBook(input);
        expect(result, startsWith('Chapter 1'));
      });

      test('handles "This eBook is for the use of anyone anywhere" header', () {
        const input = '''
This eBook is for the use of anyone anywhere in the world.

Chapter 1

The actual story.
''';
        final result = BoilerplateRemover.removeFromBook(input);
        expect(result, startsWith('Chapter 1'));
      });

      test('returns unchanged content without PG markers', () {
        const input = '''
Chapter 1

The story begins.

Chapter 2

The story continues.
''';
        final result = BoilerplateRemover.removeFromBook(input);
        expect(result, equals(input));
      });
    });

    group('cleanChapter', () {
      test('removes "Produced by" paragraph from start', () {
        const input = '''
Produced by John Smith

Chapter 1

The story begins.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, startsWith('Chapter 1'));
      });

      test('removes "Scanned by" paragraph from start', () {
        const input = '''
Scanned by Archive.org volunteers

Chapter 1

The story begins.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, startsWith('Chapter 1'));
      });

      test('removes "Digitized by" paragraph from start', () {
        const input = '''
Digitized by Google

Chapter 1

The story.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, startsWith('Chapter 1'));
      });

      test('removes "Proofread by" paragraph from start', () {
        const input = '''
Proofread by volunteers

Chapter One

The narrative begins.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, startsWith('Chapter One'));
      });

      test('removes page number paragraphs', () {
        const input = '''
123

Chapter 1

The story.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, startsWith('Chapter 1'));
      });

      test('removes formatted page numbers like [123]', () {
        const input = '''
[ 42 ]

The next paragraph.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, equals('The next paragraph.'));
      });

      test('removes formatted page numbers like -123-', () {
        const input = '''
- 99 -

Story content here.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, equals('Story content here.'));
      });

      test('removes Z-Library attribution', () {
        const input = '''
Downloaded from z-library

Chapter 1

The story.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, startsWith('Chapter 1'));
      });

      test('removes LibGen attribution', () {
        const input = '''
From Library Genesis

The story content.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, equals('The story content.'));
      });

      test('removes public domain notice', () {
        const input = '''
This work is in the public domain

Chapter 1

The story begins.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, startsWith('Chapter 1'));
      });

      test('removes trailing boilerplate paragraphs', () {
        const input = '''
The story ends here.

Produced by Project Gutenberg
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, equals('The story ends here.'));
      });

      test('removes gutenberg.org reference', () {
        const input = '''
Visit www.gutenberg.org for more

The actual content.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, equals('The actual content.'));
      });

      test('preserves valid chapter content', () {
        const input = '''
Chapter 1

The story begins here.

And continues here.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, equals(input.trim()));
      });

      test('handles chapter with no boilerplate', () {
        const input = '''
It was the best of times, it was the worst of times.

The city lay quiet under the stars.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, equals(input.trim()));
      });

      test('does not remove everything even if suspicious', () {
        // Edge case: very short content that might look like boilerplate
        const input = 'Short text';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, equals(input));
      });

      test('handles empty input', () {
        const input = '';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, equals(''));
      });
    });

    group('detectRepeatedPrefix', () {
      test('detects repeated first line across chapters', () {
        final chapters = [
          'Downloaded from Library\n\nChapter 1 content',
          'Downloaded from Library\n\nChapter 2 content',
          'Downloaded from Library\n\nChapter 3 content',
          'Downloaded from Library\n\nChapter 4 content',
        ];
        final result = BoilerplateRemover.detectRepeatedPrefix(chapters);
        expect(result, equals('Downloaded from Library'));
      });

      test('returns null if no repeated prefix', () {
        final chapters = [
          'Chapter 1\n\nContent here',
          'Chapter 2\n\nMore content',
          'Chapter 3\n\nEven more',
        ];
        final result = BoilerplateRemover.detectRepeatedPrefix(chapters);
        expect(result, isNull);
      });

      test('returns null for too few chapters', () {
        final chapters = [
          'Same prefix\n\nContent',
          'Same prefix\n\nContent',
        ];
        final result = BoilerplateRemover.detectRepeatedPrefix(chapters);
        expect(result, isNull);
      });

      test('requires >50% chapters to have same prefix', () {
        final chapters = [
          'Same prefix\n\nContent 1',
          'Same prefix\n\nContent 2',
          'Different start\n\nContent 3',
          'Another start\n\nContent 4',
          'Yet another\n\nContent 5',
        ];
        final result = BoilerplateRemover.detectRepeatedPrefix(chapters);
        expect(result, isNull);
      });

      test('ignores very short prefixes', () {
        final chapters = [
          'Hi\n\nContent 1',
          'Hi\n\nContent 2',
          'Hi\n\nContent 3',
          'Hi\n\nContent 4',
        ];
        final result = BoilerplateRemover.detectRepeatedPrefix(chapters);
        expect(result, isNull);
      });
    });

    group('detectRepeatedSuffix', () {
      test('detects repeated last line across chapters', () {
        final chapters = [
          'Chapter 1 content\n\nEnd of chapter',
          'Chapter 2 content\n\nEnd of chapter',
          'Chapter 3 content\n\nEnd of chapter',
          'Chapter 4 content\n\nEnd of chapter',
        ];
        final result = BoilerplateRemover.detectRepeatedSuffix(chapters);
        expect(result, equals('End of chapter'));
      });

      test('returns null if no repeated suffix', () {
        final chapters = [
          'Content\n\nThe end of one',
          'Content\n\nAnother ending',
          'Content\n\nThird ending',
        ];
        final result = BoilerplateRemover.detectRepeatedSuffix(chapters);
        expect(result, isNull);
      });
    });

    group('removePrefix', () {
      test('removes known prefix from content', () {
        const content = 'Downloaded from X\n\nActual content';
        final result =
            BoilerplateRemover.removePrefix(content, 'Downloaded from X');
        expect(result, equals('Actual content'));
      });

      test('returns unchanged if prefix not present', () {
        const content = 'Different start\n\nActual content';
        final result =
            BoilerplateRemover.removePrefix(content, 'Downloaded from X');
        expect(result, equals(content));
      });

      test('handles prefix with leading whitespace in content', () {
        const content = '  Downloaded from X\n\nActual content';
        final result =
            BoilerplateRemover.removePrefix(content, 'Downloaded from X');
        expect(result, equals('Actual content'));
      });
    });

    group('removeSuffix', () {
      test('removes known suffix from content', () {
        const content = 'Actual content\n\n--- End ---';
        final result = BoilerplateRemover.removeSuffix(content, '--- End ---');
        expect(result, equals('Actual content'));
      });

      test('returns unchanged if suffix not present', () {
        const content = 'Actual content\n\nDifferent ending';
        final result = BoilerplateRemover.removeSuffix(content, '--- End ---');
        expect(result, equals(content));
      });
    });

    group('hasProjectGutenbergBoilerplate', () {
      test('returns true for content with START marker', () {
        const content = '''
*** START OF THIS PROJECT GUTENBERG EBOOK ***
Chapter 1
''';
        expect(BoilerplateRemover.hasProjectGutenbergBoilerplate(content),
            isTrue);
      });

      test('returns true for content with END marker', () {
        const content = '''
Chapter 10
*** END OF THE PROJECT GUTENBERG EBOOK ***
''';
        expect(BoilerplateRemover.hasProjectGutenbergBoilerplate(content),
            isTrue);
      });

      test('returns true for "End of Project Gutenberg" text', () {
        const content = '''
The story ends.
End of the Project Gutenberg EBook
''';
        expect(BoilerplateRemover.hasProjectGutenbergBoilerplate(content),
            isTrue);
      });

      test('returns false for regular content', () {
        const content = '''
Chapter 1

The story begins. Nothing about Gutenberg here.
''';
        expect(BoilerplateRemover.hasProjectGutenbergBoilerplate(content),
            isFalse);
      });
    });

    group('edge cases', () {
      test('handles content with only boilerplate patterns', () {
        // This shouldn't remove everything - safety check
        const content = '''
Produced by volunteers

Scanned by archive
''';
        final result = BoilerplateRemover.cleanChapter(content);
        // Should return original rather than empty
        expect(result, equals(content.trim()));
      });

      test('handles Internet Archive reference', () {
        const input = '''
Downloaded from Internet Archive

The real content starts here.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, equals('The real content starts here.'));
      });

      test('handles archive.org reference', () {
        const input = '''
Source: archive.org

The real content.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, equals('The real content.'));
      });

      test('handles OCR quality notice', () {
        const input = '''
OCR quality may vary

Chapter 1

The story.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, startsWith('Chapter 1'));
      });

      test('handles multiple boilerplate paragraphs at start', () {
        const input = '''
Produced by someone

Proofread by others

Chapter 1

Story content.
''';
        final result = BoilerplateRemover.cleanChapter(input);
        expect(result, startsWith('Chapter 1'));
      });
    });
  });
}
