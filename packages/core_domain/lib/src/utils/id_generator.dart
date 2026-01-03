import 'dart:math';

/// Generates unique identifiers.
class IdGenerator {
  IdGenerator._();

  static final _random = Random.secure();

  /// Characters used in generated IDs.
  static const _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';

  /// Generate a random ID of specified length.
  static String generate({int length = 12}) {
    return List.generate(
      length,
      (_) => _chars[_random.nextInt(_chars.length)],
    ).join();
  }

  /// Generate an ID with a prefix and timestamp for better debugging.
  static String generatePrefixed(String prefix) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomPart = generate(length: 6);
    return '${prefix}_${timestamp}_$randomPart';
  }

  /// Generate a book ID.
  static String generateBookId() => generatePrefixed('book');

  /// Generate a chapter ID.
  static String generateChapterId(String bookId, int chapterNumber) =>
      '${bookId}_ch_$chapterNumber';

  /// Generate an audio track ID.
  static String audioTrackId(String bookId, int chapterIndex, int segmentIndex) =>
      '${bookId}_ch${chapterIndex}_seg$segmentIndex';
}

/// Convenience function to generate an ID.
String generateId({int length = 12}) => IdGenerator.generate(length: length);
