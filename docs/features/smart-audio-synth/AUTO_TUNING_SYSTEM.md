# Auto-Tuning System for Engine-Specific Optimization

## Overview

Different devices have different synthesis capabilities. A flagship phone can handle aggressive prefetch, while a mid-range device needs conservative settings. **Auto-tuning** measures device performance and automatically configures optimal settings per engine.

---

## The Problem

### Device Variability

| Device Class | Piper Segment Time | Supertonic Segment Time | Recommended Strategy |
|--------------|-------------------|------------------------|---------------------|
| **Flagship** (Snapdragon 8 Gen 3) | 1-2s | 1.5-3s | Aggressive prefetch, parallel synthesis |
| **Mid-range** (Snapdragon 778G) | 2-4s | 3-5s | Balanced prefetch, sequential synthesis |
| **Budget** (Snapdragon 680) | 4-8s | 6-10s | Conservative, on-demand synthesis |
| **Old** (Snapdragon 660) | 8-15s | 12-20s | Minimal prefetch, limit features |

### Fixed Settings Don't Work

```dart
// BAD: Hard-coded settings assume mid-range device
static const prefetchWindowSize = 10; // Too aggressive for budget phones
static const prefetchConcurrency = 2; // Budget phones can't handle parallel
```

**Problem**: 
- Flagship: Wasted potential (could prefetch 20 segments)
- Budget: Battery drain, stuttering (prefetch falls behind)

---

## Solution: Auto-Tuning System

### 1. Device Performance Profiling

Run a **5-minute synthesis benchmark** (similar to current benchmark, but focused on profiling):

```dart
class DevicePerformanceProfiler {
  Future<DeviceProfile> profileDevice(String voiceId) async {
    print('[Auto-Tune] Starting device performance profiling...');
    
    // Generate test chapter (300 words, ~30 segments)
    final testChapter = _generateTestChapter();
    final segments = segmentText(testChapter);
    
    // Measure synthesis performance
    final profile = await _measureSynthesisPerformance(voiceId, segments);
    
    // Measure battery impact
    final batteryProfile = await _measureBatteryImpact(voiceId, segments);
    
    // Measure thermal behavior
    final thermalProfile = await _measureThermalBehavior(voiceId, segments);
    
    return DeviceProfile(
      voiceId: voiceId,
      synthesis: profile,
      battery: batteryProfile,
      thermal: thermalProfile,
      deviceInfo: await _getDeviceInfo(),
    );
  }
  
  Future<SynthesisProfile> _measureSynthesisPerformance(
    String voiceId,
    List<Segment> segments,
  ) async {
    final times = <int>[];
    
    // Measure synthesis time for each segment
    for (var segment in segments.take(30)) {
      final start = DateTime.now();
      await _synthesize(voiceId, segment);
      times.add(DateTime.now().difference(start).inMilliseconds);
    }
    
    return SynthesisProfile(
      avgSynthesisMs: _calculateAverage(times),
      minSynthesisMs: times.reduce(min),
      maxSynthesisMs: times.reduce(max),
      p50SynthesisMs: _calculatePercentile(times, 0.5),
      p95SynthesisMs: _calculatePercentile(times, 0.95),
      rtf: _calculateRTF(times, segments),
    );
  }
}
```

### 2. Automatic Configuration Selection

Based on measured performance, select optimal configuration:

