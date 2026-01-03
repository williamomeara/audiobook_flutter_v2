/// Represents a chapter in a book.
class Chapter {
  const Chapter({
    required this.id,
    required this.number,
    required this.title,
    required this.content,
  });

  /// Unique identifier for this chapter.
  final String id;

  /// Chapter number (1-indexed).
  final int number;

  /// Display title.
  final String title;

  /// Full text content of the chapter.
  final String content;

  Chapter copyWith({
    String? id,
    int? number,
    String? title,
    String? content,
  }) {
    return Chapter(
      id: id ?? this.id,
      number: number ?? this.number,
      title: title ?? this.title,
      content: content ?? this.content,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'title': title,
        'content': content,
      };

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      id: json['id'] as String,
      number: (json['number'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Chapter &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          number == other.number &&
          title == other.title &&
          content == other.content;

  @override
  int get hashCode => Object.hash(id, number, title, content);

  @override
  String toString() => 'Chapter(id: $id, number: $number, title: $title)';
}
