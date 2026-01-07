import '../../utils/text_normalizer.dart';

/// Extracts plain text from HTML content, normalizing Unicode characters
/// for TTS-friendly output.
///
/// This function:
/// 1. Removes script, style, header, footer, and nav elements
/// 2. Converts block elements to newlines for proper paragraph separation
/// 3. Decodes HTML entities
/// 4. Normalizes problematic Unicode (smart quotes, em-dashes, etc.)
///
/// The normalization step is critical for AI TTS models which may
/// misinterpret curly quotes and smart apostrophes.
String stripHtmlToText(String html) {
  // 1. Remove non-content elements entirely
  var noScripts = html
      .replaceAll(
        RegExp(r'<script[\s\S]*?<\/script>', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'<style[\s\S]*?<\/style>', caseSensitive: false), ' ')
      .replaceAll(
        RegExp(r'<header[\s\S]*?<\/header>', caseSensitive: false),
        ' ',
      )
      .replaceAll(
        RegExp(r'<footer[\s\S]*?<\/footer>', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'<nav[\s\S]*?<\/nav>', caseSensitive: false), ' ');

  // 2. Convert block elements to newlines for paragraph separation
  final withNewlines = noScripts
      .replaceAll(
        RegExp(
          r'<(p|div|br|li|tr|h1|h2|h3|h4|h5|h6)[^>]*>',
          caseSensitive: false,
        ),
        '\n',
      )
      .replaceAll(
        RegExp(r'<\/(p|div|li|tr|h1|h2|h3|h4|h5|h6)>', caseSensitive: false),
        '\n',
      );

  // 3. Strip remaining HTML tags
  final noTags = withNewlines.replaceAll(RegExp(r'<[^>]+>'), ' ');

  // 4. Decode HTML entities (common ones)
  final decoded = noTags
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&#34;', '"')
      .replaceAll('&#x22;', '"')
      // Named quote entities (these produce Unicode that normalizer will fix)
      .replaceAll('&ldquo;', '"')
      .replaceAll('&rdquo;', '"')
      .replaceAll('&lsquo;', "'")
      .replaceAll('&rsquo;', "'")
      .replaceAll('&ndash;', '-')
      .replaceAll('&mdash;', ' - ')
      .replaceAll('&hellip;', '...')
      // Additional entities
      .replaceAll('&copy;', '(c)')
      .replaceAll('&reg;', '(R)')
      .replaceAll('&trade;', '(TM)')
      .replaceAll('&deg;', ' degrees')
      .replaceAll('&plusmn;', '+/-')
      // Numeric entities for common problematic chars
      .replaceAll(RegExp(r'&#8216;|&#x2018;'), "'") // '
      .replaceAll(RegExp(r'&#8217;|&#x2019;'), "'") // '
      .replaceAll(RegExp(r'&#8220;|&#x201C;'), '"') // "
      .replaceAll(RegExp(r'&#8221;|&#x201D;'), '"') // "
      .replaceAll(RegExp(r'&#8211;|&#x2013;'), '-') // –
      .replaceAll(RegExp(r'&#8212;|&#x2014;'), ' - ') // —
      .replaceAll(RegExp(r'&#8230;|&#x2026;'), '...'); // …

  // 5. Apply comprehensive Unicode normalization for TTS
  // This handles any remaining smart quotes, dashes, ligatures, etc.
  // that were encoded directly as Unicode rather than HTML entities
  final normalized = normalizeTextForTts(decoded);

  return normalized;
}
