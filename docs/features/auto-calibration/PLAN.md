# Auto-Calibration: Dynamic Synthesis Optimization

## Overview

Replace manual calibration with an intelligent auto-calibration system that continuously adjusts synthesis parameters based on real-time playback demand. The system should be invisible to users while ensuring audio is always ready before playback reaches it.

## Current State Analysis

### Existing Infrastructure
- **Fixed Concurrency**: 2 slots per engine (hardcoded default)
- **Manual Calibration**: Optional benchmark runs 1-2-3 concurrency test
- **Adaptive Prefetch**: Adjusts *window size* (not concurrency) based on RTF, battery, memory
- **Buffer Tracking**: `estimateBufferedAheadMs()` calculates buffer status
- **Watermarks**: Low (10s) / High (60s) thresholds for prefetch control

### Current Limitations
1. Concurrency is static once set (manual calibration or default)
2. No response to "falling behind" playback
3. No utilization of additional cores when device is idle
4. Calibration requires user action and interrupts experience

## Proposed Solution: Dynamic Demand-Driven Synthesis

### Core Philosophy
> "Synthesize as slowly as possible while never running out of audio"

The system should:
- **Minimize resource usage** when comfortably ahead
- **Scale up aggressively** when buffer is running low
- **Learn device capabilities** through real synthesis, not artificial benchmarks

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    DemandController                              │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────────┐  │
│  │ BufferGauge │→ │ DemandSignal │→ │ ConcurrencyGovernor    │  │
│  │ (how ahead) │  │ (scale up/dn)│  │ (adjust slots + cores) │  │
│  └─────────────┘  └──────────────┘  └────────────────────────┘  │
└────────────────────────────────────────┬────────────────────────┘
                                         ↓
              ┌──────────────────────────────────────────┐
              │         SynthesisCoordinator             │
              │  [semaphore now with dynamic slots]      │
              │  [engine → slot count, adjusted live]    │
              └──────────────────────────────────────────┘
```

---

## Feature 1: Auto-Calibrate Mode

### Description
On-demand or automatic calibration that determines optimal concurrency without interrupting playback.

### Approach: Learning Through Real Synthesis

Instead of artificial benchmarks, measure actual synthesis performance during playback:

```dart
class SynthesisPerformanceTracker {
  // Rolling window of recent synthesis times
  final _recentRTFs = <double>[];
  final int windowSize = 20;
  
  void recordSynthesis(Duration textDuration, Duration synthTime) {
    final rtf = synthTime.inMilliseconds / textDuration.inMilliseconds;
    _recentRTFs.add(rtf);
    if (_recentRTFs.length > windowSize) _recentRTFs.removeAt(0);
  }
  
  double get averageRTF => _recentRTFs.average;
  double get worstRTF => _recentRTFs.max;
}
```

### Key Insight
RTF alone isn't enough. A device with RTF=0.5 can safely use 2 concurrent slots. But:
- If thermal throttling kicks in, effective RTF rises
- If battery saver mode activates, CPU is limited
- If other apps compete for resources, synthesis slows

**Solution**: Track both RTF and **completion variance**. High variance = unstable performance = use fewer slots.

### Settings Options
1. **Auto (Default)**: System manages everything, no user input needed
2. **Performance**: Prioritize speed, use more resources, accept battery drain
3. **Efficiency**: Prioritize battery, keep 1 slot, larger prefetch window

---

## Feature 2: Dynamic Concurrency Scaling

### Description
Automatically increase/decrease synthesis concurrency based on buffer status relative to playback.

### Buffer Zones & Response

```
Buffer Status         Action                   Concurrency
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
> 45 seconds ahead    COAST (idle)             1 slot (minimum)
30-45 seconds ahead   CRUISE (maintain)        Baseline (e.g., 2)
15-30 seconds ahead   ACCELERATE               Baseline + 1
< 15 seconds ahead    EMERGENCY                Maximum (baseline + 2)
< 5 seconds ahead     CRITICAL                 Max + boost queue priority
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Implementation: DemandSignal

