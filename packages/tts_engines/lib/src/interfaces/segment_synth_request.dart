import 'dart:io';

import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Extended synthesis request with cancellation and retry support.
class SegmentSynthRequest {
  SegmentSynthRequest({
    required this.segmentId,
    required this.normalizedText,
    required this.voiceId,
    required this.outputFile,
    String? opId,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 1,
    this.speakerId,
    this.playbackRate = 1.0,
  }) : opId = opId ?? _generateOpId();

  /// Unique operation ID for cancellation.
  final String opId;

  /// Segment identifier.
  final String segmentId;

  /// Normalized text to synthesize.
  final String normalizedText;

  /// Voice identifier.
  final String voiceId;

  /// Output file path for WAV.
  final File outputFile;

  /// Timeout for synthesis operation.
  final Duration timeout;

  /// Maximum retry attempts.
  final int maxRetries;

  /// Engine-specific speaker ID (for Kokoro).
  final int? speakerId;

  /// Playback rate (1.0 = normal).
  final double playbackRate;

  /// Current retry attempt (mutable for retry logic).
  int retryAttempt = 0;

  /// Whether this request has been cancelled.
  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  /// Cancel this request.
  void cancel() {
    _cancelled = true;
  }

  /// Generate cache key for this request.
  String get cacheKey {
    final textHash = _hashText(normalizedText);
    final rateStr = playbackRate.toStringAsFixed(2).replaceAll('.', '_');
    return '${voiceId}_${rateStr}_$textHash';
  }

  /// Check if retry is allowed.
  bool get canRetry => retryAttempt < maxRetries;

  /// Increment retry counter and return whether retry is allowed.
  bool incrementRetry() {
    retryAttempt++;
    return canRetry;
  }

  @override
  String toString() =>
      'SegmentSynthRequest(id: $segmentId, voice: $voiceId, textLen: ${normalizedText.length})';

  static String _generateOpId() {
    final now = DateTime.now();
    final random = now.microsecondsSinceEpoch.toRadixString(36);
    return 'op_$random';
  }

  static String _hashText(String text) {
    final bytes = utf8.encode(text);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }
}

/// Batch synthesis request for multiple segments.
class BatchSynthRequest {
  BatchSynthRequest({
    required this.segments,
    this.priority = 0,
    this.onProgress,
  });

  /// List of segment requests.
  final List<SegmentSynthRequest> segments;

  /// Priority (higher = more urgent).
  final int priority;

  /// Progress callback (completed / total).
  final void Function(int completed, int total)? onProgress;

  /// Cancel all segments.
  void cancelAll() {
    for (final segment in segments) {
      segment.cancel();
    }
  }

  /// Get number of pending segments.
  int get pendingCount => segments.where((s) => !s.isCancelled).length;
}
