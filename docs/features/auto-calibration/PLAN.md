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

### Phase 4: RTF Monitoring & Recommendations (Week 2)
- [ ] Create `RTFMonitor` class with rolling window
- [ ] Create `PerformanceAdvisor` with recommendation logic
- [ ] Define model speed tiers in `ModelCatalog`
- [ ] Create `VoiceCompatibilityEstimator` for proactive warnings
- [ ] Wire RTF recording into synthesis callbacks
- [ ] Create `DeviceCapabilityAssessor` for overall capability check
- [ ] Implement performance warning dialogs (model switch + incapable device)

### Phase 5: Graceful Degradation (Week 2-3)
- [ ] Implement `PreSynthesisMode` for incapable devices
- [ ] Add `GracefulDegradation` strategy selection
- [ ] Create pre-synthesis UI (chapter view)
- [ ] Add "buffered mode" startup delay
- [ ] Create storage for pre-synthesized chapters

### Phase 6: Performance Learning (Week 3)
- [ ] Create `PerformanceStore` (SQLite/Hive)
- [ ] Add synthesis performance recording
- [ ] Implement profile analysis for optimal concurrency
- [ ] Add voice/engine-specific learned ceilings

### Phase 7: Settings & UI Integration (Week 3-4)
- [ ] Add "Synthesis Mode" setting: Auto / Performance / Efficiency
- [ ] Add performance warning dialog UI
- [ ] Update voice picker with compatibility indicators
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

## Feature 5: RTF Monitoring & Model Recommendation

### Description
Track overall Real-Time Factor (RTF) and warn users when their current engine/voice is too slow for their device, prompting a switch to a faster model.

### RTF Calculation

```dart
class RTFMonitor {
  final _samples = <RTFSample>[];
  final int windowSize = 50; // Last 50 segments
  
  void recordSynthesis({
    required Duration audioDuration,  // How long the audio plays
    required Duration synthesisTime,  // How long synthesis took
    required int concurrency,         // Active slots during synthesis
  }) {
    // Effective RTF considering parallelism
    // RTF < 1.0 means faster than realtime
    final rtf = synthesisTime.inMilliseconds / audioDuration.inMilliseconds;
    _samples.add(RTFSample(rtf: rtf, concurrency: concurrency, timestamp: DateTime.now()));
    if (_samples.length > windowSize) _samples.removeAt(0);
  }
  
  // Overall RTF across window
  double get overallRTF => _samples.isEmpty ? 0 : _samples.map((s) => s.rtf).average;
  
  // Effective throughput: RTF adjusted for concurrency
  // 2 concurrent at RTF 0.8 = effective 0.4 RTF
  double get effectiveRTF {
    if (_samples.isEmpty) return 0;
    final avgConcurrency = _samples.map((s) => s.concurrency).average;
    return overallRTF / avgConcurrency;
  }
  
  // Can we keep up at current playback speed?
  bool canMaintainPlayback(double playbackRate) {
    // Need effective RTF < 1/playbackRate to not fall behind
    // At 1.5x playback, need RTF < 0.67
    // Add 20% safety margin
    return effectiveRTF < (1.0 / playbackRate) * 0.8;
  }
  
  // Estimate max sustainable playback speed
  double get maxSustainableSpeed {
    if (effectiveRTF <= 0) return 3.0; // Unknown, assume good
    return (1.0 / effectiveRTF) * 0.8; // With 20% margin
  }
}
```

### Performance Thresholds

```
Effective RTF    Status              Action
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
< 0.5           EXCELLENT            Silent, optimal performance
0.5 - 0.8       GOOD                 Silent, adequate headroom
0.8 - 1.0       MARGINAL             Internal flag, no user warning yet
1.0 - 1.2       STRUGGLING           Log warning, prepare recommendation
> 1.2           UNSUSTAINABLE        Show user recommendation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Model Speed Tiers

Define engine/voice speed tiers for recommendations:

```dart
enum ModelSpeedTier {
  fast,      // Piper: small models, < 0.3 RTF typical
  medium,    // Piper: medium models, Kokoro small voices
  slow,      // Kokoro: full quality voices
  premium,   // Supertonic: highest quality, slowest
}

