import 'dart:async';

import 'playback_log.dart';

/// Manages prefetch suspension with configurable and cancellable timers.
///
/// This replaces the fixed 500ms delay in BufferScheduler.suspend() with
/// an intelligent system that adapts to user behavior and allows manual
/// override.
///
/// Features:
/// - Configurable resume delay
/// - Rapid seek detection (increases delay when user is scrubbing)
/// - Manual resume (for immediate resumption after seek bar release)
/// - Timer cancellation on dispose
class PrefetchResumeController {
  PrefetchResumeController({
    int resumeDelayMs = 500,
  }) : _baseResumeDelayMs = resumeDelayMs;

  final int _baseResumeDelayMs;

  Timer? _resumeTimer;
  bool _isSuspended = false;
  int _seekCount = 0;
  DateTime? _lastSeekTime;
  VoidCallback? _onResume;

  /// Whether prefetch is currently suspended.
  bool get isSuspended => _isSuspended;

  /// The current effective delay, considering seek patterns.
  Duration get effectiveDelay {
    final baseDelay = Duration(milliseconds: _baseResumeDelayMs);

    // If user is seeking rapidly, increase delay to avoid thrashing
    if (_seekCount >= 3 &&
        _lastSeekTime != null &&
        DateTime.now().difference(_lastSeekTime!) <
            const Duration(seconds: 2)) {
      // Rapid seeking detected - wait longer
      PlaybackLog.debug(
        'PrefetchResumeController: Rapid seeking detected '
        '($_seekCount seeks in 2s), doubling delay',
      );
      return baseDelay * 2;
    }

    return baseDelay;
  }

  /// Register callback for when prefetch should resume.
  ///
  /// The callback is invoked after the resume delay expires (or immediately
  /// if [resumeImmediately] is called).
  void setOnResume(VoidCallback callback) {
    _onResume = callback;
  }

  /// Suspend prefetch due to seek/navigation.
  ///
  /// Automatically schedules resume after delay.
  /// If called multiple times in quick succession, the timer restarts
  /// each time (debounce behavior).
  void suspend() {
    _isSuspended = true;
    _resumeTimer?.cancel();

    // Track seek patterns
    final now = DateTime.now();
    if (_lastSeekTime != null &&
        now.difference(_lastSeekTime!) < const Duration(seconds: 2)) {
      _seekCount++;
    } else {
      _seekCount = 1;
    }
    _lastSeekTime = now;

    PlaybackLog.debug(
      'PrefetchResumeController: Suspended (seek #$_seekCount)',
    );

    // Schedule auto-resume
    _resumeTimer = Timer(effectiveDelay, _resume);
  }

  /// Manually resume prefetch immediately.
  ///
  /// Use when user action indicates they're done seeking:
  /// - Seek bar released (onChangeEnd)
  /// - Play button pressed after seek
  /// - Chapter selection completed
  void resumeImmediately() {
    PlaybackLog.debug('PrefetchResumeController: Manual resume requested');
    _resumeTimer?.cancel();
    _resume();
  }

  /// Cancel any pending resume without triggering the callback.
  ///
  /// Use when disposing or when you want to explicitly prevent resume.
  void cancel() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
  }

  /// Update the base resume delay.
  ///
  /// If a timer is pending, it will restart with the new delay.
  void updateResumeDelayMs(int delayMs) {
    if (_resumeTimer != null && _baseResumeDelayMs != delayMs) {
      // Restart timer with new delay
      suspend();
    }
  }

  void _resume() {
    if (!_isSuspended) return;

    _isSuspended = false;
    _seekCount = 0;
    PlaybackLog.debug('PrefetchResumeController: Resumed');
    _onResume?.call();
  }

  /// Dispose resources.
  void dispose() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _onResume = null;
  }
}

/// Callback type for void functions.
typedef VoidCallback = void Function();
