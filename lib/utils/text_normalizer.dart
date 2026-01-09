/// Normalizes text for TTS consumption.
///
/// Handles typography issues that can cause poor TTS output:
/// - HTML entities → decoded characters
/// - Smart/curly quotes → straight quotes
/// - Em/en dashes → hyphens with spaces
/// - Unicode ligatures → expanded characters
/// - Various space types → regular spaces
/// - Special symbols → TTS-friendly alternatives
class TextNormalizer {
  // Single quote variants (curly, reversed, backtick, acute)
  static final _singleQuotePattern =
      RegExp(r'[\u2018\u2019\u201A\u201B\u0060\u00B4]');

  // Double quote variants (curly, low-9, reversed, guillemets)
  static final _doubleQuotePattern =
      RegExp(r'[\u201C\u201D\u201E\u201F\u00AB\u00BB]');

  // Dash variants (en-dash, hyphen, non-breaking hyphen, minus)
  static final _dashPattern = RegExp(r'[\u2013\u2010\u2011\u2212]');

  // Zero-width characters (space, joiner, non-joiner, BOM)
  static final _zeroWidthPattern = RegExp(r'[\u200B\u200C\u200D\uFEFF]');

  // Various space types (non-breaking, thin, hair, en, em, figure, narrow)
  static final _spacePattern =
      RegExp(r'[\u00A0\u202F\u2009\u200A\u2002\u2003\u2007]');

  // Numeric HTML entities pattern
  static final _numericEntityPattern = RegExp(r'&#x?([0-9a-fA-F]+);');

  /// Main entry point - applies all normalizations in order.
  ///
  /// The order matters:
  /// 1. HTML entities first (decode before other normalizations)
  /// 2. Quotes (simple replacements)
  /// 3. Dashes (includes em-dash with special spacing)
  /// 4. Ellipsis
  /// 5. Ligatures
  /// 6. Spaces (including zero-width removal)
  /// 7. Symbols
  /// 8. Whitespace cleanup (last, to fix any introduced issues)
  static String normalize(String text) {
    if (text.isEmpty) return text;

    var result = text;

    result = decodeHtmlEntities(result);
    result = normalizeQuotes(result);
    result = normalizeDashes(result);
    result = normalizeEllipsis(result);
    result = normalizeLigatures(result);
    result = normalizeSpaces(result);
    result = normalizeSymbols(result);
    result = cleanWhitespace(result);

    return result;
  }

  /// Decodes HTML entities to their character equivalents.
  ///
  /// Handles both named entities (&amp;) and numeric entities (&#39; &#x27;)
  static String decodeHtmlEntities(String text) {
    var result = text;

    // Named entities
    result = result
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&mdash;', '\u2014')
        .replaceAll('&ndash;', '\u2013')
        .replaceAll('&hellip;', '\u2026')
        .replaceAll('&lsquo;', '\u2018')
        .replaceAll('&rsquo;', '\u2019')
        .replaceAll('&ldquo;', '\u201C')
        .replaceAll('&rdquo;', '\u201D')
        .replaceAll('&laquo;', '\u00AB')
        .replaceAll('&raquo;', '\u00BB')
        .replaceAll('&copy;', '\u00A9')
        .replaceAll('&reg;', '\u00AE')
        .replaceAll('&trade;', '\u2122')
        .replaceAll('&bull;', '\u2022')
        .replaceAll('&middot;', '\u00B7')
        .replaceAll('&frac12;', '\u00BD')
        .replaceAll('&frac14;', '\u00BC')
        .replaceAll('&frac34;', '\u00BE');

    // Numeric entities (decimal and hex)
    result = result.replaceAllMapped(_numericEntityPattern, (match) {
      final value = match.group(1)!;
      final isHex = match.group(0)!.contains('x');
      final codePoint = int.tryParse(value, radix: isHex ? 16 : 10);
      if (codePoint != null && codePoint > 0 && codePoint <= 0x10FFFF) {
        return String.fromCharCode(codePoint);
      }
      return match.group(0)!; // Return original if invalid
    });

    return result;
  }

