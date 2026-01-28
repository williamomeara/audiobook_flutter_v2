import 'package:sqflite/sqflite.dart';

/// Data Access Object for books table.
///
/// Handles CRUD operations for the books library.
/// Voice is stored on the book (one voice per book design).
class BookDao {
  final Database _db;

  BookDao(this._db);

  /// Get all books ordered by last update.
  Future<List<Map<String, dynamic>>> getAllBooks() async {
    return await _db.query(
      'books',
      orderBy: 'updated_at DESC',
    );
  }

  /// Get a single book by ID.
  Future<Map<String, dynamic>?> getBook(String id) async {
    final results = await _db.query(
      'books',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isEmpty ? null : results.first;
  }

  /// Insert a new book.
  Future<void> insertBook(Map<String, dynamic> book) async {
    await _db.insert('books', book);
  }

  /// Update an existing book.
  Future<void> updateBook(String id, Map<String, dynamic> updates) async {
    updates['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'books',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a book (cascades to chapters, segments, progress, cache).
  Future<void> deleteBook(String id) async {
    await _db.delete(
      'books',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Update the voice for a book (used at first play or voice change).
  Future<void> updateVoice(String bookId, String voiceId) async {
    await _db.update(
      'books',
      {
        'voice_id': voiceId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  /// Toggle favorite status for a book.
  Future<void> toggleFavorite(String bookId) async {
    await _db.rawUpdate('''
      UPDATE books
      SET is_favorite = CASE WHEN is_favorite = 1 THEN 0 ELSE 1 END,
          updated_at = ?
      WHERE id = ?
    ''', [DateTime.now().millisecondsSinceEpoch, bookId]);
  }

  /// Get all favorite books.
  Future<List<Map<String, dynamic>>> getFavoriteBooks() async {
    return await _db.query(
      'books',
      where: 'is_favorite = 1',
      orderBy: 'updated_at DESC',
    );
  }

  /// Check if a book exists by ID.
  Future<bool> exists(String id) async {
    final result = await _db.rawQuery(
      'SELECT 1 FROM books WHERE id = ? LIMIT 1',
      [id],
    );
    return result.isNotEmpty;
  }

  /// Get book count.
  Future<int> count() async {
    final result = await _db.rawQuery('SELECT COUNT(*) as count FROM books');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