```dart
class AutoTuner {
  EngineConfig selectOptimalConfig(DeviceProfile profile) {
    // Classify device performance tier
    final tier = _classifyDeviceTier(profile);
    
    // Select configuration based on tier
    switch (tier) {
      case DeviceTier.flagship:
        return _getFlagshipConfig(profile);
      case DeviceTier.midRange:
        return _getMidRangeConfig(profile);
      case DeviceTier.budget:
        return _getBudgetConfig(profile);
      case DeviceTier.legacy:
        return _getLegacyConfig(profile);
    }
  }
  
  DeviceTier _classifyDeviceTier(DeviceProfile profile) {
    final rtf = profile.synthesis.rtf;
    
    // RTF thresholds (engine-specific)
    if (rtf < 0.3) {
      return DeviceTier.flagship; // Very fast synthesis
    } else if (rtf < 0.5) {
      return DeviceTier.midRange; // Good synthesis speed
    } else if (rtf < 0.8) {
      return DeviceTier.budget; // Acceptable synthesis
    } else {
      return DeviceTier.legacy; // Slow synthesis
    }
  }
  
  EngineConfig _getFlagshipConfig(DeviceProfile profile) {
    return EngineConfig(
      // Aggressive prefetch - device can handle it
      prefetchWindowSize: 20,
      prefetchConcurrency: 3, // Triple parallel synthesis!
      preSynthesizeCount: 2,
      
      // Full chapter synthesis
      enableFullChapterPrefetch: true,
      fullChapterBatteryThreshold: 30,
      
      // Next chapter prediction
      enableNextChapterPrediction: true,
      
      // Cache aggressively
      cacheRetentionDays: 14,
      maxCacheSizeMB: 1000, // Flagship has storage
    );
  }
  
  EngineConfig _getMidRangeConfig(DeviceProfile profile) {
    return EngineConfig(
      // Balanced prefetch
      prefetchWindowSize: 10,
      prefetchConcurrency: 1, // Sequential synthesis
      preSynthesizeCount: 1,
      
      // Partial chapter synthesis
      enableFullChapterPrefetch: true,
      fullChapterBatteryThreshold: 50, // Higher threshold
      
      // Limited prediction
      enableNextChapterPrediction: false, // Too risky
      
      // Standard cache
      cacheRetentionDays: 7,
      maxCacheSizeMB: 500,
    );
  }
  
  EngineConfig _getBudgetConfig(DeviceProfile profile) {
    return EngineConfig(
      // Conservative prefetch
      prefetchWindowSize: 5, // Only 5 segments ahead
      prefetchConcurrency: 1,
      preSynthesizeCount: 1,
      
      // No full chapter synthesis
      enableFullChapterPrefetch: false,
      fullChapterBatteryThreshold: 80, // Charging only
      
      // No prediction
      enableNextChapterPrediction: false,
      
      // Minimal cache
      cacheRetentionDays: 3,
      maxCacheSizeMB: 200,
    );
  }
}
```

### 3. Per-Engine Configuration Storage

Store configuration for each engine separately:

```dart
class EngineConfigManager {
  // Store per-engine, per-device configs
  final Map<String, EngineConfig> _configs = {};
  
  Future<void> saveConfig(String engineId, EngineConfig config) async {
    _configs[engineId] = config;
    await _prefs.setString('engine_config_$engineId', jsonEncode(config));
  }
  
  Future<EngineConfig?> loadConfig(String engineId) async {
    if (_configs.containsKey(engineId)) {
      return _configs[engineId];
    }
    
    final json = _prefs.getString('engine_config_$engineId');
    if (json != null) {
      return EngineConfig.fromJson(jsonDecode(json));
    }
    
    return null; // Not yet profiled
  }
  
  Future<EngineConfig> getConfigOrAutoTune(String engineId) async {
    // Check if we have a saved config
    var config = await loadConfig(engineId);
    if (config != null) {
      return config;
    }
    
    // No config - run auto-tuning
    print('[AutoTune] No config for $engineId, running auto-tune...');
    final profile = await DevicePerformanceProfiler().profileDevice(engineId);
    config = AutoTuner().selectOptimalConfig(profile);
    await saveConfig(engineId, config);
    
    return config;
  }
}
```

---

## Shared Logic, Different Configs

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│           Shared Playback Controller                        │
│  • Chapter loading                                          │
│  • Playback state management                                │
│  • Segment queue                                            │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ Uses config for decisions
                   ▼
┌─────────────────────────────────────────────────────────────┐
│           Smart Synthesis Manager (Shared)                  │
│  • Priority queue                                           │
│  • Prefetch scheduling                                      │
│  • Cache management                                         │
│                                                             │
│  Uses: config.prefetchWindowSize                           │
│        config.prefetchConcurrency                          │
│        config.preSynthesizeCount                           │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ Reads config
                   ▼
