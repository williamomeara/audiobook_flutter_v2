import 'chapter.dart';

/// Reading progress within a book.
class BookProgress {
  const BookProgress({
    required this.chapterIndex,
    required this.segmentIndex,
  });

  /// Current chapter index (0-indexed).
  final int chapterIndex;

  /// Current segment index within the chapter (0-indexed).
  final int segmentIndex;

  static const zero = BookProgress(chapterIndex: 0, segmentIndex: 0);

  BookProgress copyWith({
    int? chapterIndex,
    int? segmentIndex,
  }) {
    return BookProgress(
      chapterIndex: chapterIndex ?? this.chapterIndex,
      segmentIndex: segmentIndex ?? this.segmentIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'chapterIndex': chapterIndex,
        'segmentIndex': segmentIndex,
      };

  factory BookProgress.fromJson(Map<String, dynamic> json) {
    return BookProgress(
      chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
      segmentIndex: (json['segmentIndex'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookProgress &&
          runtimeType == other.runtimeType &&
          chapterIndex == other.chapterIndex &&
          segmentIndex == other.segmentIndex;

  @override
  int get hashCode => Object.hash(chapterIndex, segmentIndex);

  @override
  String toString() =>
      'BookProgress(chapter: $chapterIndex, segment: $segmentIndex)';
}

/// Represents a book in the library.
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.addedAt,
    required this.chapters,
    this.progress = BookProgress.zero,
    this.completedChapters = const {},
    this.gutenbergId,
    this.coverImagePath,
    this.voiceId,
    this.isFavorite = false,
    this.firstContentChapter,
  });

  /// Unique identifier for this book.
  final String id;

  /// Book title.
  final String title;

  /// Author name.
  final String author;

  /// Path to the source file (EPUB/PDF).
  final String filePath;

  /// Timestamp when the book was added (milliseconds since epoch).
  final int addedAt;

  /// Project Gutenberg book ID, if imported from Gutenberg.
  final int? gutenbergId;

  /// Path to extracted cover image, if available.
  final String? coverImagePath;

  /// Voice ID override for this book (null = use global setting).
  final String? voiceId;

  /// List of chapters in the book.
  final List<Chapter> chapters;

  /// Current reading progress.
  final BookProgress progress;

  /// Set of chapter indices that have been completed (listened to >95%).
  final Set<int> completedChapters;

  /// Whether this book is marked as a favorite.
  final bool isFavorite;

  /// Index of the first chapter detected as actual content (not front matter).
  /// Used to offer "skip to content" functionality.
  final int? firstContentChapter;

  /// Calculate overall progress percentage (0-100).
  int get progressPercent {
    if (chapters.isEmpty) return 0;
    final totalSegments = chapters.fold<int>(0, (sum, ch) {
      // Estimate segments based on content length (roughly 500 chars per segment)
      return sum + ((ch.content.length / 500).ceil().clamp(1, 100));
    });
    if (totalSegments == 0) return 0;
    
    // Sum segments before current chapter
    var completedSegments = 0;
    for (var i = 0; i < progress.chapterIndex && i < chapters.length; i++) {
      completedSegments += (chapters[i].content.length / 500).ceil().clamp(1, 100);
    }
    // Add current segment progress
    completedSegments += progress.segmentIndex;
    
    return ((completedSegments / totalSegments) * 100).round().clamp(0, 100);
  }

  Book copyWith({
    String? id,
    String? title,
    String? author,
    String? filePath,
    int? addedAt,
    int? gutenbergId,
    String? coverImagePath,
    String? voiceId,
    List<Chapter>? chapters,
    BookProgress? progress,
    Set<int>? completedChapters,
    bool? isFavorite,
    int? firstContentChapter,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      filePath: filePath ?? this.filePath,
      addedAt: addedAt ?? this.addedAt,
      gutenbergId: gutenbergId ?? this.gutenbergId,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      voiceId: voiceId ?? this.voiceId,
      chapters: chapters ?? this.chapters,
      progress: progress ?? this.progress,
      completedChapters: completedChapters ?? this.completedChapters,
      isFavorite: isFavorite ?? this.isFavorite,
      firstContentChapter: firstContentChapter ?? this.firstContentChapter,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'filePath': filePath,
        'addedAt': addedAt,
        'gutenbergId': gutenbergId,
        'coverImagePath': coverImagePath,
        'voiceId': voiceId,
        'chapters': chapters.map((c) => c.toJson()).toList(growable: false),
        'progress': progress.toJson(),
        'completedChapters': completedChapters.toList(growable: false),
        'isFavorite': isFavorite,
        'firstContentChapter': firstContentChapter,
      };

  factory Book.fromJson(Map<String, dynamic> json) {
    final progressJson = (json['progress'] as Map?)?.cast<String, dynamic>() ?? const {};
    final progress = BookProgress.fromJson(progressJson);
    
    // Migration: if completedChapters is missing, mark chapters before current as complete
    Set<int> completedChapters;
    if (json.containsKey('completedChapters')) {
      completedChapters = (json['completedChapters'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toSet() ?? const {};
    } else {
      // Migrate old books: assume chapters before current position are complete
      completedChapters = {for (var i = 0; i < progress.chapterIndex; i++) i};
    }
    
    return Book(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      author: (json['author'] as String?) ?? 'Unknown author',
      filePath: (json['filePath'] as String?) ?? '',
      addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
      gutenbergId: (json['gutenbergId'] as num?)?.toInt(),
      coverImagePath: json['coverImagePath'] as String?,
      voiceId: json['voiceId'] as String?,
      chapters: (json['chapters'] as List<dynamic>? ?? const [])
          .map((c) => Chapter.fromJson(c as Map<String, dynamic>))
          .toList(growable: false),
      progress: progress,
      completedChapters: completedChapters,
      isFavorite: (json['isFavorite'] as bool?) ?? false,
      firstContentChapter: (json['firstContentChapter'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Book && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Book(id: $id, title: $title, author: $author)';
}
