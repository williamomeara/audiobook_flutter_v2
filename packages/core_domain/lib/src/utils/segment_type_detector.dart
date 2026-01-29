/// Utility for detecting the type of content in a text segment.
/// 
/// This is used during parsing to classify segments for type-aware
/// rendering and optional TTS skip behavior.
library;

import '../models/segment.dart';

/// Detects the type of a segment based on its text content.
/// 
/// The detection uses heuristic patterns to identify:
/// - Code blocks (programming syntax, template tags)
/// - Tables (structured data patterns)
/// - Figures (image references, captions)
/// - Headings (chapter/section markers)
/// - Quotes (block quotes)
class SegmentTypeDetector {
  const SegmentTypeDetector();

  /// Detect the segment type from text content.
  /// 
  /// Returns a [SegmentDetectionResult] containing the detected type,
  /// a confidence score (0.0-1.0), and optional metadata.
  SegmentDetectionResult detect(String text) {
    // Check for explicit markers first (highest priority)
    if (_hasCodeMarkers(text)) {
      return SegmentDetectionResult(
        type: SegmentType.code,
        confidence: 1.0,
        metadata: _extractCodeMetadata(text),
      );
    }
    
    if (_hasFigureMarkers(text)) {
      return SegmentDetectionResult(
        type: SegmentType.figure,
        confidence: 1.0,
        metadata: _extractFigureMetadata(text),
      );
    }
    
    // Check for heuristic patterns (lower confidence)
    final codeResult = _calculateCodeScore(text);
    if (codeResult.score >= 0.35) {  // Lowered threshold for better detection
      return SegmentDetectionResult(
        type: SegmentType.code,
        confidence: codeResult.score,
        metadata: {'detected': 'heuristic', 'language': codeResult.language},
      );
    }
    
    final tableScore = _calculateTableScore(text);
    if (tableScore >= 0.35) {  // Lowered threshold
      return SegmentDetectionResult(
        type: SegmentType.table,
        confidence: tableScore,
        metadata: {'detected': 'heuristic'},
      );
    }
    
    // Default to text
    return const SegmentDetectionResult(
      type: SegmentType.text,
      confidence: 1.0,
    );
  }
  
  /// Check for explicit [CODE] markers added during parsing.
  bool _hasCodeMarkers(String text) {
    return text.contains('[CODE]') || text.contains('[/CODE]');
  }
  
  /// Check for explicit [Figure:] markers added during parsing.
  bool _hasFigureMarkers(String text) {
    return RegExp(r'\[Figure:.*?\]', caseSensitive: false).hasMatch(text);
  }
  
  /// Extract code metadata from marked code block.
  Map<String, dynamic> _extractCodeMetadata(String text) {
    // Use the improved language detection from the score calculator
    final result = _calculateCodeScore(text);
    return {
      'language': result.language,
      'marked': true,
    };
  }
  
  /// Extract figure metadata from marker.
  Map<String, dynamic> _extractFigureMetadata(String text) {
    final match = RegExp(r'\[Figure:\s*(.*?)\]', caseSensitive: false).firstMatch(text);
    return {
      'caption': match?.group(1)?.trim() ?? '',
      'marked': true,
    };
  }
  