class ModelCatalog {
  static ModelSpeedTier getTier(String engineId, String voiceId) {
    if (engineId == 'piper') {
      if (voiceId.contains('-low') || voiceId.contains('-small')) return ModelSpeedTier.fast;
      return ModelSpeedTier.medium;
    }
    if (engineId == 'kokoro') {
      return ModelSpeedTier.slow;
    }
    if (engineId == 'supertonic') {
      return ModelSpeedTier.premium;
    }
    return ModelSpeedTier.medium;
  }
  
  static List<AlternativeVoice> getFasterAlternatives(String engineId, String voiceId) {
    final currentTier = getTier(engineId, voiceId);
    // Return voices from faster tiers with similar characteristics
    // (same language, similar gender/style if possible)
  }
}
```

### Recommendation Logic

```dart
class PerformanceAdvisor {
  final RTFMonitor _rtfMonitor;
  final String currentEngineId;
  final String currentVoiceId;
  
  // Called periodically during playback
  PerformanceRecommendation? checkPerformance(double playbackRate) {
    final effectiveRTF = _rtfMonitor.effectiveRTF;
    
    // Only recommend if we've collected enough data
    if (_rtfMonitor.sampleCount < 10) return null;
    
    // Check if we can maintain current playback rate
    if (_rtfMonitor.canMaintainPlayback(playbackRate)) {
      return null; // All good
    }
    
    // Check if we've already maxed out concurrency
    if (!_hasHeadroomToScale()) {
      // Can't scale up anymore - recommend model change
      return PerformanceRecommendation(
        type: RecommendationType.switchModel,
        reason: _buildReason(effectiveRTF, playbackRate),
        alternatives: ModelCatalog.getFasterAlternatives(currentEngineId, currentVoiceId),
        maxSustainableSpeed: _rtfMonitor.maxSustainableSpeed,
      );
    }
    
    // Still have room to scale - let DemandController handle it
    return null;
  }
  
  String _buildReason(double rtf, double playbackRate) {
    if (playbackRate > 1.0) {
      return 'Your device cannot synthesize ${currentVoiceId} fast enough for ${playbackRate}x playback.';
    }
    return 'Your device is struggling to keep up with ${currentVoiceId}.';
  }
  
  bool _hasHeadroomToScale() {
    // Check if we can increase concurrency
    return currentConcurrency < maxConcurrency;
  }
}
```

### User Warning UI

Only show after:
1. At least 10 segments synthesized (reliable data)
2. Already at maximum concurrency (can't scale up more)
3. Effective RTF > 1.2 (clearly unsustainable)
4. User hasn't dismissed this warning in current session

```
┌────────────────────────────────────────────────────────────────┐
│  ⚠️ Performance Notice                                         │
├────────────────────────────────────────────────────────────────┤
│  Your device is having trouble keeping up with                 │
│  the "Kokoro - Sarah" voice at 1.5x speed.                    │
│                                                                │
│  Suggestions:                                                  │
│  • Switch to "Piper - Lessac" (faster)                        │
│  • Reduce playback speed to 1.0x                              │
│  • Let the app buffer ahead before playing                    │
│                                                                │
│  Current performance: 1.3x realtime (need <1.0x)              │
│                                                                │
│  ┌──────────────────┐  ┌───────────────┐                      │
│  │  Switch Voice    │  │   Dismiss     │                      │
│  └──────────────────┘  └───────────────┘                      │
└────────────────────────────────────────────────────────────────┘
```

### When NOT to Show Warning

1. **Paused playback**: User might be doing other things
2. **Initial buffering**: Haven't collected enough data yet
3. **After recent seek**: Temporary spike, wait for recovery
4. **User already acknowledged**: Don't nag, once per session max
5. **Already switching to faster model**: In transition

### Critical Failure: Cannot Achieve Real-Time Synthesis

When **no voice/engine combination** can achieve RTS on the device, we need a clear notification:

```dart
enum SynthesisCapability {
  capable,           // Can synthesize faster than realtime with at least one voice
  marginal,          // Barely keeping up, some voices unusable
  incapable,         // Cannot achieve RTS with ANY available voice
}

class DeviceCapabilityAssessor {
  final PerformanceStore _store;
  final List<AvailableVoice> _downloadedVoices;
  
