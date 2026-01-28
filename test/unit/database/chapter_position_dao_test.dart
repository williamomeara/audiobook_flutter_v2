import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:audiobook_flutter_v2/app/database/daos/chapter_position_dao.dart';

void main() {
  late Database db;
  late ChapterPositionDao dao;

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
          CREATE TABLE chapter_positions (
            book_id TEXT NOT NULL,
            chapter_index INTEGER NOT NULL,
            segment_index INTEGER NOT NULL,
            is_primary INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY(book_id, chapter_index),
            FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_chapter_positions_primary 
          ON chapter_positions(book_id) 
          WHERE is_primary = 1
        ''');
        
        // Insert test data
        await db.insert('books', {'id': 'book-1'});
        await db.insert('books', {'id': 'book-2'});
      },
    );
    
    dao = ChapterPositionDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ChapterPositionDao', () {
    group('savePosition', () {
      test('saves new position correctly', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: false,
        );

        final result = await dao.getChapterPosition('book-1', 0);
        expect(result, isNotNull);
        expect(result!.chapterIndex, 0);
        expect(result.segmentIndex, 5);
        expect(result.isPrimary, false);
      });

      test('updates existing position on conflict', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: false,
        );
        
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 15,
          isPrimary: true,
        );

        final result = await dao.getChapterPosition('book-1', 0);
        expect(result!.segmentIndex, 15);
        expect(result.isPrimary, true);
      });

      test('saves primary position correctly', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 2,
          segmentIndex: 10,
          isPrimary: true,
        );

        final primary = await dao.getPrimaryPosition('book-1');
        expect(primary, isNotNull);
        expect(primary!.chapterIndex, 2);
        expect(primary.segmentIndex, 10);
        expect(primary.isPrimary, true);
      });
    });

    group('getPrimaryPosition', () {
      test('returns null when no primary position exists', () async {
        final result = await dao.getPrimaryPosition('book-1');
        expect(result, isNull);
      });

      test('returns the primary position when it exists', () async {
        // Add non-primary positions
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: false,
        );
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 1,
          segmentIndex: 10,
          isPrimary: true,
        );
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 2,
          segmentIndex: 15,
          isPrimary: false,
        );

        final primary = await dao.getPrimaryPosition('book-1');
        expect(primary, isNotNull);
        expect(primary!.chapterIndex, 1);
        expect(primary.segmentIndex, 10);
      });

      test('returns primary for specific book only', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: true,
        );
        await dao.savePosition(
          bookId: 'book-2',
          chapterIndex: 1,
          segmentIndex: 10,
          isPrimary: true,
        );

        final primary1 = await dao.getPrimaryPosition('book-1');
        final primary2 = await dao.getPrimaryPosition('book-2');

        expect(primary1!.chapterIndex, 0);
        expect(primary2!.chapterIndex, 1);
      });
    });

    group('getChapterPosition', () {
      test('returns null for non-existent chapter', () async {
        final result = await dao.getChapterPosition('book-1', 99);
        expect(result, isNull);
      });

      test('returns position for specific chapter', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: false,
        );
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 1,
          segmentIndex: 10,
          isPrimary: false,
        );

        final chapter0 = await dao.getChapterPosition('book-1', 0);
        final chapter1 = await dao.getChapterPosition('book-1', 1);

        expect(chapter0!.segmentIndex, 5);
        expect(chapter1!.segmentIndex, 10);
      });
    });

    group('getAllPositions', () {
      test('returns empty map when no positions exist', () async {
        final result = await dao.getAllPositions('book-1');
        expect(result, isEmpty);
      });

      test('returns all positions keyed by chapter index', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: true,
        );
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 3,
          segmentIndex: 15,
          isPrimary: false,
        );
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 1,
          segmentIndex: 10,
          isPrimary: false,
        );

        final result = await dao.getAllPositions('book-1');

        expect(result.length, 3);
        expect(result[0]!.segmentIndex, 5);
        expect(result[1]!.segmentIndex, 10);
        expect(result[3]!.segmentIndex, 15);
        expect(result[0]!.isPrimary, true);
      });

      test('returns positions for specific book only', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: true,
        );
        await dao.savePosition(
          bookId: 'book-2',
          chapterIndex: 0,
          segmentIndex: 10,
          isPrimary: true,
        );

        final book1Positions = await dao.getAllPositions('book-1');
        final book2Positions = await dao.getAllPositions('book-2');

        expect(book1Positions.length, 1);
        expect(book2Positions.length, 1);
        expect(book1Positions[0]!.segmentIndex, 5);
        expect(book2Positions[0]!.segmentIndex, 10);
      });
    });

    group('clearPrimaryFlag', () {
      test('clears primary flag from all positions', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: true,
        );
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 1,
          segmentIndex: 10,
          isPrimary: false,
        );

        await dao.clearPrimaryFlag('book-1');

        final position0 = await dao.getChapterPosition('book-1', 0);
        final position1 = await dao.getChapterPosition('book-1', 1);
        final primary = await dao.getPrimaryPosition('book-1');

        expect(position0!.isPrimary, false);
        expect(position1!.isPrimary, false);
        expect(primary, isNull);
      });

      test('only clears primary flag for specified book', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: true,
        );
        await dao.savePosition(
          bookId: 'book-2',
          chapterIndex: 0,
          segmentIndex: 10,
          isPrimary: true,
        );

        await dao.clearPrimaryFlag('book-1');

        final primary1 = await dao.getPrimaryPosition('book-1');
        final primary2 = await dao.getPrimaryPosition('book-2');

        expect(primary1, isNull);
        expect(primary2, isNotNull);
        expect(primary2!.chapterIndex, 0);
      });
    });

    group('setPrimaryChapter', () {
      test('sets specified chapter as primary', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: true,
        );
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 1,
          segmentIndex: 10,
          isPrimary: false,
        );

        await dao.setPrimaryChapter('book-1', 1);

        final position0 = await dao.getChapterPosition('book-1', 0);
        final position1 = await dao.getChapterPosition('book-1', 1);

        expect(position0!.isPrimary, false);
        expect(position1!.isPrimary, true);
      });

      test('only one chapter can be primary at a time', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: true,
        );
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 1,
          segmentIndex: 10,
          isPrimary: true,
        );
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 2,
          segmentIndex: 15,
          isPrimary: true,
        );

        await dao.setPrimaryChapter('book-1', 2);

        final positions = await dao.getAllPositions('book-1');
        final primaryCount = positions.values.where((p) => p.isPrimary).length;

        expect(primaryCount, 1);
        expect(positions[2]!.isPrimary, true);
      });
    });

    group('deleteBookPositions', () {
      test('deletes all positions for a book', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: true,
        );
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 1,
          segmentIndex: 10,
          isPrimary: false,
        );

        await dao.deleteBookPositions('book-1');

        final positions = await dao.getAllPositions('book-1');
        expect(positions, isEmpty);
      });

      test('does not affect other books', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: true,
        );
        await dao.savePosition(
          bookId: 'book-2',
          chapterIndex: 0,
          segmentIndex: 10,
          isPrimary: true,
        );

        await dao.deleteBookPositions('book-1');

        final book1Positions = await dao.getAllPositions('book-1');
        final book2Positions = await dao.getAllPositions('book-2');

        expect(book1Positions, isEmpty);
        expect(book2Positions.length, 1);
      });
    });

    group('deleteChapterPosition', () {
      test('deletes position for specific chapter', () async {
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 0,
          segmentIndex: 5,
          isPrimary: true,
        );
        await dao.savePosition(
          bookId: 'book-1',
          chapterIndex: 1,
          segmentIndex: 10,
          isPrimary: false,
        );

        await dao.deleteChapterPosition('book-1', 0);

        final position0 = await dao.getChapterPosition('book-1', 0);
        final position1 = await dao.getChapterPosition('book-1', 1);

        expect(position0, isNull);
        expect(position1, isNotNull);
      });
    });

    group('ChapterPosition', () {
      test('fromMap creates correct instance', () {
        final map = {
          'chapter_index': 5,
          'segment_index': 10,
          'is_primary': 1,
          'updated_at': 1234567890,
        };

        final position = ChapterPosition.fromMap(map);

        expect(position.chapterIndex, 5);
        expect(position.segmentIndex, 10);
        expect(position.isPrimary, true);
        expect(position.updatedAt, DateTime.fromMillisecondsSinceEpoch(1234567890));
      });

      test('toMap creates correct map', () {
        final position = ChapterPosition(
          chapterIndex: 3,
          segmentIndex: 7,
          isPrimary: false,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(9876543210),
        );

        final map = position.toMap();

        expect(map['chapter_index'], 3);
        expect(map['segment_index'], 7);
        expect(map['is_primary'], 0);
        expect(map['updated_at'], 9876543210);
      });

      test('equality works correctly', () {
        final position1 = ChapterPosition(
          chapterIndex: 1,
          segmentIndex: 5,
          isPrimary: true,
          updatedAt: DateTime.now(),
        );
        final position2 = ChapterPosition(
          chapterIndex: 1,
          segmentIndex: 5,
          isPrimary: true,
          updatedAt: DateTime.now(),
        );
        final position3 = ChapterPosition(
          chapterIndex: 2,
          segmentIndex: 5,
          isPrimary: true,
          updatedAt: DateTime.now(),
        );

        expect(position1, equals(position2));
        expect(position1, isNot(equals(position3)));
      });

      test('toString returns informative string', () {
        final position = ChapterPosition(
          chapterIndex: 3,
          segmentIndex: 7,
          isPrimary: true,
          updatedAt: DateTime.now(),
        );

        expect(position.toString(), contains('chapter: 3'));
        expect(position.toString(), contains('segment: 7'));
        expect(position.toString(), contains('primary: true'));
      });
    });
  });
}
