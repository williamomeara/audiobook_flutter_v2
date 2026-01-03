/// Text normalization utilities for consistent TTS synthesis.
///
/// Normalization ensures that the same text produces the same cache key
/// regardless of minor whitespace or formatting differences.
class TextNormalizer {
  TextNormalizer._();

  /// Normalize text for synthesis.
  ///
  /// This function:
  /// - Trims leading/trailing whitespace
  /// - Collapses multiple whitespace to single spaces
  /// - Normalizes common punctuation
  static String normalize(String text) {
    if (text.isEmpty) return '';

    var result = text
        // Normalize line breaks to spaces
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        // Collapse multiple spaces to one
        .replaceAll(RegExp(r'\s+'), ' ')
        // Normalize quotes
        .replaceAll(RegExp(r'["""]'), '"')
        .replaceAll(RegExp(r"[''']"), "'")
        // Normalize dashes
        .replaceAll(RegExp(r'[–—]'), '-')
        // Normalize ellipsis
        .replaceAll('…', '...')
        // Trim
        .trim();

    return result;
  }

  /// Normalize text specifically for cache key generation.
  ///
  /// More aggressive normalization to maximize cache hits.
  static String normalizeForCache(String text) {
    if (text.isEmpty) return '';

    return text
        // Convert to lowercase for cache matching
        .toLowerCase()
        // Remove all whitespace variations
        .replaceAll(RegExp(r'\s+'), ' ')
        // Normalize quotes - use Unicode escapes to avoid string issues
        .replaceAll(RegExp('[\u201c\u201d\u201e\u0022\u2018\u2019\u201a\u0027]'), '')
        // Remove punctuation that doesn't affect speech
        .replaceAll(RegExp(r'[^\w\s.,!?;:\-]'), '')
        .trim();
  }
}