  /// Calculate a code likelihood score (0.0-1.0) based on heuristics.
  /// Returns both the score and detected language.
  ({double score, String language}) _calculateCodeScore(String text) {
    if (text.isEmpty) return (score: 0.0, language: 'plaintext');
    
    double score = 0.0;
    String detectedLang = 'plaintext';
    
    // Very strong indicators - these alone should trigger code detection
    // Django/Jinja template tags
    if (RegExp(r'\{%\s*\w+').hasMatch(text) || RegExp(r'\{\{[^}]+\}\}').hasMatch(text)) {
      score += 0.5;
      detectedLang = 'django';
    }
    
    // SQL keywords in combination
    if (RegExp(r'\b(SELECT|INSERT|UPDATE|DELETE)\b.*\b(FROM|INTO|SET|WHERE)\b', caseSensitive: false).hasMatch(text)) {
      score += 0.5;
      detectedLang = 'sql';
    }
    
    // Python def/class with colon
    if (RegExp(r'\b(def|class)\s+\w+.*:').hasMatch(text)) {
      score += 0.5;
      detectedLang = 'python';
    }
    
    // JavaScript/TypeScript const/let/var with assignment
    if (RegExp(r'\b(const|let|var)\s+\w+\s*=').hasMatch(text)) {
      score += 0.4;
      if (detectedLang == 'plaintext') detectedLang = 'javascript';
    }
    
    // Dart final/late with type or assignment
    if (RegExp(r'\b(final|late)\s+\w+').hasMatch(text) || text.contains('@override')) {
      score += 0.4;
      if (detectedLang == 'plaintext') detectedLang = 'dart';
    }
    
    // Arrow functions
    if (text.contains('=>')) {
      score += 0.3;
      if (detectedLang == 'plaintext') detectedLang = 'javascript';
    }
    
    // Shell commands at start of line
    if (RegExp(r'^(flutter|dart|npm|pip|git|apt|sudo)\s+\w+', multiLine: true).hasMatch(text)) {
      score += 0.5;
      if (detectedLang == 'plaintext') detectedLang = 'bash';
    }
    
    // Strong indicators (add to existing score)
    final strongPatterns = [
      // Function/method calls with parentheses
      RegExp(r'\w+\([^)]*\)'),
      // Assignment with type annotation
      RegExp(r'\w+:\s*\w+\s*='),
      // Curly braces with newlines (code blocks)
      RegExp(r'\{\s*\n|\n\s*\}'),
      // Import statements
      RegExp(r'^import\s+', multiLine: true),
      // Return statements
      RegExp(r'\breturn\s+'),
      // Common keywords
      RegExp(r'\b(function|async|await|try|catch|throw|new|this|self)\b'),
    ];
    
    for (final pattern in strongPatterns) {
      if (pattern.hasMatch(text)) {
        score += 0.15;
      }
    }
    
    // Medium indicators
    final mediumPatterns = [
      // Camel case identifiers  
      RegExp(r'\b[a-z]+[A-Z][a-zA-Z]*\b'),
      // Snake case identifiers
      RegExp(r'\b\w+_\w+\b'),
      // Semicolon line endings
      RegExp(r';\s*$', multiLine: true),
      // Method chaining
      RegExp(r'\.\w+\('),
      // Comments
      RegExp(r'(//|#)\s*\w+'),
    ];
    
    for (final pattern in mediumPatterns) {
      if (pattern.hasMatch(text)) {
        score += 0.08;
      }
    }
    
    // Symbol density check
    final codeSymbols = RegExp(r'[{}\[\]()<>;=]');
    final symbolCount = codeSymbols.allMatches(text).length;
    final symbolDensity = text.isNotEmpty ? symbolCount / text.length : 0;
    if (symbolDensity > 0.06) {
      score += 0.15;
    }
    
    // Multiple indented lines suggests code
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length >= 2) {
      final indentedLines = lines.where((l) => l.startsWith('  ') || l.startsWith('\t')).length;
      if (indentedLines >= 2 && indentedLines / lines.length > 0.3) {
        score += 0.2;
      }
    }
    
    return (score: score.clamp(0.0, 1.0), language: detectedLang);
  }
  
  /// Calculate a table likelihood score (0.0-1.0) based on heuristics.
  double _calculateTableScore(String text) {
    if (text.isEmpty) return 0.0;
    
    double score = 0.0;
    
    // Pipe-separated values (Markdown tables)
    if (RegExp(r'\|.*\|.*\|').hasMatch(text)) {
      score += 0.4;
    }
    
    // Tab-separated values with multiple columns
    final lines = text.split('\n');
    final tabLines = lines.where((l) => l.contains('\t') && l.split('\t').length >= 3).length;
    if (tabLines >= 2) {
      score += 0.3;
    }
    
    // Consistent spacing patterns (columns)
    if (lines.length >= 3) {
      final hasConsistentSpacing = _hasConsistentColumnSpacing(lines);
      if (hasConsistentSpacing) {
        score += 0.3;
      }
    }
    
    return score.clamp(0.0, 1.0);
  }
  
  /// Check if lines have consistent column-like spacing.
  bool _hasConsistentColumnSpacing(List<String> lines) {
    if (lines.length < 3) return false;
    
    // Look for multiple spaces appearing at similar positions
    final spacePositions = <int>[];
    for (final line in lines) {
      for (var i = 0; i < line.length - 1; i++) {
        if (line[i] == ' ' && line[i + 1] == ' ') {
          spacePositions.add(i);
        }
      }
    }
    
    // If we have many double-spaces at consistent positions, it's likely a table
    return spacePositions.length >= lines.length * 2;
  }
}

/// Result of segment type detection.
class SegmentDetectionResult {
  const SegmentDetectionResult({
    required this.type,
    required this.confidence,
    this.metadata,
  });
  
  /// The detected segment type.
  final SegmentType type;
  
  /// Confidence score (0.0-1.0) of the detection.
  final double confidence;
  
  /// Optional metadata extracted during detection.
  final Map<String, dynamic>? metadata;
  
  @override
  String toString() => 'SegmentDetectionResult(type: $type, confidence: $confidence)';
}
