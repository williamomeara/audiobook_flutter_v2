/// Real-time buffer status for UI display.
///
/// Provides information about the synthesis buffer so the UI can:
/// - Show buffer level indicator during playback
/// - Display "Buffer: Xs ahead" text
/// - Show warnings when buffer is low
/// - Indicate when synthesis is actively building buffer
///
/// This is purely informational - it never blocks playback.
class BufferStatus {
  /// Amount of audio buffered ahead of playback position (in seconds).
  final double bufferSeconds;

  /// Current playback rate (1.0 = normal, 2.0 = 2x speed).
  final double playbackRate;

  /// Effective buffer considering playback rate.
  /// At 2x playback, 30s of audio = 15s of real time.
  double get effectiveBufferSeconds => bufferSeconds / playbackRate;

  /// Whether synthesis is currently active (building buffer).
  final bool isSynthesizing;

  /// Number of segments currently being synthesized.
  final int activeSynthesisCount;

  /// Timestamp when this status was captured.
  final DateTime timestamp;

  const BufferStatus({
    required this.bufferSeconds,
    required this.playbackRate,
    required this.isSynthesizing,
    this.activeSynthesisCount = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? const _ConstantDateTime();

  /// Empty buffer status (initial state).
  static const empty = BufferStatus(
    bufferSeconds: 0,
    playbackRate: 1.0,
    isSynthesizing: false,
  );

  /// Buffer level as a normalized value (0.0 - 1.0).
  /// Based on target buffer of 60 seconds.
  double get normalizedLevel => (effectiveBufferSeconds / 60.0).clamp(0.0, 1.0);

  /// User-friendly buffer description.
  String get displayText {
    final secs = effectiveBufferSeconds.round();
    if (secs < 5) return 'Buffer: Low';
    if (secs < 15) return 'Buffer: ${secs}s';
    if (secs < 60) return 'Buffer: ${secs}s ahead';
    final mins = (secs / 60).floor();
    return 'Buffer: ${mins}m ahead';
  }

  /// Whether buffer is dangerously low.
  bool get isLow => effectiveBufferSeconds < 10;

  /// Whether buffer is critically low (about to run out).
  bool get isCritical => effectiveBufferSeconds < 3;

  /// Whether buffer is comfortable (no warnings needed).
  bool get isComfortable => effectiveBufferSeconds >= 30;

  /// Synthesis status text for UI.
  String get synthesisStatusText {
    if (!isSynthesizing) return '';
    if (activeSynthesisCount > 1) {
      return 'Synthesizing ($activeSynthesisCount)...';
    }
    return 'Synthesizing...';
  }

  @override
  String toString() =>
      'BufferStatus(${bufferSeconds.toStringAsFixed(1)}s @ ${playbackRate}x, '
      'effective: ${effectiveBufferSeconds.toStringAsFixed(1)}s, '
      'synthesizing: $isSynthesizing)';
}

/// Warning level for buffer status.
enum BufferWarningLevel {
  /// No warning - buffer is comfortable.
  none,

  /// Informational - buffer is moderate.
  info,

  /// Warning - buffer is getting low.
  warning,

  /// Critical - buffer about to run out or already empty.
  critical,
}

/// Extension for getting warning level from BufferStatus.
extension BufferStatusWarning on BufferStatus {
  /// Get the warning level for this buffer status.
  BufferWarningLevel get warningLevel {
    if (isCritical) return BufferWarningLevel.critical;
    if (isLow) return BufferWarningLevel.warning;
    if (!isComfortable) return BufferWarningLevel.info;
    return BufferWarningLevel.none;
  }
}

/// Constant DateTime for use in const constructors.
class _ConstantDateTime implements DateTime {
  const _ConstantDateTime();

  @override
  DateTime add(Duration duration) => DateTime.now().add(duration);

  @override
  int compareTo(DateTime other) => DateTime.now().compareTo(other);

  @override
  int get day => DateTime.now().day;

  @override
  Duration difference(DateTime other) => DateTime.now().difference(other);

  @override
  int get hour => DateTime.now().hour;

  @override
  bool isAfter(DateTime other) => DateTime.now().isAfter(other);

  @override
  bool isAtSameMomentAs(DateTime other) =>
      DateTime.now().isAtSameMomentAs(other);

  @override
  bool isBefore(DateTime other) => DateTime.now().isBefore(other);

  @override
  String get timeZoneName => DateTime.now().timeZoneName;

  @override
  bool get isUtc => false;

  @override
  int get microsecond => DateTime.now().microsecond;

  @override
  int get microsecondsSinceEpoch => DateTime.now().microsecondsSinceEpoch;

  @override
  int get millisecond => DateTime.now().millisecond;

  @override
  int get millisecondsSinceEpoch => DateTime.now().millisecondsSinceEpoch;

  @override
  int get minute => DateTime.now().minute;

  @override
  int get month => DateTime.now().month;

  @override
  int get second => DateTime.now().second;

  @override
  DateTime subtract(Duration duration) => DateTime.now().subtract(duration);

  @override
  Duration get timeZoneOffset => DateTime.now().timeZoneOffset;

  @override
  String toIso8601String() => DateTime.now().toIso8601String();

  @override
  DateTime toLocal() => DateTime.now().toLocal();

  @override
  DateTime toUtc() => DateTime.now().toUtc();

  @override
  int get weekday => DateTime.now().weekday;

  @override
  int get year => DateTime.now().year;
}
