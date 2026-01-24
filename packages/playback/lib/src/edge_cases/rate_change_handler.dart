import 'dart:async';
import 'dart:developer' as developer;

/// Handles playback rate changes with debouncing.
///
/// When users scrub the rate slider rapidly, this handler:
/// 1. Debounces rapid changes to avoid excessive cache invalidation
/// 2. Delays prefetch restart until rate stabilizes
/// 3. Optionally invalidates rate-specific cached segments
///
/// Note: When rateIndependentSynthesis is enabled, cached audio can be
/// reused across rate changes (playback rate is applied by audio player).
class RateChangeHandler {
  RateChangeHandler({
    required void Function(double rate) onRateStabilized,
    required void Function(String reason) onCancelPrefetch,
    required Future<void> Function() onRestartPrefetch,
    Duration debounceDelay = const Duration(milliseconds: 500),
    bool rateIndependentSynthesis = true,
  }) : _onRateStabilized = onRateStabilized,
       _onCancelPrefetch = onCancelPrefetch,
       _onRestartPrefetch = onRestartPrefetch,
       _debounceDelay = debounceDelay,
       _rateIndependentSynthesis = rateIndependentSynthesis;

  final void Function(double rate) _onRateStabilized;
  final void Function(String reason) _onCancelPrefetch;
  final Future<void> Function() _onRestartPrefetch;
  final Duration _debounceDelay;
  final bool _rateIndependentSynthesis;

  double _currentRate = 1.0;
  double _pendingRate = 1.0;
  Timer? _debounceTimer;
  int _changeCount = 0;
  DateTime? _firstChangeTime;

  /// Current effective playback rate.
  double get currentRate => _currentRate;

  /// Whether rate changes are being debounced.
  bool get isDebouncing => _debounceTimer != null;

  /// Number of rate changes in the current debounce window.
  int get pendingChangeCount => _changeCount;

  /// Whether rate-independent synthesis is enabled.
  bool get rateIndependentSynthesis => _rateIndependentSynthesis;

  /// Handle a rate change request.
  ///
  /// [newRate] is the requested playback rate.
  /// Returns immediately, but rate change is debounced.
  void handleRateChange(double newRate) {
    // Clamp rate to valid range
    final clampedRate = newRate.clamp(0.5, 3.0);
    
    // Track change statistics
    _changeCount++;
    _firstChangeTime ??= DateTime.now();
    _pendingRate = clampedRate;

    // Cancel existing timer
    _debounceTimer?.cancel();

    // If this is a significant change, cancel prefetch immediately
    if ((clampedRate - _currentRate).abs() > 0.25) {
      _onCancelPrefetch('rate change: $_currentRate -> $clampedRate');
    }

    // Start new debounce timer
    _debounceTimer = Timer(_debounceDelay, () => _applyRate(clampedRate));

    developer.log(
      '[RateChangeHandler] Rate change queued: $clampedRate (change #$_changeCount)',
      name: 'RateChangeHandler',
    );
  }

  /// Apply the debounced rate change.
  Future<void> _applyRate(double rate) async {
    _debounceTimer = null;
    final previousRate = _currentRate;
    _currentRate = rate;

    // Calculate stats for logging
    final totalChanges = _changeCount;
    final debounceTime = _firstChangeTime != null
        ? DateTime.now().difference(_firstChangeTime!)
        : Duration.zero;

    // Reset counters
    _changeCount = 0;
    _firstChangeTime = null;

    developer.log(
      '[RateChangeHandler] Rate stabilized: $previousRate -> $rate '
      '(debounced $totalChanges changes over ${debounceTime.inMilliseconds}ms)',
      name: 'RateChangeHandler',
    );

    // Notify listeners
    _onRateStabilized(rate);

    // If rate-independent synthesis is disabled, we need to invalidate cache
    // and restart prefetch with new rate baked into synthesis
    if (!_rateIndependentSynthesis) {
      developer.log(
        '[RateChangeHandler] Rate-dependent synthesis: restarting prefetch',
        name: 'RateChangeHandler',
      );
      _onCancelPrefetch('rate change requires re-synthesis');
      await _onRestartPrefetch();
    } else {
      // Rate-independent: just restart prefetch, existing cache is valid
      developer.log(
        '[RateChangeHandler] Rate-independent synthesis: reusing cache',
        name: 'RateChangeHandler',
      );
      await _onRestartPrefetch();
    }
  }

  /// Force immediate application of pending rate (skip debounce).
  Future<void> applyImmediately() async {
    if (_debounceTimer != null) {
      _debounceTimer!.cancel();
      _debounceTimer = null;
      await _applyRate(_pendingRate);
    }
  }

  /// Cancel any pending rate change.
  void cancel() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _changeCount = 0;
    _firstChangeTime = null;
    _pendingRate = _currentRate;
    
    developer.log(
      '[RateChangeHandler] Pending rate change cancelled',
      name: 'RateChangeHandler',
    );
  }

  /// Set the initial rate without triggering handlers.
  void setInitialRate(double rate) {
    _currentRate = rate;
    _pendingRate = rate;
    developer.log(
      '[RateChangeHandler] Initial rate set: $rate',
      name: 'RateChangeHandler',
    );
  }

  /// Dispose resources.
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}
