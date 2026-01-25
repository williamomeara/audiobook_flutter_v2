# Edge Case Handlers

Edge case handlers coordinate graceful transitions when configuration or system state changes during active playback. They live in `packages/playback/lib/src/edge_cases/`.

## Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          EDGE CASE HANDLERS                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌────────────────────┐    ┌────────────────────┐    ┌─────────────────┐   │
│  │ RateChangeHandler  │    │ VoiceChangeHandler │    │ MemoryPressure  │   │
│  │                    │    │                    │    │    Handler      │   │
│  │ • Debounces rapid  │    │ • Cancels old      │    │                 │   │
│  │   rate changes     │    │   prefetch         │    │ • Reduces       │   │
│  │ • Cancels prefetch │    │ • Invalidates      │    │   prefetch      │   │
│  │   on significant   │    │   context          │    │ • Pauses/resumes│   │
│  │   delta            │    │ • Resynthesizes    │    │   synthesis     │   │
│  │ • Restarts after   │    │   current segment  │    │ • Trims cache   │   │
│  │   stabilization    │    │                    │    │                 │   │
│  └─────────┬──────────┘    └─────────┬──────────┘    └────────┬────────┘   │
│            │                         │                        │            │
│            └─────────────────────────┼────────────────────────┘            │
│                                      │                                      │
│                                      ▼                                      │
│                          ┌──────────────────────┐                           │
│                          │  AutoTuneRollback    │                           │
│                          │                      │                           │
│                          │  • Snapshots config  │                           │
│                          │  • Monitors metrics  │                           │
│                          │  • Triggers rollback │                           │
│                          │    if degradation    │                           │
│                          └──────────────────────┘                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Handler Details

### 1. RateChangeHandler

**File:** `rate_change_handler.dart`

**Purpose:** Handle playback rate changes with debouncing to avoid excessive cache invalidation.

#### Behavior

```
User scrubs rate slider rapidly: 1.0 → 1.25 → 1.5 → 1.75 → 2.0
                                   ↓     ↓     ↓     ↓     ↓
                              Debounced (500ms default)
                                          ↓
                              Only final rate (2.0) applied
```

#### State Machine

```
┌─────────┐  handleRateChange()  ┌────────────┐  timer expires  ┌──────────────┐
│  IDLE   │ ─────────────────────► DEBOUNCING │ ────────────────► RATE_APPLIED │
└─────────┘                       └────────────┘                 └──────────────┘
     ▲                                  │                              │
     │                                  │ new change                   │
     │                                  └──────────┐                   │
     │                                             │                   │
     └─────────────────────────────────────────────┴───────────────────┘
```

#### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `debounceDelay` | 500ms | Wait time before applying rate |
| `rateIndependentSynthesis` | true | If true, cached audio reusable across rates |
| Cancel threshold | 0.25 | Rate delta that triggers immediate prefetch cancel |

#### Callbacks

| Callback | When Called |
|----------|-------------|
| `onRateStabilized(rate)` | After debounce, with final rate |
| `onCancelPrefetch(reason)` | When rate change > 0.25 or after stabilization |
| `onRestartPrefetch()` | After rate stabilized |

#### Usage

```dart
final handler = RateChangeHandler(
  onRateStabilized: (rate) => player.setSpeed(rate),
  onCancelPrefetch: (reason) => scheduler.cancelPrefetch(reason),
  onRestartPrefetch: () => scheduler.startPrefetch(),
);

// Called on every slider change
handler.handleRateChange(newRate);

// Force immediate application (e.g., on slider release)
await handler.applyImmediately();
```

---

### 2. VoiceChangeHandler

**File:** `voice_change_handler.dart`

**Purpose:** Handle voice changes mid-playback by canceling old prefetch and resynthesizing.

#### Behavior

```
Voice change: kokoro_af_alloy → piper_en_us_lessac
              ↓
    1. Cancel in-progress prefetch for old voice
    2. Preserve current playback position
    3. Invalidate prefetch context (triggers scheduler reset)
    4. Synthesize current segment with new voice
    5. Resume playback
```

#### State Machine