┌─────────────────────────────────────────────────────────────┐
│           Engine Config Manager                             │
│  ┌──────────────┬──────────────┬──────────────┐            │
│  │ Piper Config │ Super Config │ Kokoro Config│            │
│  │ • Window: 10 │ • Window: 15 │ • Window: 8  │            │
│  │ • Conc: 1    │ • Conc: 2    │ • Conc: 1    │            │
│  │ • Pre: 1     │ • Pre: 1     │ • Pre: 2     │            │
│  └──────────────┴──────────────┴──────────────┘            │
└─────────────────────────────────────────────────────────────┘
```

### Code Example

```dart
// Shared logic
class SmartSynthesisManager {
  final EngineConfigManager _configManager;
  
  Future<void> loadChapter(String engineId, Chapter chapter) async {
    // Get engine-specific config
    final config = await _configManager.getConfigOrAutoTune(engineId);
    
    final segments = segmentText(chapter.content);
    
    // Pre-synthesize based on config
    final preSynthCount = config.preSynthesizeCount;
    for (var i = 0; i < preSynthCount && i < segments.length; i++) {
      await _synthesize(engineId, segments[i]);
    }
    
    // Start prefetch with engine-specific window size
    _startPrefetch(
      engineId,
      segments,
      windowSize: config.prefetchWindowSize,
      concurrency: config.prefetchConcurrency,
    );
  }
  
  void _startPrefetch(
    String engineId,
    List<Segment> segments, {
    required int windowSize,
    required int concurrency,
  }) {
    // Shared prefetch logic, parameterized by config
    Future(() async {
      if (concurrency == 1) {
        // Sequential
        for (var i = 0; i < windowSize && i < segments.length; i++) {
          await _synthesize(engineId, segments[i]);
        }
      } else {
        // Parallel
        for (var i = 0; i < windowSize; i += concurrency) {
          final batch = segments.skip(i).take(concurrency);
          await Future.wait(batch.map((s) => _synthesize(engineId, s)));
        }
      }
    });
  }
}
```

---

## User Experience

### Auto-Tuning UI

**Settings > Playback > Engine Optimization**:

```
┌─────────────────────────────────────────────────────────────┐
│ 🎯 Device Optimization                                      │
│                                                              │
│ Optimize playback for your device by running a quick test.  │
│ This measures synthesis speed and battery impact.           │
│                                                              │
│ ┌──────────────────────────────────────────────────────┐   │
│ │ Piper (Alan GB)                    [Optimize Now]    │   │
│ │ Last optimized: Never                                │   │
│ │                                                       │   │
│ │ Supertonic (M1)                    [Optimize Now]    │   │
│ │ Last optimized: 2 days ago                           │   │
│ │ Status: ✓ Optimized for your device                 │   │
│ │                                                       │   │
│ │ Kokoro (British F1)                [Optimize Now]    │   │
│ │ Last optimized: Never                                │   │
│ └──────────────────────────────────────────────────────┘   │
│                                                              │
│ ☑ Re-optimize when device is charging                       │
│ ☑ Auto-optimize new voices on first use                     │
│                                                              │
│ [Reset All Optimizations]                                   │
└──────────────────────────────────────────────────────────────┘
```

### Optimization Flow

1. **User taps "Optimize Now"**
   - Shows progress: "Running 30-second synthesis test..."
   - Progress bar updates as segments synthesize
   
2. **Test completes**
   - Shows results: "Your device is **Mid-Range**"
   - Shows selected config:
     ```
     Prefetch window: 10 segments
     Synthesis strategy: Sequential
     Battery threshold: 50%
     Cache retention: 7 days
     ```

3. **User can manually adjust** (Advanced option):
   - Slider: Conservative ←→ Balanced ←→ Aggressive
   - Preview impact: "More battery drain, smoother playback"

---

## Auto-Tuning Logic

### When to Run Auto-Tuning

1. **First app launch** (for default voice)
2. **First time using a voice** (per-voice optimization)
3. **User manually triggers** (Settings → Optimize)
4. **Periodic re-tuning** (every 30 days, detects OS updates/performance changes)
5. **After OS update detected** (performance characteristics may change)

```dart
class AutoTuningScheduler {
  Future<void> checkAndRunAutoTuning(String engineId) async {
    // Check if we need to auto-tune
    final lastTuned = await _getLastTunedDate(engineId);
    final daysSinceLastTune = DateTime.now().difference(lastTuned).inDays;
    
    if (lastTuned == null || daysSinceLastTune > 30) {
      // Time to re-tune
      print('[AutoTune] Re-tuning $engineId (last tuned $daysSinceLastTune days ago)');
      await _runAutoTuning(engineId);
    }
  }
  