  /// Check if ANY downloaded voice can achieve RTS
  Future<SynthesisCapability> assessOverallCapability() async {
    final device = await DeviceCapabilities.detect();
    
    // Check each downloaded voice
    final voiceCapabilities = <String, double>{};
    for (final voice in _downloadedVoices) {
      final profile = await _store.getProfile(voice.engineId, voice.voiceId);
      if (profile != null) {
        final effectiveRTF = profile.expectedRTF / device.recommendedMaxConcurrency;
        voiceCapabilities['${voice.engineId}:${voice.voiceId}'] = effectiveRTF;
      }
    }
    
    if (voiceCapabilities.isEmpty) {
      return SynthesisCapability.capable; // No data yet, assume capable
    }
    
    final bestRTF = voiceCapabilities.values.reduce(min);
    
    if (bestRTF < 0.8) return SynthesisCapability.capable;
    if (bestRTF < 1.2) return SynthesisCapability.marginal;
    return SynthesisCapability.incapable;
  }
  
  /// Get the fastest working voice, if any
  Future<AvailableVoice?> findFastestWorkingVoice() async {
    // Returns the voice with lowest RTF that can achieve RTS
    // Returns null if no voice can achieve RTS
  }
}
```

### Incapable Device Notification

Show this notification when:
1. Tested at least 3 different voices
2. All voices have RTF > 1.2 at max concurrency
3. User hasn't dismissed permanently

```
┌────────────────────────────────────────────────────────────────┐
│  ❌ Device Performance Issue                                    │
├────────────────────────────────────────────────────────────────┤
│  Unfortunately, your device cannot synthesize speech fast      │
│  enough for real-time playback with any available voice.       │
│                                                                │
│  This may be because:                                          │
│  • Your device has limited processing power                    │
│  • Battery saver mode is active                                │
│  • Other apps are using significant resources                  │
│                                                                │
│  Options:                                                      │
│  • Pre-synthesize chapters before listening                   │
│  • Try downloading a faster voice (Piper)                     │
│  • Listen at reduced playback speed                           │
│  • Try again when device is less busy                         │
│                                                                │
│  Best achievable: 0.7x realtime (need 1.0x minimum)           │
│                                                                │
│  ┌────────────────────┐  ┌───────────────────┐                │
│  │  Pre-synthesize    │  │   Slower Playback │                │
│  └────────────────────┘  └───────────────────┘                │
│                                                                │
│  ┌────────────────────────────────────────────┐               │
│  │     Don't show again for this device      │               │
│  └────────────────────────────────────────────┘               │
└────────────────────────────────────────────────────────────────┘
```

### Pre-Synthesis Mode

For incapable devices, offer a "pre-synthesis" option:

```dart
class PreSynthesisMode {
  /// Synthesize entire chapter(s) before allowing playback
  Future<void> preSynthesizeChapter(
    String bookId,
    int chapterIndex, {
    ProgressCallback? onProgress,
  }) async {
    // 1. Calculate total segments in chapter
    // 2. Synthesize all segments (no playback pressure)
    // 3. Cache results
    // 4. Mark chapter as "ready for playback"
    // 5. User can then play without synthesis delay
  }
  
  /// Estimate time to pre-synthesize
  Duration estimatePreSynthesisTime(int chapterIndex) {
    final segments = _getSegmentCount(chapterIndex);
    final avgAudioDuration = Duration(seconds: 15); // typical segment
    final rtf = _currentRTF;
    return avgAudioDuration * segments * rtf;
  }
}
```

### Pre-Synthesis UI

Add to chapter/book screen:

```
┌─────────────────────────────────────────────────────────────────┐
│ Chapter 5: The Journey Begins                                   │
├─────────────────────────────────────────────────────────────────┤
│ ⚠️ Your device needs to pre-synthesize this chapter            │
│                                                                 │
│ Estimated time: ~12 minutes                                     │
│ Storage needed: ~45 MB                                          │
│                                                                 │
│ ┌───────────────────────────────────────────────────────────┐  │
│ │          Pre-synthesize Chapter 5                         │  │
│ └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│ Or try listening anyway (may have interruptions)               │
│ ┌───────────────────────────────────────────────────────────┐  │
│ │              Play Anyway                                  │  │
│ └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Graceful Degradation Modes

For incapable devices, offer multiple fallback strategies:

```dart
enum PlaybackMode {
  realtime,        // Normal: synthesize on-demand
  preSynthesized,  // Chapter must be pre-synthesized
  buffered,        // Start playback only after X minutes buffered
  interruptible,   // Play with warnings about possible interruptions
}

class GracefulDegradation {
  /// Determine best playback mode for device
  PlaybackMode recommendedMode(SynthesisCapability capability, double rtf) {
    switch (capability) {
      case SynthesisCapability.capable:
        return PlaybackMode.realtime;
      case SynthesisCapability.marginal:
        // Can work but might stutter at high speeds
        return PlaybackMode.buffered;
      case SynthesisCapability.incapable:
        // Can't keep up - need pre-synthesis
        if (rtf < 0.5) {
          // Very slow but might work with enough buffer
          return PlaybackMode.interruptible;
        }
        return PlaybackMode.preSynthesized;
    }
  }
  
  /// Minimum buffer before starting playback in buffered mode
  Duration minimumBufferForMode(PlaybackMode mode, double rtf) {
    switch (mode) {
      case PlaybackMode.realtime: return Duration.zero;
      case PlaybackMode.buffered: return Duration(minutes: 2);
      case PlaybackMode.interruptible: return Duration(seconds: 30);
      case PlaybackMode.preSynthesized: return Duration.zero; // Chapter done
    }
  }
}
```

### Proactive Prevention

Before user even starts a book, estimate compatibility:

```dart
class VoiceCompatibilityEstimator {
  // Based on learned performance profiles and device capabilities
  Future<VoiceCompatibility> estimateCompatibility(
    String engineId, 
    String voiceId,
    double intendedPlaybackSpeed,
  ) async {
    final profile = await _performanceStore.getProfile(engineId, voiceId);
    final device = await DeviceCapabilities.detect();
    
    if (profile == null) {
      // No data - return unknown
      return VoiceCompatibility.unknown;
    }
    
    final estimatedRTF = profile.expectedRTF / device.recommendedMaxConcurrency;
    final required = 1.0 / intendedPlaybackSpeed;
    
    if (estimatedRTF < required * 0.7) return VoiceCompatibility.excellent;
    if (estimatedRTF < required) return VoiceCompatibility.good;
    if (estimatedRTF < required * 1.2) return VoiceCompatibility.marginal;
    return VoiceCompatibility.tooSlow;
  }
}
```

### Settings Voice Picker Enhancement

Show estimated compatibility in voice picker:

```
┌─────────────────────────────────────────────┐
│ Select Voice                                │
├─────────────────────────────────────────────┤
│ Kokoro - Sarah         ⚡ Great for 2x      │
│ Kokoro - Adam          ⚡ Great for 2x      │
│ Piper - Lessac         ⚡⚡ Great for 3x     │
│ Piper - Alan           ⚡⚡ Great for 3x     │
│ Supertonic - Premium   ⚠️ Best at 1x        │
└─────────────────────────────────────────────┘
```

---

## Success Criteria

1. **Zero user-visible stalls** during normal playback
2. **No manual calibration needed** for most users
3. **Battery usage ≤ current** in typical scenarios
4. **Smooth recovery** from seeks and speed changes
5. **Device stays cool** during extended listening
6. **Proactive guidance** when voice is too slow for device

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
- `packages/playback/lib/src/synthesis/rtf_monitor.dart`
- `packages/playback/lib/src/synthesis/performance_advisor.dart`
- `packages/playback/lib/src/synthesis/model_catalog.dart`
- `packages/playback/lib/src/synthesis/device_capability_assessor.dart`
- `packages/playback/lib/src/synthesis/pre_synthesis_mode.dart`
- `packages/playback/lib/src/synthesis/graceful_degradation.dart`
- `lib/ui/widgets/performance_warning_dialog.dart`
- `lib/ui/widgets/pre_synthesis_prompt.dart`

### Modified Files
- `packages/playback/lib/src/synthesis/synthesis_coordinator.dart` - Use DynamicSemaphore, record RTF
- `packages/playback/lib/src/synthesis/semaphore.dart` - Enhance or replace
- `packages/playback/lib/playback_config.dart` - Add synthesis mode enum, playback modes
- `lib/ui/screens/settings_screen.dart` - Add synthesis mode picker, voice compatibility
- `lib/ui/screens/playback_screen.dart` - Pre-synthesis prompts for incapable devices
- `lib/ui/screens/book_details_screen.dart` - Show pre-synthesis option per chapter
- `lib/ui/widgets/voice_picker.dart` - Add compatibility indicators
- `lib/app/playback_providers.dart` - Wire up DemandController, RTFMonitor, graceful degradation
