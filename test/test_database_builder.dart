// Creates a test SQLite database matching the app's schema
// Run with: dart run test/test_database_builder.dart

import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

void main() async {
  final fixturesDir = Directory('test/fixtures');
  await fixturesDir.create(recursive: true);

  final dbPath = '${fixturesDir.path}/test_audiobook.db';

  // Remove existing database
  final existingDb = File(dbPath);
  if (await existingDb.exists()) {
    await existingDb.delete();
    print('Removed existing database');
  }

  // Create new database
  final db = sqlite3.open(dbPath);
  print('Created database: $dbPath\n');

  try {
    // Create schema
    _createSchema(db);
    print('✓ Schema created\n');

    // Seed with test data
    _seedTestData(db);
    print('✓ Test data loaded\n');

    // Print statistics
    _printDatabaseStats(db);
  } finally {
    db.dispose();
  }

  print('\nTest database ready at: $dbPath');
  print('Use in tests with:\n');
  print('  final dbFile = File("test/fixtures/test_audiobook.db");');
  print('  final db = sqlite3.open(dbFile.path);');
}

void _createSchema(Database db) {
  // Books table
  db.execute('''
    CREATE TABLE IF NOT EXISTS books (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      author TEXT,
      cover_path TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');

  // Chapters table
  db.execute('''
    CREATE TABLE IF NOT EXISTS chapters (
      id TEXT PRIMARY KEY,
      book_id TEXT NOT NULL,
      number INTEGER NOT NULL,
      title TEXT,
      content TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (book_id) REFERENCES books(id)
    )
  ''');

  // Create indices
  db.execute('CREATE INDEX idx_chapters_book_id ON chapters(book_id)');
  db.execute('CREATE INDEX idx_chapters_number ON chapters(number)');
}

void _seedTestData(Database db) {
  final now = DateTime.now().millisecondsSinceEpoch;

  // Heavy boilerplate test book
  db.execute(
    '''INSERT INTO books (id, title, author, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?)''',
    ['book_heavy', 'Heavy Boilerplate Test', 'Test Author', now, now],
  );

  final heavyChapters = [
    ('ch_heavy_1', 'Chapter 1', _getHeavyBoilerplateContent(1)),
    ('ch_heavy_2', 'Chapter 2', _getHeavyBoilerplateContent(2)),
    ('ch_heavy_3', 'Chapter 3', _getHeavyBoilerplateContent(3)),
  ];

  for (var i = 0; i < heavyChapters.length; i++) {
    final (id, title, content) = heavyChapters[i];
    db.execute(
      '''INSERT INTO chapters (id, book_id, number, title, content, created_at)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [id, 'book_heavy', i + 1, title, content, now],
    );
  }

  // Light boilerplate test book
  db.execute(
    '''INSERT INTO books (id, title, author, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?)''',
    ['book_light', 'Light Boilerplate Test', 'Test Author', now, now],
  );

  final lightChapters = [
    ('ch_light_1', 'Chapter 1', _getLightBoilerplateContent(1)),
    ('ch_light_2', 'Chapter 2', _getLightBoilerplateContent(2)),
    ('ch_light_3', 'Chapter 3', _getLightBoilerplateContent(3)),
  ];

  for (var i = 0; i < lightChapters.length; i++) {
    final (id, title, content) = lightChapters[i];
    db.execute(
      '''INSERT INTO chapters (id, book_id, number, title, content, created_at)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [id, 'book_light', i + 1, title, content, now],
    );
  }

  // Clean test book (no boilerplate)
  db.execute(
    '''INSERT INTO books (id, title, author, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?)''',
    ['book_clean', 'Clean Test Book', 'Test Author', now, now],
  );

  final cleanChapters = [
    ('ch_clean_1', 'Chapter 1', _getCleanContent(1)),
    ('ch_clean_2', 'Chapter 2', _getCleanContent(2)),
    ('ch_clean_3', 'Chapter 3', _getCleanContent(3)),
  ];

  for (var i = 0; i < cleanChapters.length; i++) {
    final (id, title, content) = cleanChapters[i];
    db.execute(
      '''INSERT INTO chapters (id, book_id, number, title, content, created_at)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [id, 'book_clean', i + 1, title, content, now],
    );
  }
}

String _getHeavyBoilerplateContent(int chapterNum) {
  return '''
e-text prepared by Project Gutenberg volunteers

HTML version created 2024

UTF-8 encoded

Transcribed by volunteers

Distributed under Creative Commons License

This work is in the public domain

Original pagination preserved

[Footnote: Additional editorial notes]

Chapter $chapterNum

This is chapter $chapterNum with actual story content. The narrative begins here and continues with meaningful plot progression.

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation.

The chapter continues with more substantial content that should definitely be preserved during processing.

End of Chapter $chapterNum
''';
}

String _getLightBoilerplateContent(int chapterNum) {
  return '''
Produced by Project Gutenberg volunteers

Chapter $chapterNum

The chapter begins with important narrative content. This is the heart of the text that readers care about.

Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.

More meaningful content continues here, advancing the story and developing characters.

Chapter $chapterNum concludes.
''';
}

String _getCleanContent(int chapterNum) {
  return '''
Chapter $chapterNum

The narrative opens with a compelling scene. The protagonist faces a challenging decision that will shape the rest of the story.

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.

Through careful dialogue and vivid description, the author develops the central conflict. Readers follow the character's journey with increasing investment in the outcome.

As Chapter $chapterNum concludes, new questions emerge that propel the narrative forward into the next chapter.
''';
}

void _printDatabaseStats(Database db) {
  final bookCount = db.select('SELECT COUNT(*) as count FROM books').first['count'];
  final chapterCount = db.select('SELECT COUNT(*) as count FROM chapters').first['count'];

  print('Database Statistics:');
  print('  Books: $bookCount');
  print('  Chapters: $chapterCount');

  final bookDetails = db.select('SELECT id, title, author FROM books');
  print('\n  Books:');
  for (final row in bookDetails) {
    final chapters = db.select(
      'SELECT COUNT(*) as count FROM chapters WHERE book_id = ?',
      [row['id']],
    ).first['count'];
    print('    - ${row['title']} ($chapters chapters)');
  }
}
