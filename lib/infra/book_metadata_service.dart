import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service for looking up book metadata from external APIs.
///
/// Currently uses Google Books API for reliable book information.
class BookMetadataService {
  static const String _googleBooksBaseUrl = 'https://www.googleapis.com/books/v1/volumes';

  /// Search for a book by title and author.
  ///
  /// Returns the best matching volume info, or null if no good match found.
  Future<BookVolumeInfo?> searchBook(String title, String author) async {
    if (title.trim().isEmpty) return null;

    // Clean up the title (remove extra stuff like (Z-Library))
    final cleanTitle = _cleanTitle(title);
    final cleanAuthor = _cleanAuthor(author);

    // Build search query
    final query = _buildSearchQuery(cleanTitle, cleanAuthor);

    try {
      final response = await http.get(Uri.parse('$_googleBooksBaseUrl?q=$query'));

      if (response.statusCode != 200) {
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>?;

      if (items == null || items.isEmpty) {
        return null;
      }

      // Find the best match
      return _findBestMatch(items, cleanTitle, cleanAuthor);
    } catch (e) {
      // Silently fail on network errors
      return null;
    }
  }

  String _cleanTitle(String title) {
    // Remove common suffixes like (Z-Library), [PDF], etc.
    return title
        .replaceAll(RegExp(r'\s*\([^)]*(?:z-library|pdf|epub|kindle)[^)]*\)\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[[^\]]*(?:pdf|epub|kindle)[^\]]*\]\s*', caseSensitive: false), '')
        .trim();
  }

  String _cleanAuthor(String author) {
    // Remove unknown author placeholders
    if (author.toLowerCase().contains('unknown')) {
      return '';
    }
    return author.trim();
  }

  String _buildSearchQuery(String title, String author) {
    final parts = <String>[];

    // Add title
    parts.add('intitle:${Uri.encodeComponent(title)}');

    // Add author if available
    if (author.isNotEmpty) {
      parts.add('inauthor:${Uri.encodeComponent(author)}');
    }

    return parts.join('+');
  }

  BookVolumeInfo? _findBestMatch(List<dynamic> items, String targetTitle, String targetAuthor) {
    BookVolumeInfo? bestMatch;
    double bestScore = 0.0;

    for (final item in items) {
      final volumeInfo = BookVolumeInfo.fromJson(item['volumeInfo'] as Map<String, dynamic>);
      final score = _calculateMatchScore(volumeInfo, targetTitle, targetAuthor);

      if (score > bestScore && score > 0.7) { // Require 70% match confidence
        bestMatch = volumeInfo;
        bestScore = score;
      }
    }

    return bestMatch;
  }

  /// Calculate confidence score for a metadata result against target title/author.
  /// Returns 0.0 to 1.0, where 1.0 is perfect match.
  double calculateConfidence(BookVolumeInfo metadata, String targetTitle, String targetAuthor) {
    return _calculateMatchScore(metadata, targetTitle, targetAuthor);
  }

  double _calculateMatchScore(BookVolumeInfo volumeInfo, String targetTitle, String targetAuthor) {
    double score = 0.0;

    // Title similarity (case-insensitive substring match)
    final titleMatch = volumeInfo.title.toLowerCase().contains(targetTitle.toLowerCase()) ||
                      targetTitle.toLowerCase().contains(volumeInfo.title.toLowerCase());
    if (titleMatch) score += 0.6;

    // Author match
    if (targetAuthor.isNotEmpty && volumeInfo.authors.isNotEmpty) {
      final authorMatch = volumeInfo.authors.any((a) =>
        a.toLowerCase().contains(targetAuthor.toLowerCase()) ||
        targetAuthor.toLowerCase().contains(a.toLowerCase())
      );
      if (authorMatch) score += 0.4;
    } else if (targetAuthor.isEmpty) {
      // If no target author, still give some credit
      score += 0.2;
    }

    return score;
  }
}

/// Represents volume information from Google Books API.
class BookVolumeInfo {
  const BookVolumeInfo({
    required this.title,
    required this.authors,
    required this.description,
    required this.publishedDate,
    required this.pageCount,
    required this.categories,
    required this.imageLinks,
  });

  final String title;
  final List<String> authors;
  final String? description;
  final String? publishedDate;
  final int? pageCount;
  final List<String> categories;
  final Map<String, String> imageLinks;

  String get authorsDisplay => authors.isEmpty ? 'Unknown author' : authors.join(', ');

  String? get thumbnailUrl => imageLinks['thumbnail'];

  factory BookVolumeInfo.fromJson(Map<String, dynamic> json) {
    return BookVolumeInfo(
      title: (json['title'] as String?) ?? '',
      authors: (json['authors'] as List<dynamic>?)?.map((a) => a as String).toList() ?? const [],
      description: json['description'] as String?,
      publishedDate: json['publishedDate'] as String?,
      pageCount: (json['pageCount'] as num?)?.toInt(),
      categories: (json['categories'] as List<dynamic>?)?.map((c) => c as String).toList() ?? const [],
      imageLinks: (json['imageLinks'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v as String)) ?? const {},
    );
  }
}