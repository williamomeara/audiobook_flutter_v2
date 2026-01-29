class GutendexPage {
  const GutendexPage({
    required this.count,
    required this.next,
    required this.previous,
    required this.results,
  });

  final int count;
  final String? next;
  final String? previous;
  final List<GutendexBook> results;

  factory GutendexPage.fromJson(Map<String, dynamic> json) {
    final resultsJson = (json['results'] as List?) ?? const <dynamic>[];
    return GutendexPage(
      count: (json['count'] as num?)?.toInt() ?? 0,
      next: json['next'] as String?,
      previous: json['previous'] as String?,
      results: resultsJson
          .whereType<Map<String, dynamic>>()
          .map(GutendexBook.fromJson)
          .toList(growable: false),
    );
  }
}

class GutendexBook {
  const GutendexBook({
    required this.id,
    required this.title,
    required this.authors,
    required this.languages,
    required this.formats,
    required this.downloadCount,
  });

  final int id;
  final String title;
  final List<GutendexPerson> authors;
  final List<String> languages;
  final Map<String, String> formats;
  final int downloadCount;

  String get authorsDisplay {
    if (authors.isEmpty) return 'Unknown author';
    return authors.map((a) => a.name).where((n) => n.trim().isNotEmpty).join(', ');
  }

  String? get epubUrl {
    const preferred = 'application/epub+zip';
    if (formats.containsKey(preferred)) return formats[preferred];

    for (final entry in formats.entries) {
      final key = entry.key.toLowerCase();
      if (key.startsWith(preferred)) return entry.value;
    }
    return null;
  }

  String? get coverImageUrl {
    // Prefer explicit image mime types.
    if (formats.containsKey('image/jpeg')) return formats['image/jpeg'];
    if (formats.containsKey('image/png')) return formats['image/png'];

    // Fallback: any key that looks like an image.
    for (final entry in formats.entries) {
      final key = entry.key.toLowerCase();
      if (key.startsWith('image/') ||
          key.contains('cover') ||
          key.contains('jpg') ||
          key.contains('jpeg') ||
          key.contains('png') ||
          key.contains('webp')) {
        final v = entry.value;
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }

  factory GutendexBook.fromJson(Map<String, dynamic> json) {
    final authorsJson = (json['authors'] as List?) ?? const <dynamic>[];
    final languagesJson = (json['languages'] as List?) ?? const <dynamic>[];
    final formatsJson = (json['formats'] as Map?) ?? const <dynamic, dynamic>{};

    final formats = <String, String>{};
    for (final entry in formatsJson.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is String) {
        formats[key] = value;
      }
    }

    return GutendexBook(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?)?.trim() ?? '',
      authors: authorsJson
          .whereType<Map<String, dynamic>>()
          .map(GutendexPerson.fromJson)
          .toList(growable: false),
      languages: languagesJson
          .whereType<String>()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList(growable: false),
      formats: formats,
      downloadCount: (json['download_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class GutendexPerson {
  const GutendexPerson({
    required this.name,
    required this.birthYear,
    required this.deathYear,
    this.aliases = const [],
  });

  final String name;
  final int? birthYear;
  final int? deathYear;
  final List<String> aliases;

  factory GutendexPerson.fromJson(Map<String, dynamic> json) {
    final aliasesJson = (json['aliases'] as List?) ?? const <dynamic>[];
    return GutendexPerson(
      name: (json['name'] as String?)?.trim() ?? '',
      birthYear: (json['birth_year'] as num?)?.toInt(),
      deathYear: (json['death_year'] as num?)?.toInt(),
      aliases: aliasesJson
          .whereType<String>()
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toList(growable: false),
    );
  }
}