```dart
enum DemandLevel {
  coast,      // Way ahead, minimize work
  cruise,     // Comfortable, maintain pace
  accelerate, // Getting close, speed up
  emergency,  // Dangerously close, max effort
  critical,   // About to run out, panic mode
}

class DemandSignal {
  final DemandLevel level;
  final double bufferSeconds;
  final double playbackRate;  // 1.0x, 1.5x, 2.0x affects thresholds
  
  int get recommendedConcurrency {
    switch (level) {
      case DemandLevel.coast: return 1;
      case DemandLevel.cruise: return baselineConcurrency;
      case DemandLevel.accelerate: return baselineConcurrency + 1;
      case DemandLevel.emergency: return maxConcurrency;
      case DemandLevel.critical: return maxConcurrency; // + boost
    }
  }
}
```

### Playback Rate Awareness
At 2.0x playback speed, 30 seconds of audio is consumed in 15 seconds real-time. Thresholds must scale:

```dart
double adjustedThreshold(double baseThreshold, double playbackRate) {
  return baseThreshold * playbackRate;
}
// 30s threshold at 2x = need 60s of synthesized audio
```

---

## Feature 3: Intelligent Core/Thread Management

### Description
Detect device capabilities and configure synthesis threads appropriately.

### Detection Strategy

```dart
class DeviceCapabilities {
  static Future<DeviceCapabilities> detect() async {
    final cpuCores = Platform.numberOfProcessors;
    final performanceCores = await _detectPerformanceCores(); // Platform-specific
    final thermalState = await _getThermalState();
    final batteryOptimized = await _isBatteryOptimized();
    
    return DeviceCapabilities(
      totalCores: cpuCores,
      performanceCores: performanceCores,
      efficiencyCores: cpuCores - performanceCores,
      thermalHeadroom: thermalState,
      powerConstrained: batteryOptimized,
    );
  }
  
  int get recommendedMaxConcurrency {
    // Never use more than performance cores
    // Leave headroom for UI thread
    return min(performanceCores - 1, 4).clamp(1, 4);
  }
}
```

### Android-Specific
```dart
// Use Android's ProcessStats or ActivityManager
final activityManager = await methodChannel.invokeMethod('getCpuInfo');
final bigCores = activityManager['bigCores'];  // Performance cores
```

### iOS-Specific
```dart
// Use processInfo.processorCount and thermal state
final thermalState = ProcessInfo.processInfo.thermalState;
// .nominal, .fair, .serious, .critical
```

### Ceiling Logic
```
Device Type          Max Concurrency    Notes
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Low-end (4 cores)    2                  Leave room for OS
Mid-range (6 cores)  3                  Performance cores only
High-end (8 cores)   4                  Cap to prevent diminishing returns
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Feature 4: Continuous Performance Learning

### Description
Build a performance profile over time, learning optimal settings for each engine/voice combination.

### Performance Database

```dart
class PerformanceProfile {
  final String engineId;
  final String voiceId;
  final List<PerformanceSample> samples;
  
  // Learned optimal concurrency for this voice
  int get optimalConcurrency {
    // Analyze samples to find sweet spot
    // where throughput plateaus vs concurrency
  }
  
  // Expected RTF based on history
  double get expectedRTF;
  
  // Variance in performance (stability)
  double get performanceStability;
}

class PerformanceStore {
  Future<void> recordSynthesis({
    required String engineId,
    required String voiceId,
    required Duration textDuration,
    required Duration synthTime,
    required int concurrencyAtTime,
    required ThermalState thermalState,
    required bool charging,
  });
  
