/// Compression state of a cache entry.
enum CompressionState {
  wav,        // Uncompressed WAV file
  compressing, // Compression in progress
  m4a,        // Compressed M4A file
  failed,     // Compression failed (keep original WAV)
}

/// Metadata for a cache entry used in intelligent eviction.
class CacheEntryMetadata {
  CacheEntryMetadata({
    required this.key,
    required this.sizeBytes,
    required this.createdAt,
    required this.lastAccessed,
    required this.accessCount,
    required this.bookId,
    required this.voiceId,
    required this.segmentIndex,
    required this.chapterIndex,
    required this.engineType,
    required this.audioDurationMs,
    this.compressionState = CompressionState.wav,
    this.compressionStartedAt,
  });

  /// Cache key (voiceId_rate_hash)
  final String key;

  /// File size in bytes.
  final int sizeBytes;

  /// Compression state of this entry.
  final CompressionState compressionState;

  /// When compression was started (null if not compressing).
  final DateTime? compressionStartedAt;

  /// When the entry was first created.
  final DateTime createdAt;

  /// When the entry was last accessed.
  DateTime lastAccessed;

  /// Number of times this entry has been accessed.
  int accessCount;

  /// Book this segment belongs to.
  final String bookId;

  /// Voice used for synthesis.
  final String voiceId;

  /// Segment index within the chapter.
  final int segmentIndex;

  /// Chapter index within the book.
  final int chapterIndex;

  /// TTS engine used (supertonic, piper, kokoro).
  final String engineType;

  /// Duration of the audio in milliseconds.
  final int audioDurationMs;

  /// Create from JSON (for persistence).
  factory CacheEntryMetadata.fromJson(Map<String, dynamic> json) {
    return CacheEntryMetadata(
      key: json['key'] as String,
      sizeBytes: json['sizeBytes'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastAccessed: DateTime.parse(json['lastAccessed'] as String),
      accessCount: json['accessCount'] as int,
      bookId: json['bookId'] as String,
      voiceId: json['voiceId'] as String,
      segmentIndex: json['segmentIndex'] as int,
      chapterIndex: json['chapterIndex'] as int,
      engineType: json['engineType'] as String,
      audioDurationMs: json['audioDurationMs'] as int,
      compressionState: _parseCompressionState(json['compressionState'] as String?),
      compressionStartedAt: json['compressionStartedAt'] != null
          ? DateTime.parse(json['compressionStartedAt'] as String)
          : null,
    );
  }

  static CompressionState _parseCompressionState(String? value) {
    if (value == null) return CompressionState.wav;
    return CompressionState.values.firstWhere(
      (s) => s.toString() == 'CompressionState.$value',
      orElse: () => CompressionState.wav,
    );
  }


  /// Convert to JSON for persistence.
  Map<String, dynamic> toJson() => {
        'key': key,
        'sizeBytes': sizeBytes,
        'createdAt': createdAt.toIso8601String(),
        'lastAccessed': lastAccessed.toIso8601String(),
        'accessCount': accessCount,
        'bookId': bookId,
        'voiceId': voiceId,
        'segmentIndex': segmentIndex,
        'chapterIndex': chapterIndex,
        'engineType': engineType,
        'audioDurationMs': audioDurationMs,
        'compressionState': compressionState.name,
        'compressionStartedAt': compressionStartedAt?.toIso8601String(),
      };

  CacheEntryMetadata copyWith({
    DateTime? lastAccessed,
    int? accessCount,
    CompressionState? compressionState,
    DateTime? compressionStartedAt,
  }) =>
      CacheEntryMetadata(
        key: key,
        sizeBytes: sizeBytes,
        createdAt: createdAt,
        lastAccessed: lastAccessed ?? this.lastAccessed,
        accessCount: accessCount ?? this.accessCount,
        bookId: bookId,
        voiceId: voiceId,
        segmentIndex: segmentIndex,
        chapterIndex: chapterIndex,
        engineType: engineType,
        audioDurationMs: audioDurationMs,
        compressionState: compressionState ?? this.compressionState,
        compressionStartedAt: compressionStartedAt ?? this.compressionStartedAt,
      );
}

/// Context for calculating eviction scores.
class EvictionContext {
  const EvictionContext({
    required this.currentVoiceId,
    required this.activeBookIds,
    required this.bookReadingPositions,
    required this.bookProgress,
    required this.maxAccessCount,
  });

  /// Currently selected voice ID.
  final String currentVoiceId;

  /// Book IDs that are currently "active" (recently opened).
  final Set<String> activeBookIds;

