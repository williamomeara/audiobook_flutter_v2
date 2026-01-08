import 'dart:async';
import 'dart:developer' as developer;

import 'package:battery_plus/battery_plus.dart';

import 'playback_config.dart';

/// Monitors device resources (battery, storage) and determines synthesis mode.
///
/// Phase 2: Battery-aware prefetch - adjusts prefetch aggressiveness based on
/// battery level and charging state to optimize battery life while maintaining
/// smooth playback.
class ResourceMonitor {
  ResourceMonitor({Battery? battery}) : _battery = battery ?? Battery();

  final Battery _battery;

  /// Current synthesis mode based on resource constraints
  SynthesisMode _currentMode = SynthesisMode.balanced;

  /// Stream of mode changes
  final _modeController = StreamController<SynthesisMode>.broadcast();

  /// Subscription to battery state changes
  StreamSubscription<BatteryState>? _batteryStateSub;

  /// Current battery level (cached)
  int _batteryLevel = 100;

  /// Whether device is charging
  bool _isCharging = false;

  /// Whether the monitor has been initialized
  bool _isInitialized = false;

  // Getters
  SynthesisMode get currentMode => _currentMode;
  Stream<SynthesisMode> get modeStream => _modeController.stream;
  int get batteryLevel => _batteryLevel;
  bool get isCharging => _isCharging;

  /// Initialize the resource monitor and start listening to battery changes.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    developer.log('[ResourceMonitor] Initializing...');

    try {
      // Get initial battery level
      _batteryLevel = await _battery.batteryLevel;
      developer.log('[ResourceMonitor] Initial battery level: $_batteryLevel%');

      // Get initial charging state
      final batteryState = await _battery.batteryState;
      _isCharging = batteryState == BatteryState.charging || 
                    batteryState == BatteryState.full;
      developer.log('[ResourceMonitor] Initial charging state: $_isCharging');

      // Update mode based on initial state
      _updateSynthesisMode();

      // Listen to battery state changes
      _batteryStateSub = _battery.onBatteryStateChanged.listen((state) {
        _isCharging = state == BatteryState.charging || state == BatteryState.full;
        developer.log('[ResourceMonitor] Battery state changed: $state (charging: $_isCharging)');
        _updateSynthesisMode();
      });

      developer.log('[ResourceMonitor] Initialized successfully. Mode: $_currentMode');
    } catch (e, st) {
      developer.log(
        '[ResourceMonitor] Failed to initialize battery monitoring',
        error: e,
        stackTrace: st,
      );
      // Default to balanced mode if battery monitoring fails
      _currentMode = SynthesisMode.balanced;
    }
  }

  /// Update battery level (call periodically or when needed).
  Future<void> refreshBatteryLevel() async {
    try {
      final previousLevel = _batteryLevel;
      _batteryLevel = await _battery.batteryLevel;
      
      if (previousLevel != _batteryLevel) {
        developer.log('[ResourceMonitor] Battery level updated: $previousLevel% → $_batteryLevel%');
        _updateSynthesisMode();
      }
    } catch (e) {
      developer.log('[ResourceMonitor] Failed to refresh battery level: $e');
    }
  }

  /// Determine appropriate synthesis mode based on current resource state.
  void _updateSynthesisMode() {
    final previousMode = _currentMode;
    SynthesisMode newMode;

    if (_isCharging) {
      // Charging - maximum synthesis
      newMode = SynthesisMode.aggressive;
    } else if (_batteryLevel < PlaybackConfig.minimumPrefetchBatteryLevel) {
      // Very low battery - JIT only
      newMode = SynthesisMode.jitOnly;
    } else if (_batteryLevel < 20) {
      // Low battery - conservative
      newMode = SynthesisMode.conservative;
    } else if (_batteryLevel >= PlaybackConfig.fullChapterPrefetchBatteryThreshold) {
      // High battery - aggressive
      newMode = SynthesisMode.aggressive;
    } else {
      // Normal battery - balanced
      newMode = SynthesisMode.balanced;
    }

    if (newMode != previousMode) {
      _currentMode = newMode;
      developer.log(
        '[ResourceMonitor] Synthesis mode changed: $previousMode → $newMode '
        '(battery: $_batteryLevel%, charging: $_isCharging)',
      );
      _modeController.add(newMode);
    }
  }

  /// Check if prefetching is allowed given current resources.
  bool get canPrefetch {
    return _currentMode != SynthesisMode.jitOnly;
  }

  /// Get maximum prefetch tracks based on current mode.
  int get maxPrefetchTracks => _currentMode.maxPrefetchTracks;

  /// Get target buffer size based on current mode.
  int get bufferTargetMs => _currentMode.bufferTargetMs;

  /// Get concurrency limit based on current mode.
  int get concurrencyLimit => _currentMode.concurrencyLimit;

  /// Dispose resources.
  Future<void> dispose() async {
    developer.log('[ResourceMonitor] Disposing...');
    await _batteryStateSub?.cancel();
    await _modeController.close();
    _isInitialized = false;
  }
}