  Future<void> autoTuneOnFirstUse(String engineId) async {
    final config = await _configManager.loadConfig(engineId);
    if (config == null) {
      // First use - auto-tune automatically
      print('[AutoTune] First use of $engineId, auto-tuning...');
      await _runAutoTuning(engineId);
    }
  }
}
```

---

## Configuration Schema

### EngineConfig Data Class

```dart
class EngineConfig {
  EngineConfig({
    required this.engineId,
    required this.deviceTier,
    required this.prefetchWindowSize,
    required this.prefetchConcurrency,
    required this.preSynthesizeCount,
    required this.enableFullChapterPrefetch,
    required this.fullChapterBatteryThreshold,
    required this.enableNextChapterPrediction,
    required this.cacheRetentionDays,
    required this.maxCacheSizeMB,
    required this.measuredRTF,
    required this.tunedAt,
  });
  
  final String engineId;
  final DeviceTier deviceTier;
  
  // Prefetch settings
  final int prefetchWindowSize; // How many segments to prefetch
  final int prefetchConcurrency; // How many parallel synthesis tasks
  final int preSynthesizeCount; // How many segments to synthesize on load
  
  // Advanced prefetch
  final bool enableFullChapterPrefetch;
  final int fullChapterBatteryThreshold; // % battery required
  
  // Prediction
  final bool enableNextChapterPrediction;
  
  // Cache settings
  final int cacheRetentionDays;
  final int maxCacheSizeMB;
  
  // Metadata
  final double measuredRTF; // Measured Real-Time Factor
  final DateTime tunedAt;
  
  factory EngineConfig.fromJson(Map<String, dynamic> json) { ... }
  Map<String, dynamic> toJson() { ... }
}

enum DeviceTier {
  flagship,  // RTF < 0.3
  midRange,  // RTF 0.3-0.5
  budget,    // RTF 0.5-0.8
  legacy,    // RTF > 0.8
}
```

---

## Integration with Existing Plans

### Supertonic Plan Enhancement

```markdown
## Phase 0: Auto-Tuning (Before Phase 1)

Before implementing optimization, auto-tune for user's device:

1. Run 30-segment synthesis test
2. Measure RTF, battery impact
3. Select optimal config:
   - Flagship: prefetchWindow=15, concurrency=2
   - Mid-range: prefetchWindow=10, concurrency=1
   - Budget: prefetchWindow=5, concurrency=1
4. Apply config to Phase 1 implementation
```

### Piper Plan Enhancement

```markdown
## Phase 0: Auto-Tuning (Before Phase 1)

Piper has more variability, so tuning is critical:

1. Run 30-segment synthesis test
2. If RTF > 0.6, use conservative config:
   - prefetchWindow=5 (vs 15 for fast devices)
   - preSynthesizeCount=1 (vs 2 for fast devices)
3. If RTF < 0.4, use aggressive config:
   - prefetchWindow=15
   - Consider parallel first+second synthesis