```
┌─────────┐  handleVoiceChange()  ┌─────────────────┐
│  IDLE   │ ──────────────────────► CANCEL_PREFETCH │
└─────────┘                        └───────┬─────────┘
     ▲                                     │
     │                                     ▼
     │                            ┌─────────────────┐
     │                            │ INVALIDATE_CTX  │
     │                            └───────┬─────────┘
     │                                    │
     │                                    ▼
     │                            ┌─────────────────┐
     │                            │ RESYNTHESIZE    │
     │                            └───────┬─────────┘
     │                                    │
     │           success/failure          │
     └────────────────────────────────────┘
```

#### Key Features

- **Atomic operation:** If resynthesis fails, old voice is restored
- **Mutex protection:** Ignores voice change requests while one is in progress
- **Position preservation:** Maintains playback position across voice switch

#### Callbacks

| Callback | When Called |
|----------|-------------|
| `onCancelPrefetch(reason)` | Immediately on voice change |
| `onInvalidateContext()` | After prefetch cancelled |
| `onResynthesizeCurrent()` | After context invalidated |

---

### 3. MemoryPressureHandler

**File:** `memory_pressure_handler.dart`

**Purpose:** Handle OS memory pressure events by reducing prefetch and trimming cache.

#### Pressure Levels

```dart
enum MemoryPressure {
  none,     // Normal operation
  moderate, // Reduce prefetch, trim cache
  critical, // Pause synthesis, aggressive trim
}
```

#### State Machine

```
┌──────────┐
│   NONE   │ ◄─────────────────────────────────────────────────────────┐
└────┬─────┘                                                           │
     │ moderate pressure                                               │
     ▼                                                                 │
┌──────────┐  critical pressure  ┌──────────────┐  recovery timer     │
│ MODERATE │ ───────────────────► │   CRITICAL   │ ────────────────────┤
│          │                      │              │                     │
│ • Reduce │                      │ • Pause      │                     │
│   prefetch                      │   synthesis  │                     │
│ • Trim   │                      │ • Aggressive │                     │
│   cache  │                      │   trim       │                     │
└──────────┘                      └──────────────┘                     │
     │                                                                 │
     │ recovery timer (10s)                                            │
     └─────────────────────────────────────────────────────────────────┘
```

#### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `recoveryDelay` | 10s | Wait after pressure before resuming |

#### Callbacks

| Callback | When Called |
|----------|-------------|
| `onReducePrefetch(level)` | Moderate or critical pressure |
| `onPauseSynthesis(level)` | Critical pressure only |
| `onTrimCache(level)` | Any pressure level |
| `onResumeSynthesis(level)` | After recovery delay with no new pressure |

#### Integration with Android

Integrates with Android's `ComponentCallbacks2.onTrimMemory()`:

```dart
// In Android-specific code
@override
void onTrimMemory(int level) {
  final pressure = switch (level) {
    TRIM_MEMORY_RUNNING_CRITICAL => MemoryPressure.critical,
    TRIM_MEMORY_RUNNING_LOW => MemoryPressure.moderate,
    _ => MemoryPressure.none,
  };
  handler.handlePressure(pressure);
}
```

---

### 4. AutoTuneRollback

**File:** `auto_tune_rollback.dart`

**Purpose:** Maintain configuration snapshots and automatically rollback if performance degrades.

#### Rollback Triggers

| Trigger | Threshold | Description |
|---------|-----------|-------------|
| Buffer underrun rate | >50% increase vs baseline | Playback gaps increased significantly |
| Synthesis failure rate | >10% absolute | Too many syntheses failing |
| Manual request | N/A | User or code requests rollback |

#### State Machine

```
┌──────────┐  saveSnapshot()  ┌───────────────┐
│  NORMAL  │ ────────────────► SNAPSHOT_SAVED │
└──────────┘                  └───────┬───────┘
     ▲                                │
     │                      startCalibration()
     │                                │
     │                                ▼
     │                        ┌───────────────┐
     │                        │  CALIBRATING  │
     │                        └───────┬───────┘
     │                                │
     │                      endCalibration()
     │                                │
     │                                ▼
     │                        ┌───────────────┐
     │                        │  MONITORING   │
     │                        └───────┬───────┘
     │                                │
     │                 checkForRollback()
     │                     │         │
     │            no rollback     rollback needed
     │                     │         │
     │                     ▼         ▼
     │            ┌───────────┐  ┌───────────┐
     │            │ CONFIRMED │  │ ROLLBACK  │
     │            └───────────┘  └─────┬─────┘
     │                                 │
     │            clearSnapshots()     │
     └─────────────────────────────────┘
```