  // Retrieve learned profile
  Future<PerformanceProfile> getProfile(String engineId, String voiceId);
}
```

### Learning Algorithm
1. Start conservative (2 concurrent)
2. During coast periods, experiment with +1 concurrency
3. Measure if throughput actually increases
4. If not, record that concurrency ceiling
5. Adjust for thermal throttling (performance drops = reduce ceiling)

---

## Implementation Plan

### Phase 1: Foundation (Week 1)
- [ ] Create `DemandController` class
- [ ] Add `BufferGauge` tracking (uses existing `estimateBufferedAheadMs`)
- [ ] Implement `DemandSignal` with zone calculations
- [ ] Add playback rate scaling to thresholds

### Phase 2: Dynamic Concurrency (Week 1-2)
- [ ] Make `Semaphore` support dynamic slot adjustment
- [ ] Create `ConcurrencyGovernor` that responds to DemandSignal
- [ ] Wire governor into SynthesisCoordinator
- [ ] Add hysteresis to prevent thrashing (cooldown periods)

### Phase 3: Device Detection (Week 2)
- [ ] Create `DeviceCapabilities` class
- [ ] Add Android MethodChannel for CPU info
- [ ] Add iOS equivalent (or use reasonable defaults)
- [ ] Set per-device concurrency ceilings

### Phase 4: Performance Learning (Week 2-3)
- [ ] Create `PerformanceStore` (SQLite/Hive)
- [ ] Add synthesis performance recording
- [ ] Implement profile analysis for optimal concurrency
- [ ] Add voice/engine-specific learned ceilings

### Phase 5: Settings Integration (Week 3)
- [ ] Add "Synthesis Mode" setting: Auto / Performance / Efficiency
- [ ] Update settings UI
- [ ] Wire modes to DemandController behavior
- [ ] Remove old calibration UI (or mark as "Advanced")

---

## Technical Details

### Semaphore Enhancement

Current semaphore has fixed slots. Enhance to support dynamic adjustment:

```dart
class DynamicSemaphore {
  int _maxSlots;
  int _activeSlots = 0;
  final _waitQueue = Queue<Completer<void>>();
  
  set maxSlots(int value) {
    _maxSlots = value;
    // Wake up waiting tasks if slots increased
    while (_activeSlots < _maxSlots && _waitQueue.isNotEmpty) {
      _waitQueue.removeFirst().complete();
      _activeSlots++;
    }
  }
  
  Future<void> acquire() async {
    if (_activeSlots < _maxSlots) {
      _activeSlots++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }
  
  void release() {
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeFirst().complete();
    } else {
      _activeSlots--;
    }
  }
}
```

### Hysteresis: Preventing Thrashing

```dart
class ConcurrencyGovernor {
  int _currentConcurrency;
  DateTime? _lastChange;
  final Duration cooldown = Duration(seconds: 5);
  
  void respondToSignal(DemandSignal signal) {
    final recommended = signal.recommendedConcurrency;
    
    // Emergency bypasses cooldown
    if (signal.level == DemandLevel.emergency || 
        signal.level == DemandLevel.critical) {
      _setConcurrency(recommended);
      return;
    }
    
    // Normal changes respect cooldown
    if (_lastChange != null && 
        DateTime.now().difference(_lastChange!) < cooldown) {
      return; // Too soon
    }
    
    // Only change by 1 at a time (except emergency)
    if (recommended > _currentConcurrency) {
      _setConcurrency(_currentConcurrency + 1);
    } else if (recommended < _currentConcurrency) {
      _setConcurrency(_currentConcurrency - 1);
    }
  }
}
```

### Buffer Gauge Integration

```dart
class BufferGauge {
  final SynthesisCoordinator _coordinator;
  final PlaybackController _playback;
  
  Stream<DemandSignal> get demandStream async* {
    await for (final state in _playback.playbackState) {
      if (!state.isPlaying) continue;
      
      final bufferMs = _coordinator.estimateBufferedAheadMs(
        currentSegmentIndex: state.segmentIndex,
        currentPositionInSegment: state.positionInSegment,
      );
      
      final playbackRate = state.speed;
      final adjustedBuffer = bufferMs / playbackRate;
      
      yield DemandSignal(
        level: _calculateLevel(adjustedBuffer),
        bufferSeconds: adjustedBuffer / 1000,
        playbackRate: playbackRate,
      );
    }
  }
  