```

---

## Benefits

### For Users
✅ **Automatic optimization** - No manual tuning required  
✅ **Device-appropriate** - Works well on any device  
✅ **Battery-efficient** - Doesn't drain budget phones  
✅ **Performance maximized** - Flagship phones use full potential

### For Developers
✅ **Single codebase** - Shared logic, different configs  
✅ **Future-proof** - New devices automatically tuned  
✅ **Data-driven** - Real measurements, not guesses  
✅ **Per-engine granularity** - Kokoro/Piper/Supertonic each optimized

---

## Testing Strategy

### Test Matrix

| Device Tier | Test Device | Piper RTF | Supertonic RTF | Expected Config |
|-------------|-------------|-----------|----------------|-----------------|
| **Flagship** | Galaxy S24 Ultra | 0.25x | 0.18x | Aggressive prefetch |
| **Mid-range** | Pixel 7a | 0.38x | 0.26x | Balanced prefetch |
| **Budget** | Moto G Power | 0.55x | 0.42x | Conservative prefetch |
| **Legacy** | Galaxy A32 | 0.75x | 0.68x | Minimal prefetch |

### Validation Tests

1. **Run auto-tuning on all test devices**
2. **Verify selected config matches expectations**
3. **Run playback benchmark with auto-tuned config**
4. **Measure buffering time** - should be 0s on all devices (different strategies)
5. **Measure battery drain** - should be <5% on all devices

---

## Implementation Timeline

### Week 0: Auto-Tuning Infrastructure
- [ ] Create `DevicePerformanceProfiler` class
- [ ] Create `AutoTuner` class
- [ ] Create `EngineConfigManager` class
- [ ] Add UI for manual optimization trigger
- [ ] Add periodic re-tuning scheduler

### Week 1: Integration with Supertonic
- [ ] Add Phase 0 (auto-tuning) to Supertonic plan
- [ ] Test on 3 device tiers
- [ ] Validate config selection
- [ ] Implement Phase 1 with auto-tuned config

### Week 2: Integration with Piper
- [ ] Add Phase 0 (auto-tuning) to Piper plan
- [ ] Test on 3 device tiers
- [ ] Validate config selection
- [ ] Implement Phase 1+2 with auto-tuned config

### Week 3: Integration with Kokoro (pending benchmark)
- [ ] Wait for Kokoro benchmark results
- [ ] Create Kokoro-specific auto-tuning thresholds
- [ ] Test on 3 device tiers

---

## Configuration Examples

### Flagship Device (Galaxy S24 Ultra)
```json
{
  "engineId": "piper:en_GB-alan-medium",
  "deviceTier": "flagship",
  "prefetchWindowSize": 20,
  "prefetchConcurrency": 3,
  "preSynthesizeCount": 2,
  "enableFullChapterPrefetch": true,
  "fullChapterBatteryThreshold": 30,
  "enableNextChapterPrediction": true,
  "cacheRetentionDays": 14,
  "maxCacheSizeMB": 1000,
  "measuredRTF": 0.25,
  "tunedAt": "2026-01-07T19:00:00Z"
}
```

### Budget Device (Moto G Power)
```json
{
  "engineId": "piper:en_GB-alan-medium",
  "deviceTier": "budget",
  "prefetchWindowSize": 5,
  "prefetchConcurrency": 1,
  "preSynthesizeCount": 1,
  "enableFullChapterPrefetch": false,
  "fullChapterBatteryThreshold": 80,
  "enableNextChapterPrediction": false,
  "cacheRetentionDays": 3,
  "maxCacheSizeMB": 200,
  "measuredRTF": 0.55,
  "tunedAt": "2026-01-07T19:00:00Z"
}
```

---

## Success Metrics

### Auto-Tuning Adoption
- **Target**: 80% of users run auto-tuning (either automatic or manual)
- **Measure**: Track tuning completion rate

### Device Tier Distribution
- Expected: 20% flagship, 50% mid-range, 25% budget, 5% legacy
- Track actual distribution to validate assumptions

### Buffering Elimination by Tier
- **Target**: 0s buffering on all tiers
- Flagship: 0s (aggressive prefetch)
- Mid-range: 0s (balanced prefetch)
- Budget: <1s (conservative prefetch)
- Legacy: <3s (minimal prefetch, acceptable for old devices)

### Battery Impact by Tier
- Flagship: <3% (can handle it)
- Mid-range: <4% (balanced)
- Budget: <5% (conservative limits drain)
- Legacy: <3% (minimal prefetch = minimal drain)

---

**Status**: Ready to implement  
**Priority**: **P0** (Foundation for all optimizations)  
**Effort**: 1 week (Week 0 before Phase 1 of any engine)  
**Confidence**: **Very High** (proven approach, similar to graphics settings in games)