  /// Current reading position (segment index) per book.
  final Map<String, int> bookReadingPositions;

  /// Reading progress (0.0-1.0) per book.
  final Map<String, double> bookProgress;

  /// Maximum access count across all entries (for normalization).
  final int maxAccessCount;
}

/// Calculator for intelligent cache eviction scores.
///
/// Higher scores = more valuable = evict last.
/// Lower scores = less valuable = evict first.
class EvictionScoreCalculator {
  const EvictionScoreCalculator();

  /// Weight factors for score calculation.
  static const double recencyWeight = 0.30;
  static const double frequencyWeight = 0.20;
  static const double readingPositionWeight = 0.30;
  static const double bookProgressWeight = 0.15;
  static const double voiceMatchWeight = 0.05;

  /// Calculate the eviction score for an entry.
  /// 
  /// Returns a value from 0.0 (evict first) to 1.0 (evict last).
  double calculateScore(
    CacheEntryMetadata entry,
    EvictionContext context,
  ) {
    final recency = _recencyScore(entry);
    final frequency = _frequencyScore(entry, context.maxAccessCount);
    final position = _readingPositionScore(entry, context);
    final progress = _bookProgressScore(entry, context);
    final voice = _voiceMatchScore(entry, context);

    return recency * recencyWeight +
        frequency * frequencyWeight +
        position * readingPositionWeight +
        progress * bookProgressWeight +
        voice * voiceMatchWeight;
  }

  /// Recency score: how recently was this entry accessed?
  /// Decay curve: 50% value at 24 hours, 10% at 7 days.
  double _recencyScore(CacheEntryMetadata entry) {
    final hoursSinceAccess =
        DateTime.now().difference(entry.lastAccessed).inHours.toDouble();

    // Exponential decay with 48-hour half-life
    return _exp(-hoursSinceAccess / 48.0);
  }

  /// Frequency score: how often has this entry been accessed?
  double _frequencyScore(CacheEntryMetadata entry, int maxAccessCount) {
    if (maxAccessCount <= 0) return 0.5;
    return (entry.accessCount / maxAccessCount).clamp(0.0, 1.0);
  }

  /// Reading position score: is this near the current reading position?
  double _readingPositionScore(
    CacheEntryMetadata entry,
    EvictionContext context,
  ) {
    final readingPosition = context.bookReadingPositions[entry.bookId];
    if (readingPosition == null) return 0.0;

    final segmentDistance = (entry.segmentIndex - readingPosition).abs();

    // Segments ahead are more valuable than segments behind
    if (entry.segmentIndex >= readingPosition) {
      // Ahead: high value, slow decay (keep next 20 segments hot)
      return _exp(-segmentDistance / 20.0);
    } else {
      // Behind: lower value, faster decay
      return _exp(-segmentDistance / 5.0) * 0.5;
    }
  }

  /// Book progress score: books in-progress are more valuable.
  /// Bell curve: 50% progress = highest value.
  double _bookProgressScore(
    CacheEntryMetadata entry,
    EvictionContext context,
  ) {
    final progress = context.bookProgress[entry.bookId] ?? 0.0;

    // Bell curve peaking at 50% progress
    return 4.0 * progress * (1.0 - progress);
  }

  /// Voice match score: current voice cache is more valuable.
  double _voiceMatchScore(
    CacheEntryMetadata entry,
    EvictionContext context,
  ) {
    return entry.voiceId == context.currentVoiceId ? 1.0 : 0.0;
  }

  /// Helper for exponential function (dart:math.exp).
  double _exp(double x) {
    // Simple approximation that's good enough for our purposes
    // exp(-x) for x >= 0 returns values from 1 to 0
    if (x >= 0) return 1.0;
    if (x <= -10) return 0.0;
    
    // Taylor series approximation
    var result = 1.0;
    var term = 1.0;
    for (var i = 1; i <= 10; i++) {
      term *= x / i;
      result += term;
    }
    return result.clamp(0.0, 1.0);
  }
}

/// Entry with calculated eviction score.
class ScoredCacheEntry {
  const ScoredCacheEntry({
    required this.metadata,
    required this.score,
  });

  final CacheEntryMetadata metadata;
  final double score;
}

/// Extension to sort entries by eviction priority.
extension CacheEntrySorting on List<ScoredCacheEntry> {
  /// Sort by score ascending (lowest score = evict first).
  void sortByEvictionPriority() {
    sort((a, b) => a.score.compareTo(b.score));
  }
}
