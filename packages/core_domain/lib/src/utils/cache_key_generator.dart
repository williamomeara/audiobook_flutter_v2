import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../models/cache_key.dart';
import 'text_normalizer.dart';

/// Generates stable cache keys for audio synthesis results.
class CacheKeyGenerator {
  CacheKeyGenerator._();

  /// Whether to use rate-independent synthesis.
  ///
  /// When true, synthesis is always done at 1.0x speed and playback
  /// rate is adjusted in the audio player. This maximizes cache hits.
  static const bool rateIndependentSynthesis = true;

  /// Generate a cache key for given parameters.
  static CacheKey generate({
    required String voiceId,
    required String text,
    required double playbackRate,
  }) {
    final normalizedText = TextNormalizer.normalizeForCache(text);
    final textHash = _hashText(normalizedText);
    final synthesisRate = rateIndependentSynthesis ? 1.0 : playbackRate;

    return CacheKey(
      voiceId: voiceId,
      textHash: textHash,
      synthesisRate: synthesisRate,
    );
  }

  /// Generate a stable hash for text content.
  ///
  /// Uses SHA-256 truncated to 16 characters for reasonable uniqueness
  /// while keeping filenames manageable.
  static String _hashText(String text) {
    final bytes = utf8.encode(text);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  /// Get the effective synthesis rate.
  static double getSynthesisRate(double playbackRate) {
    return rateIndependentSynthesis ? 1.0 : playbackRate;
  }
}