  /// Converts all curly/smart quotes to straight quotes.
  ///
  /// Single quotes: ' ' ‚ ‛ ` ´ → '
  /// Double quotes: " " „ ‟ « » → "
  static String normalizeQuotes(String text) {
    var result = text.replaceAll(_singleQuotePattern, "'");
    return result.replaceAll(_doubleQuotePattern, '"');
  }

  /// Normalizes various dash types to ASCII hyphen.
  ///
  /// Em-dash (—) gets spaces around it for natural TTS pacing.
  /// Other dashes (–, ‐, ‑, −) become simple hyphens.
  static String normalizeDashes(String text) {
    // Em-dash with spaces for natural TTS pause
    var result = text.replaceAll('\u2014', ' - ');
    // Other dashes to simple hyphen
    return result.replaceAll(_dashPattern, '-');
  }

  /// Expands Unicode ellipsis to three periods.
  ///
  /// … → ...
  static String normalizeEllipsis(String text) {
    return text.replaceAll('\u2026', '...');
  }

  /// Expands typographic ligatures to their component letters.
  ///
  /// Common ligatures:
  /// - ﬁ → fi, ﬂ → fl, ﬀ → ff, ﬃ → ffi, ﬄ → ffl
  /// - Œ → OE, œ → oe, Æ → AE, æ → ae
  static String normalizeLigatures(String text) {
    return text
        .replaceAll('\uFB01', 'fi')
        .replaceAll('\uFB02', 'fl')
        .replaceAll('\uFB00', 'ff')
        .replaceAll('\uFB03', 'ffi')
        .replaceAll('\uFB04', 'ffl')
        .replaceAll('\uFB05', 'st')
        .replaceAll('\uFB06', 'st')
        .replaceAll('\u0152', 'OE')
        .replaceAll('\u0153', 'oe')
        .replaceAll('\u00C6', 'AE')
        .replaceAll('\u00E6', 'ae');
  }

  /// Normalizes various space types to regular ASCII space.
  ///
  /// Also removes zero-width characters that can cause issues.
  static String normalizeSpaces(String text) {
    // Remove zero-width characters first
    var result = text.replaceAll(_zeroWidthPattern, '');
    // Normalize various spaces to regular space
    return result.replaceAll(_spacePattern, ' ');
  }

  /// Converts special symbols to TTS-friendly text.
  ///
  /// Fractions: ½ → 1/2, ¼ → 1/4, ¾ → 3/4
  /// Legal: © → (c), ® → (R), ™ → (TM)
  /// Other: № → No., • → *, · → .
  static String normalizeSymbols(String text) {
    return text
        // Fractions
        .replaceAll('\u00BD', '1/2')
        .replaceAll('\u00BC', '1/4')
        .replaceAll('\u00BE', '3/4')
        .replaceAll('\u2153', '1/3')
        .replaceAll('\u2154', '2/3')
        // Legal symbols
        .replaceAll('\u00A9', '(c)')
        .replaceAll('\u00AE', '(R)')
        .replaceAll('\u2122', '(TM)')
        // Numero
        .replaceAll('\u2116', 'No.')
        // Bullets and dots
        .replaceAll('\u2022', '*')
        .replaceAll('\u2023', '*')
        .replaceAll('\u2043', '-')
        .replaceAll('\u00B7', '.');
  }

  /// Cleans up whitespace issues.
  ///
  /// - Collapses multiple consecutive spaces to single space
  /// - Collapses 3+ newlines to double newline (preserves paragraph breaks)
  /// - Trims leading/trailing whitespace
  static String cleanWhitespace(String text) {
    // Collapse multiple spaces
    var result = text.replaceAll(RegExp(r' {2,}'), ' ');
    // Collapse 3+ newlines to paragraph break
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return result.trim();
  }
}
