import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/utils/content_classifier.dart';

void main() {
  group('ContentClassifier', () {
    group('classify by title', () {
      test('identifies Copyright as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'page1.xhtml',
          title: 'Copyright',
          contentSnippet: 'Some text here',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies Title Page as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'page1.xhtml',
          title: 'Title Page',
          contentSnippet: 'Book title',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies Cover as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'page.xhtml',
          title: 'Cover',
          contentSnippet: '',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies Dedication as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'ded.xhtml',
          title: 'Dedication',
          contentSnippet: 'For my family',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies Contents as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'toc.xhtml',
          title: 'Contents',
          contentSnippet: 'Chapter 1 ... Chapter 2',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies Table of Contents as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'toc.xhtml',
          title: 'Table of Contents',
          contentSnippet: 'Chapter list',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies Epigraph as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'ep.xhtml',
          title: 'Epigraph',
          contentSnippet: 'A quote',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies Foreword as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'fw.xhtml',
          title: 'Foreword',
          contentSnippet: 'Introduction by someone',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies Preface as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'pf.xhtml',
          title: 'Preface',
          contentSnippet: 'Author preface',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies Also By as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'also.xhtml',
          title: 'Also By Author Name',
          contentSnippet: 'Other books',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies Dramatis Personae as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'chars.xhtml',
          title: 'Dramatis Personae',
          contentSnippet: 'Character list',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies About the Author as back matter', () {
        final result = ContentClassifier.classify(
          filename: 'author.xhtml',
          title: 'About the Author',
          contentSnippet: 'Jane Smith lives...',
        );
        expect(result, equals(ContentType.backMatter));
      });

      test('identifies About Author as back matter', () {
        final result = ContentClassifier.classify(
          filename: 'author.xhtml',
          title: 'About Author',
          contentSnippet: 'Bio here',
        );
        expect(result, equals(ContentType.backMatter));
      });

      test('identifies Acknowledgments as back matter', () {
        final result = ContentClassifier.classify(
          filename: 'ack.xhtml',
          title: 'Acknowledgments',
          contentSnippet: 'Thanks to...',
        );
        expect(result, equals(ContentType.backMatter));
      });

      test('identifies Bibliography as back matter', () {
        final result = ContentClassifier.classify(
          filename: 'bib.xhtml',
          title: 'Bibliography',
          contentSnippet: 'References',
        );
        expect(result, equals(ContentType.backMatter));
      });

      test('identifies Index as back matter', () {
        final result = ContentClassifier.classify(
          filename: 'idx.xhtml',
          title: 'Index',
          contentSnippet: 'A-Z entries',
        );
        expect(result, equals(ContentType.backMatter));
      });

      test('identifies Reader\'s Guide as back matter', () {
        final result = ContentClassifier.classify(
          filename: 'guide.xhtml',
          title: 'Reader\'s Guide',
          contentSnippet: 'Discussion',
        );
        expect(result, equals(ContentType.backMatter));
      });

      test('identifies Discussion Questions as back matter', () {
        final result = ContentClassifier.classify(
          filename: 'questions.xhtml',
          title: 'Discussion Questions',
          contentSnippet: 'Questions',
        );
        expect(result, equals(ContentType.backMatter));
      });

      test('identifies Newsletter as back matter', () {
        final result = ContentClassifier.classify(
          filename: 'news.xhtml',
          title: 'Newsletter Sign-up',
          contentSnippet: 'Subscribe',
        );
        expect(result, equals(ContentType.backMatter));
      });

      test('identifies "Discover your next" as back matter', () {
        final result = ContentClassifier.classify(
          filename: 'next-reads.xhtml',
          title: 'Discover your next great read!',
          contentSnippet: 'More books',
        );
        expect(result, equals(ContentType.backMatter));
      });
    });

    group('classify by title - body matter', () {
      test('identifies Chapter 1 as body matter', () {
        final result = ContentClassifier.classify(
          filename: 'ch01.xhtml',
          title: 'Chapter 1',
          contentSnippet: 'Story begins',
        );
        expect(result, equals(ContentType.bodyMatter));
      });

      test('identifies Chapter IV (roman) as body matter', () {
        final result = ContentClassifier.classify(
          filename: 'ch04.xhtml',
          title: 'Chapter IV',
          contentSnippet: 'Story continues',
        );
        expect(result, equals(ContentType.bodyMatter));
      });

      test('identifies Part 1 as body matter', () {
        final result = ContentClassifier.classify(
          filename: 'part1.xhtml',
          title: 'Part 1',
          contentSnippet: 'Part heading',
        );
        expect(result, equals(ContentType.bodyMatter));
      });

      test('identifies Prologue as body matter', () {
        final result = ContentClassifier.classify(
          filename: 'prl.xhtml',
          title: 'Prologue',
          contentSnippet: 'Story begins',
        );
        expect(result, equals(ContentType.bodyMatter));
      });

      test('identifies Epilogue as body matter', () {
        final result = ContentClassifier.classify(
          filename: 'epi.xhtml',
          title: 'Epilogue',
          contentSnippet: 'Story ends',
        );
        expect(result, equals(ContentType.bodyMatter));
      });

      test('identifies just a number as body matter', () {
        final result = ContentClassifier.classify(
          filename: 'ch05.xhtml',
          title: '5',
          contentSnippet: 'Chapter content',
        );
        expect(result, equals(ContentType.bodyMatter));
      });

      test('identifies just roman numerals as body matter', () {
        final result = ContentClassifier.classify(
          filename: 'ch03.xhtml',
          title: 'III',
          contentSnippet: 'Chapter content',
        );
        expect(result, equals(ContentType.bodyMatter));
      });

      test('identifies Interlude as body matter', () {
        final result = ContentClassifier.classify(
          filename: 'int.xhtml',
          title: 'Interlude',
          contentSnippet: 'A break',
        );
        expect(result, equals(ContentType.bodyMatter));
      });
    });

    group('classify by epub:type', () {
      test('respects epub:type frontmatter', () {
        final result = ContentClassifier.classify(
          filename: 'chapter.xhtml',
          title: 'Chapter 1',
          contentSnippet: 'Story content',
          epubType: 'frontmatter',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('respects epub:type cover', () {
        final result = ContentClassifier.classify(
          filename: 'any.xhtml',
          title: 'Any',
          contentSnippet: '',
          epubType: 'cover',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('respects epub:type bodymatter', () {
        final result = ContentClassifier.classify(
          filename: 'any.xhtml',
          title: 'Copyright',
          contentSnippet: 'All rights reserved',
          epubType: 'bodymatter',
        );
        expect(result, equals(ContentType.bodyMatter));
      });

      test('respects epub:type chapter', () {
        final result = ContentClassifier.classify(
          filename: 'any.xhtml',
          title: 'Any',
          contentSnippet: '',
          epubType: 'chapter',
        );
        expect(result, equals(ContentType.bodyMatter));
      });

      test('respects epub:type backmatter', () {
        final result = ContentClassifier.classify(
          filename: 'any.xhtml',
          title: 'Prologue',
          contentSnippet: 'Story',
          epubType: 'backmatter',
        );
        expect(result, equals(ContentType.backMatter));
      });
    });

    group('classify by filename', () {
      test('identifies cover.xhtml as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'cover.xhtml',
          title: '',
          contentSnippet: '',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies _toc_ pattern as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'book_toc_r1.xhtml',
          title: '',
          contentSnippet: '',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies _cop_ pattern as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'book_cop_r1.xhtml',
          title: '',
          contentSnippet: '',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies _ded_ pattern as front matter', () {
        final result = ContentClassifier.classify(
          filename: 'book_ded_r1.xhtml',
          title: '',
          contentSnippet: '',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('identifies next-reads.xhtml as back matter', () {
        final result = ContentClassifier.classify(
          filename: 'next-reads.xhtml',
          title: '',
          contentSnippet: '',
        );
        expect(result, equals(ContentType.backMatter));
      });
    });

    group('classify by content', () {
      test('detects copyright notice in content', () {
        final result = ContentClassifier.classify(
          filename: 'page.xhtml',
          title: '',
          contentSnippet: 'Copyright © 2023 by Author Name',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('detects ISBN in content', () {
        final result = ContentClassifier.classify(
          filename: 'page.xhtml',
          title: '',
          contentSnippet: 'ISBN 978-0-123456-78-9. All rights reserved.',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('detects "All rights reserved" in content', () {
        final result = ContentClassifier.classify(
          filename: 'page.xhtml',
          title: '',
          contentSnippet: 'All rights reserved. No part of this...',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('detects dedication pattern "For my"', () {
        final result = ContentClassifier.classify(
          filename: 'page.xhtml',
          title: '',
          contentSnippet: 'For my beloved family and friends.',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('detects author bio pattern', () {
        final result = ContentClassifier.classify(
          filename: 'page.xhtml',
          title: '',
          contentSnippet: 'Jane Smith is the author of many books.',
        );
        expect(result, equals(ContentType.backMatter));
      });

      test('detects "lives in" pattern (author bio)', () {
        final result = ContentClassifier.classify(
          filename: 'page.xhtml',
          title: '',
          contentSnippet: 'The author lives in Seattle with her cats.',
        );
        expect(result, equals(ContentType.backMatter));
      });
    });

    group('classify short content heuristic', () {
      test('returns front matter for short content without sentence structure', () {
        // Short content (< 200 chars) without proper sentences is likely front matter
        final result = ContentClassifier.classify(
          filename: 'ch07.xhtml',
          title: 'The Journey Begins',
          contentSnippet: 'It was a dark and stormy night...',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('returns front matter for empty content', () {
        // Empty content is also considered short without sentences
        final result = ContentClassifier.classify(
          filename: '',
          title: '',
          contentSnippet: '',
        );
        expect(result, equals(ContentType.frontMatter));
      });

      test('returns body matter for short content WITH sentence structure', () {
        // Short content with proper sentence structure is body matter
        final result = ContentClassifier.classify(
          filename: 'ch07.xhtml',
          title: 'Chapter 7',
          contentSnippet: 'It was a dark and stormy night. Sarah woke up suddenly.',
        );
        expect(result, equals(ContentType.bodyMatter));
      });

      test('returns body matter for content over 200 chars', () {
        // Longer content defaults to body matter even without sentence structure
        final longContent = 'A' * 250;
        final result = ContentClassifier.classify(
          filename: 'ch07.xhtml',
          title: 'Unknown',
          contentSnippet: longContent,
        );
        expect(result, equals(ContentType.bodyMatter));
      });
    });

    group('findBodyMatterRange', () {
      test('skips front matter at start', () {
        final chapters = [
          ChapterInfo(
              filename: 'cover.xhtml', title: 'Cover', contentSnippet: ''),
          ChapterInfo(
              filename: 'copyright.xhtml',
              title: 'Copyright',
              contentSnippet: ''),
          ChapterInfo(
              filename: 'ch1.xhtml',
              title: 'Chapter 1',
              contentSnippet: 'Story'),
          ChapterInfo(
              filename: 'ch2.xhtml',
              title: 'Chapter 2',
              contentSnippet: 'Story'),
        ];

        final (start, end) = ContentClassifier.findBodyMatterRange(chapters);
        expect(start, equals(2));
        expect(end, equals(4));
      });

      test('skips back matter at end', () {
        final chapters = [
          ChapterInfo(
              filename: 'ch1.xhtml',
              title: 'Chapter 1',
              contentSnippet: 'Story'),
          ChapterInfo(
              filename: 'ch2.xhtml',
              title: 'Chapter 2',
              contentSnippet: 'Story'),
          ChapterInfo(
              filename: 'about.xhtml',
              title: 'About the Author',
              contentSnippet: 'Bio'),
        ];

        final (start, end) = ContentClassifier.findBodyMatterRange(chapters);
        expect(start, equals(0));
        expect(end, equals(2));
      });

      test('skips both front and back matter', () {
        final chapters = [
          ChapterInfo(
              filename: 'cover.xhtml', title: 'Cover', contentSnippet: ''),
          ChapterInfo(
              filename: 'copyright.xhtml',
              title: 'Copyright',
              contentSnippet: ''),
          ChapterInfo(
              filename: 'dedication.xhtml',
              title: 'Dedication',
              contentSnippet: ''),
          ChapterInfo(
              filename: 'ch1.xhtml',
              title: 'Chapter 1',
              contentSnippet: 'Story'),
          ChapterInfo(
              filename: 'ch2.xhtml',
              title: 'Chapter 2',
              contentSnippet: 'Story'),
          ChapterInfo(
              filename: 'epilogue.xhtml',
              title: 'Epilogue',
              contentSnippet: 'End'),
          ChapterInfo(
              filename: 'about.xhtml',
              title: 'About the Author',
              contentSnippet: 'Bio'),
          ChapterInfo(
              filename: 'ack.xhtml',
              title: 'Acknowledgments',
              contentSnippet: 'Thanks'),
        ];

        final (start, end) = ContentClassifier.findBodyMatterRange(chapters);
        expect(start, equals(3)); // Chapter 1
        expect(end, equals(6)); // After Epilogue
      });

      test('handles empty list', () {
        final (start, end) = ContentClassifier.findBodyMatterRange([]);
        expect(start, equals(0));
        expect(end, equals(0));
      });

      test('handles all front matter (returns all as fallback)', () {
        final chapters = [
          ChapterInfo(
              filename: 'cover.xhtml', title: 'Cover', contentSnippet: ''),
          ChapterInfo(
              filename: 'copyright.xhtml',
              title: 'Copyright',
              contentSnippet: ''),
        ];

        final (start, end) = ContentClassifier.findBodyMatterRange(chapters);
        expect(start, equals(0));
        expect(end, equals(2)); // Fallback: return all
      });

      test('handles real book example - Gideon The Ninth', () {
        final chapters = [
          ChapterInfo(
              filename: 'title.xhtml',
              title: 'Title Page',
              contentSnippet: ''),
          ChapterInfo(
              filename: 'copyright.xhtml',
              title: 'Copyright Notice',
              contentSnippet: 'Copyright'),
          ChapterInfo(
              filename: 'ded.xhtml',
              title: 'Dedication',
              contentSnippet: 'for pT'),
          ChapterInfo(
              filename: 'dramatis.xhtml',
              title: 'Dramatis Personae',
              contentSnippet: 'Characters'),
          ChapterInfo(
              filename: 'epigraph.xhtml',
              title: 'Epigraph',
              contentSnippet: 'Quote'),
          ChapterInfo(
              filename: 'ch01.xhtml',
              title: 'Chapter 1',
              contentSnippet: 'Story'),
          ChapterInfo(
              filename: 'ch02.xhtml',
              title: 'Chapter 2',
              contentSnippet: 'Story'),
          ChapterInfo(
              filename: 'epilogue.xhtml',
              title: 'Epilogue',
              contentSnippet: 'End'),
          ChapterInfo(
              filename: 'ack.xhtml',
              title: 'Acknowledgments',
              contentSnippet: 'Thanks'),
          ChapterInfo(
              filename: 'about.xhtml',
              title: 'About the Author',
              contentSnippet: 'Bio'),
        ];

        final (start, end) = ContentClassifier.findBodyMatterRange(chapters);
        expect(start, equals(5)); // Chapter 1
        expect(end, equals(8)); // After Epilogue
      });

      test('handles real book example - Kindred', () {
        final chapters = [
          ChapterInfo(
              filename: 'cover.xhtml',
              title: 'Cover Page',
              contentSnippet: 'Kindred'),
          ChapterInfo(
              filename: 'title.xhtml',
              title: 'Title Page',
              contentSnippet: 'Kindred'),
          ChapterInfo(
              filename: 'ded.xhtml',
              title: 'Dedication',
              contentSnippet: 'To Victoria'),
          ChapterInfo(
              filename: 'toc.xhtml',
              title: 'Contents',
              contentSnippet: 'Table'),
          ChapterInfo(
              filename: 'prl.xhtml',
              title: 'Prologue',
              contentSnippet: 'I lost an arm'),
          ChapterInfo(
              filename: 'ch01.xhtml',
              title: 'Chapter 1 - The River',
              contentSnippet: 'Story'),
          ChapterInfo(
              filename: 'epilogue.xhtml',
              title: 'Epilogue',
              contentSnippet: 'End'),
          ChapterInfo(
              filename: 'guide.xhtml',
              title: 'Reader\'s Guide',
              contentSnippet: 'Discussion'),
          ChapterInfo(
              filename: 'questions.xhtml',
              title: 'Discussion Questions',
              contentSnippet: 'Questions'),
          ChapterInfo(
              filename: 'copyright.xhtml',
              title: 'Copyright',
              contentSnippet: 'Rights'),
        ];

        final (start, end) = ContentClassifier.findBodyMatterRange(chapters);
        expect(start, equals(4)); // Prologue
        expect(end, equals(7)); // After Epilogue
      });
    });

    group('classifyAll', () {
      test('returns list of classifications', () {
        final chapters = [
          ChapterInfo(
              filename: 'cover.xhtml', title: 'Cover', contentSnippet: ''),
          ChapterInfo(
              filename: 'ch1.xhtml',
              title: 'Chapter 1',
              contentSnippet: 'Story'),
          ChapterInfo(
              filename: 'about.xhtml',
              title: 'About the Author',
              contentSnippet: 'Bio'),
        ];

        final types = ContentClassifier.classifyAll(chapters);
        expect(types.length, equals(3));
        expect(types[0], equals(ContentType.frontMatter));
        expect(types[1], equals(ContentType.bodyMatter));
        expect(types[2], equals(ContentType.backMatter));
      });
    });

    group('filterToBodyMatter', () {
      test('filters to body matter only', () {
        final chapters = ['Cover', 'Copyright', 'Chapter 1', 'Chapter 2', 'About'];
        final chapterInfos = [
          ChapterInfo(
              filename: 'cover.xhtml', title: 'Cover', contentSnippet: ''),
          ChapterInfo(
              filename: 'copyright.xhtml',
              title: 'Copyright',
              contentSnippet: ''),
          ChapterInfo(
              filename: 'ch1.xhtml',
              title: 'Chapter 1',
              contentSnippet: 'Story'),
          ChapterInfo(
              filename: 'ch2.xhtml',
              title: 'Chapter 2',
              contentSnippet: 'Story'),
          ChapterInfo(
              filename: 'about.xhtml',
              title: 'About the Author',
              contentSnippet: 'Bio'),
        ];

        final bodyMatter =
            ContentClassifier.filterToBodyMatter(chapters, chapterInfos);
        expect(bodyMatter, equals(['Chapter 1', 'Chapter 2']));
      });

      test('throws if lists have different lengths', () {
        expect(
          () => ContentClassifier.filterToBodyMatter(
            ['a', 'b'],
            [ChapterInfo(filename: 'a', title: 'a', contentSnippet: '')],
          ),
          throwsArgumentError,
        );
      });
    });
  });
}
