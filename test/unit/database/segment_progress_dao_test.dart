import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiobook_flutter_v2/app/database/daos/segment_progress_dao.dart';

void main() {
  late Database db;
  late SegmentProgressDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Create in-memory database with test schema
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        // Create minimal schema for testing
        await db.execute('''
          CREATE TABLE books (
            id TEXT PRIMARY KEY
          )
        ''');
        await db.execute('''
          CREATE TABLE segments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            chapter_index INTEGER NOT NULL,
            segment_index INTEGER NOT NULL,
            text TEXT NOT NULL,
            char_count INTEGER NOT NULL,
            estimated_duration_ms INTEGER NOT NULL,
            UNIQUE(book_id, chapter_index, segment_index)
          )
        ''');
        await db.execute('''
          CREATE TABLE segment_progress (
            book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            chapter_index INTEGER NOT NULL,
            segment_index INTEGER NOT NULL,
            listened_at INTEGER NOT NULL,
            PRIMARY KEY(book_id, chapter_index, segment_index)
          )
        ''');
        
        // Insert test data
        await db.insert('books', {'id': 'book-1'});
        await db.insert('books', {'id': 'book-2'});
        
        // Add segments for book-1, chapter 0 (5 segments)
        for (int i = 0; i < 5; i++) {
          await db.insert('segments', {
            'book_id': 'book-1',
            'chapter_index': 0,
            'segment_index': i,
            'text': 'Segment $i text',
            'char_count': 15,
            'estimated_duration_ms': 1000,
          });
        }
        
        // Add segments for book-1, chapter 1 (3 segments)
        for (int i = 0; i < 3; i++) {
          await db.insert('segments', {
            'book_id': 'book-1',
            'chapter_index': 1,
            'segment_index': i,
            'text': 'Chapter 1 segment $i',
            'char_count': 20,
            'estimated_duration_ms': 1200,
          });
        }
        
        // Add segments for book-2, chapter 0 (2 segments)
        for (int i = 0; i < 2; i++) {
          await db.insert('segments', {
            'book_id': 'book-2',
            'chapter_index': 0,
            'segment_index': i,
            'text': 'Book 2 segment $i',
            'char_count': 17,
            'estimated_duration_ms': 900,
          });
        }
      },
    );
    
    dao = SegmentProgressDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('SegmentProgressDao', () {
    group('markListened', () {
      test('marks a segment as listened', () async {
        await dao.markListened('book-1', 0, 0);
        
        final isListened = await dao.isSegmentListened('book-1', 0, 0);
        expect(isListened, true);
      });

      test('is idempotent (marking twice does not fail)', () async {
        await dao.markListened('book-1', 0, 0);
        await dao.markListened('book-1', 0, 0); // Second call should not throw
        
        final isListened = await dao.isSegmentListened('book-1', 0, 0);
        expect(isListened, true);
      });

      test('unlistened segment returns false', () async {
        final isListened = await dao.isSegmentListened('book-1', 0, 0);
        expect(isListened, false);
      });
    });

    group('markManyListened', () {
      test('marks multiple segments as listened', () async {
        await dao.markManyListened('book-1', 0, [0, 1, 2]);
        
        expect(await dao.isSegmentListened('book-1', 0, 0), true);
        expect(await dao.isSegmentListened('book-1', 0, 1), true);
        expect(await dao.isSegmentListened('book-1', 0, 2), true);
        expect(await dao.isSegmentListened('book-1', 0, 3), false);
      });

      test('handles empty list', () async {
        await dao.markManyListened('book-1', 0, []);
        // Should not throw
      });
    });

    group('markChapterListened', () {
      test('marks all segments in chapter as listened', () async {
        await dao.markChapterListened('book-1', 0, 5);
        
        final progress = await dao.getChapterProgress('book-1', 0);
        expect(progress, isNotNull);
        expect(progress!.isComplete, true);
        expect(progress.listenedSegments, 5);
        expect(progress.totalSegments, 5);
      });
    });

    group('clearChapterProgress', () {
      test('clears progress for a chapter', () async {
        await dao.markManyListened('book-1', 0, [0, 1, 2]);
        expect(await dao.isSegmentListened('book-1', 0, 0), true);
        
        await dao.clearChapterProgress('book-1', 0);
        
        expect(await dao.isSegmentListened('book-1', 0, 0), false);
        expect(await dao.isSegmentListened('book-1', 0, 1), false);
        expect(await dao.isSegmentListened('book-1', 0, 2), false);
      });

      test('does not affect other chapters', () async {
        await dao.markListened('book-1', 0, 0);
        await dao.markListened('book-1', 1, 0);
        
        await dao.clearChapterProgress('book-1', 0);
        
        expect(await dao.isSegmentListened('book-1', 0, 0), false);
        expect(await dao.isSegmentListened('book-1', 1, 0), true);
      });
    });

    group('clearBookProgress', () {
      test('clears all progress for a book', () async {
        await dao.markListened('book-1', 0, 0);
        await dao.markListened('book-1', 0, 1);
        await dao.markListened('book-1', 1, 0);
        
        await dao.clearBookProgress('book-1');
        
        expect(await dao.isSegmentListened('book-1', 0, 0), false);
        expect(await dao.isSegmentListened('book-1', 0, 1), false);
        expect(await dao.isSegmentListened('book-1', 1, 0), false);
      });

      test('does not affect other books', () async {
        await dao.markListened('book-1', 0, 0);
        await dao.markListened('book-2', 0, 0);
        
        await dao.clearBookProgress('book-1');
        
        expect(await dao.isSegmentListened('book-1', 0, 0), false);
        expect(await dao.isSegmentListened('book-2', 0, 0), true);
      });
    });

    group('getListenedSegments', () {
      test('returns set of listened segment indices', () async {
        await dao.markManyListened('book-1', 0, [0, 2, 4]);
        
        final listened = await dao.getListenedSegments('book-1', 0);
        
        expect(listened, {0, 2, 4});
      });

      test('returns empty set for chapter with no progress', () async {
        final listened = await dao.getListenedSegments('book-1', 0);
        
        expect(listened, isEmpty);
      });
    });

    group('getChapterProgress', () {
      test('returns correct progress percentages', () async {
        await dao.markManyListened('book-1', 0, [0, 1]);  // 2/5 = 40%
        
        final progress = await dao.getChapterProgress('book-1', 0);
        
        expect(progress, isNotNull);
        expect(progress!.totalSegments, 5);
        expect(progress.listenedSegments, 2);
        expect(progress.percentComplete, closeTo(0.4, 0.001));
        expect(progress.hasStarted, true);
        expect(progress.isComplete, false);
      });

      test('returns null for non-existent chapter', () async {
        final progress = await dao.getChapterProgress('book-1', 99);
        
        expect(progress, isNull);
      });

      test('isComplete returns true when all segments listened', () async {
        await dao.markChapterListened('book-1', 1, 3);
        
        final progress = await dao.getChapterProgress('book-1', 1);
        
        expect(progress, isNotNull);
        expect(progress!.isComplete, true);
        expect(progress.percentComplete, 1.0);
      });
    });

    group('getBookProgress', () {
      test('returns progress for all chapters', () async {
        await dao.markManyListened('book-1', 0, [0, 1]);  // 2/5
        await dao.markManyListened('book-1', 1, [0, 1, 2]);  // 3/3
        
        final progress = await dao.getBookProgress('book-1');
        
        expect(progress.length, 2);
        expect(progress[0]!.listenedSegments, 2);
        expect(progress[0]!.totalSegments, 5);
        expect(progress[1]!.listenedSegments, 3);
        expect(progress[1]!.totalSegments, 3);
        expect(progress[1]!.isComplete, true);
      });

      test('returns empty map for book with no segments', () async {
        final progress = await dao.getBookProgress('non-existent');
        
        expect(progress, isEmpty);
      });
    });

    group('getBookProgressSummary', () {
      test('returns total book progress', () async {
        await dao.markManyListened('book-1', 0, [0, 1]);  // 2 segments
        await dao.markManyListened('book-1', 1, [0]);  // 1 segment
        // Total: 3/8 segments
        
        final summary = await dao.getBookProgressSummary('book-1');
        
        expect(summary.totalSegments, 8);
        expect(summary.listenedSegments, 3);
        expect(summary.percentComplete, closeTo(0.375, 0.001));
        expect(summary.isComplete, false);
      });
    });

    group('getLastListenedSegment', () {
      test('returns highest listened segment index', () async {
        await dao.markManyListened('book-1', 0, [0, 2, 3]);
        
        final last = await dao.getLastListenedSegment('book-1', 0);
        
        expect(last, 3);
      });

      test('returns null for chapter with no progress', () async {
        final last = await dao.getLastListenedSegment('book-1', 0);
        
        expect(last, isNull);
      });
    });
  });

  group('ChapterProgress', () {
    test('percentComplete handles zero total', () {
      const progress = ChapterProgress(
        chapterIndex: 0,
        totalSegments: 0,
        listenedSegments: 0,
      );
      
      expect(progress.percentComplete, 0.0);
      expect(progress.isComplete, false);
    });

    test('toString provides useful info', () {
      const progress = ChapterProgress(
        chapterIndex: 2,
        totalSegments: 10,
        listenedSegments: 5,
      );
      
      expect(progress.toString(), contains('50.0%'));
    });
  });

  group('BookProgressSummary', () {
    test('percentComplete handles zero total', () {
      const summary = BookProgressSummary(
        totalSegments: 0,
        listenedSegments: 0,
      );
      
      expect(summary.percentComplete, 0.0);
      expect(summary.isComplete, false);
    });
  });
}