  DemandLevel _calculateLevel(double bufferMs) {
    if (bufferMs < 5000) return DemandLevel.critical;
    if (bufferMs < 15000) return DemandLevel.emergency;
    if (bufferMs < 30000) return DemandLevel.accelerate;
    if (bufferMs < 45000) return DemandLevel.cruise;
    return DemandLevel.coast;
  }
}
```

---

## Settings UI

### Synthesis Mode Picker

```
┌─────────────────────────────────────┐
│ Synthesis Speed                     │
├─────────────────────────────────────┤
│ ◉ Auto (Recommended)                │
│   Adapts to your device and         │
│   listening. Saves battery when     │
│   ahead, speeds up when needed.     │
├─────────────────────────────────────┤
│ ○ Performance                       │
│   Maximum speed. Uses more          │
│   battery and may warm device.      │
├─────────────────────────────────────┤
│ ○ Efficiency                        │
│   Minimum resource usage.           │
│   May briefly pause on fast seeks.  │
└─────────────────────────────────────┘
```

---

## Edge Cases & Handling

### User Seeks Far Ahead
**Problem**: User scrubs 10 chapters ahead, buffer is zero.
**Solution**: 
1. Immediately enter CRITICAL mode
2. Prioritize current segment with `SynthesisPriority.immediate`
3. Start synthesis at max concurrency
4. Show brief "loading" indicator if unavoidable

### Device Overheating
**Problem**: Thermal throttling reduces synthesis speed.
**Solution**:
1. Monitor RTF degradation
2. If RTF rises significantly, reduce concurrency (counterintuitive but reduces heat)
3. Increase prefetch window to compensate

### Memory Pressure
**Problem**: OS signals low memory.
**Solution**:
1. Reduce prefetch window (fewer queued items)
2. Clear completed segments from cache faster
3. Reduce concurrency to lower memory footprint

### Playback Speed Changes
**Problem**: User switches from 1x to 2x mid-chapter.
**Solution**:
1. BufferGauge automatically adjusts thresholds
2. Likely triggers ACCELERATE or EMERGENCY
3. Concurrency scales up to keep pace

---

## Metrics & Debugging

### Internal Metrics (for development)
```dart
class AutoCalibrationMetrics {
  int concurrencyChanges;
  int emergencyModeEntries;
  Duration timeInEachLevel;
  double averageBufferAhead;
  int userVisibleStalls; // The key metric!
}
```

### Debug View (Settings → Developer)
```
Synthesis Status
────────────────────────
Mode: Auto
Demand: CRUISE
Buffer: 34.2s ahead
Concurrency: 2/4
RTF (avg): 0.42
Last change: 12s ago
Stalls today: 0
```

---

## Success Criteria

1. **Zero user-visible stalls** during normal playback
2. **No manual calibration needed** for most users
3. **Battery usage ≤ current** in typical scenarios
4. **Smooth recovery** from seeks and speed changes
5. **Device stays cool** during extended listening

---

## Open Questions

1. **Should we support "unlimited" cores?** Some power users might want 6+ concurrent.
   - Recommendation: Cap at 4 in UI, allow override in developer settings

2. **How to handle first-time users?** No performance data yet.
   - Recommendation: Start at 2 concurrent, learn quickly

3. **Per-voice calibration worth complexity?**
   - Recommendation: Yes, Kokoro voices have different model sizes

4. **Persist learned profiles across app updates?**
   - Recommendation: Yes, stored in app documents, keyed by engine+voice

---

## Files to Modify/Create

### New Files
- `packages/playback/lib/src/synthesis/demand_controller.dart`
- `packages/playback/lib/src/synthesis/buffer_gauge.dart`
- `packages/playback/lib/src/synthesis/concurrency_governor.dart`
- `packages/playback/lib/src/synthesis/device_capabilities.dart`
- `packages/playback/lib/src/synthesis/performance_store.dart`
- `packages/playback/lib/src/synthesis/dynamic_semaphore.dart`

### Modified Files
- `packages/playback/lib/src/synthesis/synthesis_coordinator.dart` - Use DynamicSemaphore
- `packages/playback/lib/src/synthesis/semaphore.dart` - Enhance or replace
- `packages/playback/lib/playback_config.dart` - Add synthesis mode enum
- `lib/ui/screens/settings_screen.dart` - Add synthesis mode picker
- `lib/app/playback_providers.dart` - Wire up DemandController