#### ConfigSnapshot

Stores configuration at a point in time:

```dart
class ConfigSnapshot {
  final int prefetchConcurrency;     // 1-4
  final bool parallelSynthesisEnabled;
  final int bufferTargetMs;
  final DateTime timestamp;
  final String reason;               // e.g., "pre-calibration"
}
```

#### PerformanceMetrics

Metrics used to evaluate if rollback is needed:

```dart
class PerformanceMetrics {
  final int bufferUnderrunCount;     // Playback gaps
  final int synthesisFailureCount;   // Failed syntheses
  final double avgSynthesisTimeMs;   // Average synthesis duration
  final int measurementPeriodMs;     // How long we measured

  double get bufferUnderrunRate;     // Underruns per hour
  double get synthesisFailureRate;   // Failures per synthesis
}
```

#### Usage

```dart
final rollback = AutoTuneRollback();

// Before calibration: snapshot current config
rollback.saveSnapshot(ConfigSnapshot(
  prefetchConcurrency: 2,
  parallelSynthesisEnabled: true,
  bufferTargetMs: 30000,
  timestamp: DateTime.now(),
  reason: 'pre-calibration',
));

// Set baseline metrics
rollback.setBaseline(currentMetrics);

// Start calibration
rollback.startCalibration();
// ... calibration runs ...
rollback.endCalibration();

// Monitor for degradation
final decision = rollback.checkForRollback(newMetrics);
if (decision.needsRollback) {
  final snapshot = decision.snapshot!;
  // Apply snapshot config
  applyConfig(snapshot);
}
```

---

## Handler Integration

### With BufferScheduler

```dart
class BufferScheduler {
  late final RateChangeHandler _rateHandler;
  late final VoiceChangeHandler _voiceHandler;
  late final MemoryPressureHandler _memoryHandler;

  BufferScheduler() {
    _rateHandler = RateChangeHandler(
      onCancelPrefetch: _cancelPrefetch,
      onRestartPrefetch: _startPrefetch,
      onRateStabilized: _applyRate,
    );
    
    _voiceHandler = VoiceChangeHandler(
      onCancelPrefetch: _cancelPrefetch,
      onInvalidateContext: _invalidateContext,
      onResynthesizeCurrent: _resynthesizeCurrent,
    );
    
    _memoryHandler = MemoryPressureHandler(
      onReducePrefetch: _reducePrefetchWindow,
      onPauseSynthesis: _pauseSynthesis,
      onTrimCache: _trimCache,
      onResumeSynthesis: _resumeSynthesis,
    );
  }
}
```

### Event Flow Example: Rate Change During Prefetch

```
1. User drags rate slider from 1.0 to 2.0 rapidly
2. RateChangeHandler receives multiple handleRateChange() calls
3. Each call resets debounce timer (500ms)
4. If change > 0.25, prefetch cancelled immediately
5. After 500ms of no changes, final rate applied
6. BufferScheduler receives onRestartPrefetch() callback
7. Prefetch resumes with new rate (or reuses cache if rate-independent)
```

### Event Flow Example: Memory Pressure During Playback

```
1. Android sends TRIM_MEMORY_RUNNING_CRITICAL
2. MemoryPressureHandler receives handlePressure(critical)
3. Synthesis paused via onPauseSynthesis()
4. Prefetch window reduced via onReducePrefetch()
5. Cache trimmed via onTrimCache()
6. Recovery timer started (10s)
7. If no new pressure in 10s, synthesis resumed via onResumeSynthesis()
```

---

## Testing

Test files in `packages/playback/test/edge_cases/`:

| File | Tests |
|------|-------|
| `rate_change_handler_test.dart` | Debouncing, cancel thresholds, immediate apply |
| `voice_change_handler_test.dart` | Cancellation, context invalidation, failure recovery |
| `memory_pressure_handler_test.dart` | Pressure levels, recovery timing |
| `auto_tune_rollback_test.dart` | Snapshot management, rollback triggers |

---

## Related Documentation

- [Audio Synthesis Pipeline](./audio_synthesis_pipeline_state_machine.md) - How prefetch and synthesis work
- [Smart Synthesis](./smart-synthesis/README.md) - Prefetch strategies
- [Playback Screen State Machine](./playback_screen_state_machine.md) - UI state integration
