# Technical Implementation Guide
## Smart Audio Synthesis Architecture

**Companion to**: `BUFFERING_REDUCTION_STRATEGY.md`

This document provides technical implementation details for the buffering reduction strategies.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          User Interface Layer                        │
│  (PlaybackScreen, Controls, Chapter Selection)                      │
└───────────────┬──────────────────────────────────────────┬──────────┘
                │                                          │
                │ User Actions                             │ State Updates
                │ (play, pause, seek, switch chapter)      │
                ▼                                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Playback Controller                            │
│  • Manages playback state                                           │
│  • Coordinates synthesis and audio output                           │
│  • Handles user commands                                            │
└───────────────┬──────────────────────────────────────────┬──────────┘
                │                                          │
                │ Synthesis Requests                       │ Audio Ready
                │                                          │
                ▼                                          ▼
┌──────────────────────────────┐      ┌──────────────────────────────┐
│   Smart Synthesis Manager    │      │      Audio Output             │
│  ┌─────────────────────────┐ │      │  • just_audio player         │
│  │  Priority Queue         │ │      │  • Audio session management  │
│  │  • Immediate            │ │      │  • Playback rate control     │
│  │  • High                 │ │      └──────────────────────────────┘
│  │  • Medium               │ │
│  │  • Low                  │ │
│  └─────────────────────────┘ │
│  ┌─────────────────────────┐ │
│  │  Prediction Engine      │ │      ┌──────────────────────────────┐
│  │  • Next chapter         │ │      │      Audio Cache              │
│  │  • Seek hotspots        │ │◄────►│  • Persistent storage        │
│  │  • User behavior        │ │      │  • Cache hit/miss tracking   │
│  └─────────────────────────┘ │      │  • Smart eviction            │
│  ┌─────────────────────────┐ │      └──────────────────────────────┘
│  │  Resource Manager       │ │
│  │  • Battery monitor      │ │
│  │  • Synthesis modes      │ │      ┌──────────────────────────────┐
│  │  • Cancellation         │ │      │    TTS Routing Engine         │
│  └─────────────────────────┘ │      │  • Kokoro adapter            │
└───────────────┬──────────────┘      │  • Piper adapter             │
                │                     │  • Supertonic adapter        │
                │ Synthesis Tasks     └──────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   Synthesis Worker Pool                             │
│  • Multiple isolates for parallel synthesis                         │
│  • Task scheduling and priority handling                            │
│  • Progress tracking and cancellation                               │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. Smart Synthesis Manager

**Location**: `packages/playback/lib/src/smart_synthesis_manager.dart`

**Responsibilities**:
- Prioritize synthesis requests
- Predict what to synthesize next
- Manage resource constraints (battery, storage)
- Cancel unnecessary synthesis

**Key Classes**:

```dart
/// Priority levels for synthesis requests
enum SynthesisPriority {
  immediate,  // User pressed play, needs NOW (0-500ms target)
  high,       // Next segment during playback (1-2s target)
  medium,     // Predicted next chapter (5-10s target)
  low,        // Opportunistic prefetch (whenever idle)
}

/// Synthesis request with priority and context
class SynthesisRequest {
  final String bookId;
  final String chapterId;
  final int segmentIndex;
  final SynthesisPriority priority;
  final Duration timeout;
  final CancellationToken? cancellationToken;
  
  /// When this request was created (for timeout/staleness checks)
  final DateTime createdAt;
  
  /// Reason for synthesis (for debugging/analytics)
  final SynthesisReason reason;
}

enum SynthesisReason {
  userPlay,           // User pressed play button
  prefetch,           // Background prefetch during playback
  predictedNext,      // Predicted user will play next
  seekHotspot,        // Likely seek target
  opportunistic,      // Idle time synthesis
}

/// Main coordinator for smart synthesis
class SmartSynthesisManager {
  final TtsRoutingEngine _ttsEngine;
  final AudioCache _cache;
  final ResourceMonitor _resourceMonitor;
  final BehaviorPredictor _behaviorPredictor;
  
  /// Priority queue of pending synthesis requests
  final PriorityQueue<SynthesisRequest> _queue;
  
  /// Currently executing synthesis tasks
  final Map<String, Future<void>> _activeTasks;
  
  /// Submit a synthesis request (returns immediately)
  Future<void> requestSynthesis(SynthesisRequest request) async {
    // Check if already cached
    if (await _cache.isReady(request.cacheKey)) {
      return; // Already have it!
    }
    
    // Check if already in progress
    if (_activeTasks.containsKey(request.id)) {
      return; // Already working on it!
    }
    
    // Add to priority queue
    _queue.add(request);
    
    // Start processing if worker available
    _processQueue();
  }
  
  /// Main synthesis loop
  Future<void> _processQueue() async {
    // Check resource constraints
    if (!_resourceMonitor.canSynthesize()) {
      return; // Battery too low, storage full, etc.
    }
    
    // Get highest priority request
    final request = _queue.removeFirst();
    
    // Check if request is stale
    if (_isStale(request)) {
      return _processQueue(); // Skip and process next
    }
    
    // Execute synthesis
    final task = _executeSynthesis(request);
    _activeTasks[request.id] = task;
    
    try {
      await task;
    } finally {
      _activeTasks.remove(request.id);
      // Process next request
      if (_queue.isNotEmpty) {
        _processQueue();
      }
    }
  }
  
  /// Check if request is still relevant
  bool _isStale(SynthesisRequest request) {
    // User navigated away from this chapter
    if (request.chapterId != _currentChapterId) return true;
    
    // Request too old (user probably moved on)
    final age = DateTime.now().difference(request.createdAt);
    if (age > request.timeout) return true;
    
    // Cancellation token triggered
    if (request.cancellationToken?.isCancelled ?? false) return true;
    
    return false;
  }
  
  /// Execute actual synthesis
  Future<void> _executeSynthesis(SynthesisRequest request) async {
    final segment = _getSegment(request);
    
    await _ttsEngine.synthesizeToWavFile(
      voiceId: request.voiceId,
      text: segment.text,
      playbackRate: 1.0,
    );
    
    // Update analytics
    _trackSynthesisComplete(request);
  }
  
  /// Predict and queue upcoming synthesis needs
  Future<void> predictAndQueue(PlaybackState state) async {
    final predictions = await _behaviorPredictor.predict(state);
    
    for (final prediction in predictions) {
      await requestSynthesis(SynthesisRequest(
        bookId: prediction.bookId,
        chapterId: prediction.chapterId,
        segmentIndex: prediction.segmentIndex,
        priority: prediction.priority,
        reason: SynthesisReason.predictedNext,
        timeout: Duration(minutes: 5),
      ));
    }
  }
}
```

---

### 2. Behavior Predictor

**Location**: `packages/playback/lib/src/behavior_predictor.dart`

**Responsibilities**:
- Analyze user behavior patterns
- Predict next chapter, seek targets
- Recommend synthesis priorities

```dart
/// Predicts user behavior for smart prefetch
class BehaviorPredictor {
  final UserBehaviorTracker _tracker;
  
  /// Predict what user will do next
  Future<List<SynthesisPrediction>> predict(PlaybackState state) async {
    final predictions = <SynthesisPrediction>[];
    
    // Predict next chapter (if user is sequential reader)
    if (_isLikelyToContinue(state)) {
      predictions.add(SynthesisPrediction(
        type: PredictionType.nextChapter,
        chapterId: _getNextChapterId(state.currentChapter),
        segmentIndex: 0, // First segment
        priority: SynthesisPriority.medium,
        confidence: _calculateSequentialConfidence(),
      ));
    }
    
    // Predict seek hotspots
    predictions.addAll(_predictSeekTargets(state));
    
    // Predict extended window if binge listener
    if (_isBingeListener()) {
      predictions.addAll(_predictExtendedWindow(state));
    }
    
    return predictions;
  }
  
  /// Check if user is likely to continue to next chapter
  bool _isLikelyToContinue(PlaybackState state) {
    // At 80% of current chapter
    if (state.position / state.duration < 0.8) return false;
    
    // User has high completion rate
    if (_tracker.averageCompletionRate < 0.7) return false;
    
    // User has been reading sequentially
    if (!_tracker.isSequentialReader(window: 3)) return false;
    
    return true;
  }
  
  /// Predict likely seek targets
  List<SynthesisPrediction> _predictSeekTargets(PlaybackState state) {
    final hotspots = <SynthesisPrediction>[];
    
    // Chapter start (replay)
    hotspots.add(SynthesisPrediction(
      type: PredictionType.seekHotspot,
      chapterId: state.currentChapter,
      segmentIndex: 0,
      priority: SynthesisPriority.low,
      confidence: 0.3,
    ));
    
    // User bookmarks
    for (final bookmark in state.chapter.bookmarks) {
      final segmentIndex = _positionToSegmentIndex(bookmark.position);
      hotspots.add(SynthesisPrediction(
        type: PredictionType.seekHotspot,
        chapterId: state.currentChapter,
        segmentIndex: segmentIndex,
        priority: SynthesisPriority.low,
        confidence: 0.5,
      ));
    }
    
    // Historical seek patterns (this user frequently seeks to similar spots)
    final frequentSeeks = _tracker.getFrequentSeekTargets(state.chapter);
    for (final target in frequentSeeks) {
      hotspots.add(SynthesisPrediction(
        type: PredictionType.seekHotspot,
        chapterId: state.currentChapter,
        segmentIndex: target.segmentIndex,
        priority: SynthesisPriority.low,
        confidence: target.frequency,
      ));
    }
    
    return hotspots;
  }
}

/// Prediction result
class SynthesisPrediction {
  final PredictionType type;
  final String chapterId;
  final int segmentIndex;
  final SynthesisPriority priority;
  final double confidence; // 0.0 - 1.0
}

enum PredictionType {
  nextChapter,
  seekHotspot,
  extendedWindow,
}
```

---

### 3. Resource Monitor

**Location**: `packages/playback/lib/src/resource_monitor.dart`

**Responsibilities**:
- Monitor battery level and charging state
- Track storage usage
- Enforce synthesis constraints

```dart
/// Monitors device resources and enforces synthesis constraints
class ResourceMonitor {
  final Battery _battery;
  final StorageMonitor _storage;
  
  Stream<SynthesisMode> get synthesisMode => _synthesisModeController.stream;
  final _synthesisModeController = StreamController<SynthesisMode>.broadcast();
  
  SynthesisMode _currentMode = SynthesisMode.balanced;
  
  /// Initialize and start monitoring
  void initialize() {
    // Listen to battery changes
    _battery.onBatteryStateChanged.listen(_updateSynthesisMode);
    
    // Listen to storage changes
    _storage.onStorageChanged.listen(_checkStorageConstraints);
    
    // Update immediately
    _updateSynthesisMode(_battery.batteryLevel);
  }
  
  /// Determine appropriate synthesis mode based on battery
  void _updateSynthesisMode(int batteryLevel) {
    final wasCharging = _battery.isCharging;
    
    SynthesisMode newMode;
    if (_battery.isCharging) {
      newMode = SynthesisMode.maximum;
    } else if (batteryLevel < 20) {
      newMode = SynthesisMode.conservative;
    } else if (batteryLevel < 50) {
      newMode = SynthesisMode.balanced;
    } else {
      newMode = SynthesisMode.aggressive;
    }
    
    if (newMode != _currentMode) {
      _currentMode = newMode;
      _synthesisModeController.add(newMode);
      print('[ResourceMonitor] Synthesis mode changed to: $newMode');
    }
  }
  
  /// Check if synthesis is allowed given current constraints
  bool canSynthesize() {
    // Battery too low and not charging
    if (_battery.batteryLevel < 10 && !_battery.isCharging) {
      return false;
    }
    
    // Storage nearly full
    if (_storage.availableBytes < 50 * 1024 * 1024) { // 50MB minimum
      return false;
    }
    
    // User explicitly disabled prefetch
    if (!_settings.prefetchEnabled) {
      return false;
    }
    
    return true;
  }
  
  /// Get maximum concurrent synthesis tasks based on mode
  int get maxConcurrentTasks {
    switch (_currentMode) {
      case SynthesisMode.conservative:
        return 1; // One at a time
      case SynthesisMode.balanced:
        return 2; // Two parallel
      case SynthesisMode.aggressive:
        return 3; // Three parallel
      case SynthesisMode.maximum:
        return 4; // Go wild (charging)
    }
  }
}

enum SynthesisMode {
  conservative,  // Low battery, minimize synthesis
  balanced,      // Default, moderate prefetch
  aggressive,    // Good battery, full prefetch
  maximum,       // Charging, unlimited synthesis
}
```

---

### 4. User Behavior Tracker

**Location**: `packages/playback/lib/src/user_behavior_tracker.dart`

**Responsibilities**:
- Track user actions (play, pause, seek, chapter changes)
- Calculate statistics (completion rate, sequential reading, etc.)
- Persist behavior data for long-term learning

```dart
/// Tracks and analyzes user behavior for prediction
class UserBehaviorTracker {
  final SharedPreferences _prefs;
  
  /// Track when user switches chapters
  Future<void> recordChapterSwitch({
    required String fromChapterId,
    required String toChapterId,
    required double completionPercent,
  }) async {
    final event = BehaviorEvent(
      type: BehaviorEventType.chapterSwitch,
      timestamp: DateTime.now(),
      fromChapter: fromChapterId,
      toChapter: toChapterId,
      completionPercent: completionPercent,
    );
    
    await _persistEvent(event);
    _updateStatistics(event);
  }
  
  /// Track when user seeks within chapter
  Future<void> recordSeek({
    required String chapterId,
    required Duration fromPosition,
    required Duration toPosition,
  }) async {
    final event = BehaviorEvent(
      type: BehaviorEventType.seek,
      timestamp: DateTime.now(),
      chapterId: chapterId,
      fromPosition: fromPosition,
      toPosition: toPosition,
    );
    
    await _persistEvent(event);
  }
  
  /// Calculate average chapter completion rate
  double get averageCompletionRate {
    final events = _getRecentEvents(type: BehaviorEventType.chapterSwitch);
    if (events.isEmpty) return 0.5; // Default assumption
    
    final sum = events.fold<double>(
      0.0,
      (sum, event) => sum + (event.completionPercent ?? 0),
    );
    
    return sum / events.length;
  }
  
  /// Check if user reads chapters sequentially
  bool isSequentialReader({int window = 5}) {
    final recentSwitches = _getRecentEvents(
      type: BehaviorEventType.chapterSwitch,
      limit: window,
    );
    
    if (recentSwitches.length < 3) return true; // Too early, assume yes
    
    // Count sequential transitions (chapter N → chapter N+1)
    int sequential = 0;
    for (var i = 0; i < recentSwitches.length - 1; i++) {
      final from = recentSwitches[i].fromChapter;
      final to = recentSwitches[i].toChapter;
      if (_isNextChapter(from, to)) {
        sequential++;
      }
    }
    
    // Consider sequential if 70%+ of transitions are forward
    return sequential / (recentSwitches.length - 1) >= 0.7;
  }
  
  /// Get frequently targeted seek positions for a chapter
  List<SeekTarget> getFrequentSeekTargets(Chapter chapter) {
    final seeks = _getSeeksForChapter(chapter.id);
    
    // Group seeks into 30-second buckets
    final buckets = <int, int>{}; // bucket index → count
    for (final seek in seeks) {
      final bucketIndex = seek.toPosition.inSeconds ~/ 30;
      buckets[bucketIndex] = (buckets[bucketIndex] ?? 0) + 1;
    }
    
    // Find hotspots (buckets with 3+ seeks)
    final hotspots = buckets.entries
        .where((entry) => entry.value >= 3)
        .map((entry) {
          final position = Duration(seconds: entry.key * 30);
          final segmentIndex = _positionToSegmentIndex(position, chapter);
          return SeekTarget(
            segmentIndex: segmentIndex,
            position: position,
            frequency: entry.value / seeks.length,
          );
        })
        .toList();
    
    return hotspots;
  }
  
  /// User profile classification
  UserProfile get profile {
    if (averageCompletionRate > 0.8 && isSequentialReader()) {
      return UserProfile.bingeListener;
    } else if (_hasHighSeekRate()) {
      return UserProfile.skipperSeeker;
    } else {
      return UserProfile.casualListener;
    }
  }
}

enum UserProfile {
  bingeListener,    // Listens to many chapters sequentially
  casualListener,   // Listens for short periods
  skipperSeeker,    // Frequently seeks and skips
}

class SeekTarget {
  final int segmentIndex;
  final Duration position;
  final double frequency; // 0.0 - 1.0
}
```

---

### 5. Modified Playback Controller

**Location**: `packages/playback/lib/src/playback_controller.dart` (existing file)

**Changes**: Integrate SmartSynthesisManager

```dart
class PlaybackController {
  final SmartSynthesisManager _synthesisManager;
  
  /// Load chapter with pre-synthesis
  Future<void> loadChapter(Chapter chapter) async {
    final segments = _segmentText(chapter.content);
    
    // ═══════════════════════════════════════════════════════════════
    // NEW: Request immediate synthesis of first segment
    // ═══════════════════════════════════════════════════════════════
    await _synthesisManager.requestSynthesis(SynthesisRequest(
      bookId: chapter.bookId,
      chapterId: chapter.id,
      segmentIndex: 0,
      priority: SynthesisPriority.immediate,
      reason: SynthesisReason.userPlay,
      timeout: Duration(seconds: 10),
    ));
    
    // ═══════════════════════════════════════════════════════════════
    // NEW: Start predictive synthesis based on user behavior
    // ═══════════════════════════════════════════════════════════════
    _synthesisManager.predictAndQueue(currentState);
  }
  
  /// Start playback (first segment already synthesized!)
  Future<void> play() async {
    // First segment should already be cached from loadChapter()
    final cached = await _cache.isReady(_getCurrentSegmentCacheKey());
    
    if (!cached) {
      // Fallback: shouldn't happen, but handle gracefully
      print('[PlaybackController] WARNING: First segment not pre-synthesized');
      await _speakCurrent(); // Old JIT synthesis
    } else {
      // ✅ Play immediately (0ms buffering!)
      await _playFromCache();
    }
    
    // Start background prefetch for upcoming segments
    _startBackgroundPrefetch();
  }
  
  /// Background prefetch during playback
  Future<void> _startBackgroundPrefetch() async {
    // Request synthesis for next 10 segments
    for (var i = _currentIndex + 1; i < _currentIndex + 11; i++) {
      if (i >= _segments.length) break;
      
      await _synthesisManager.requestSynthesis(SynthesisRequest(
        bookId: _currentBookId,
        chapterId: _currentChapterId,
        segmentIndex: i,
        priority: SynthesisPriority.high,
        reason: SynthesisReason.prefetch,
        timeout: Duration(minutes: 5),
      ));
    }
  }
}
```

---

## Database Schema

**For tracking user behavior**:

```sql
-- User behavior events table
CREATE TABLE behavior_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_type TEXT NOT NULL, -- 'chapter_switch', 'seek', 'pause', 'resume'
  timestamp INTEGER NOT NULL,
  book_id TEXT,
  chapter_id TEXT,
  from_position INTEGER, -- milliseconds
  to_position INTEGER, -- milliseconds
  completion_percent REAL,
  metadata TEXT -- JSON for additional data
);

-- Index for fast queries
CREATE INDEX idx_behavior_timestamp ON behavior_events(timestamp);
CREATE INDEX idx_behavior_chapter ON behavior_events(chapter_id);

-- User statistics table (cached calculations)
CREATE TABLE user_statistics (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Example statistics:
-- 'average_completion_rate' → '0.85'
-- 'is_sequential_reader' → 'true'
-- 'user_profile' → 'bingeListener'
```

---

## Configuration & Settings

**User-facing settings** in `Settings > Playback > Smart Synthesis`:

```dart
class SmartSynthesisSettings {
  /// Enable/disable smart pre-synthesis
  bool enabled = true;
  
  /// Synthesis aggressiveness
  SynthesisAggressiveness aggressiveness = SynthesisAggressiveness.balanced;
  
  /// Battery behavior
  bool reduceSynthesisOnLowBattery = true;
  int lowBatteryThreshold = 20; // percent
  
  bool fullPrefetchWhenCharging = true;
  
  /// Network behavior
  bool prefetchNextChapterOnWifi = true;
  
  /// Cache settings
  int maxCacheSizeMB = 500;
  bool persistCacheAcrossRestarts = true;
  int cacheRetentionDays = 7;
}

enum SynthesisAggressiveness {
  off,         // Disable smart synthesis, JIT only
  conservative, // First segment only
  balanced,    // First segment + immediate window (10 segments)
  aggressive,  // Full current chapter + next chapter first segment
}
```

---

## Analytics & Monitoring

**Track these metrics** for optimization:

```dart
class SynthesisAnalytics {
  /// Buffering metrics
  void recordBufferingEvent({
    required Duration duration,
    required String reason, // 'first_segment', 'cache_miss', 'seek'
  });
  
  /// Synthesis performance
  void recordSynthesisComplete({
    required int segmentIndex,
    required Duration synthesisTime,
    required SynthesisReason reason,
  });
  
  /// Cache performance
  void recordCacheAccess({
    required bool hit,
    required String segmentId,
  });
  
  /// Prediction accuracy
  void recordPrediction({
    required PredictionType type,
    required bool correct, // Did user actually play what we predicted?
  });
  
  /// Generate summary report
  AnalyticsReport generateReport() {
    return AnalyticsReport(
      totalBufferingTime: _totalBufferingMs,
      bufferingEvents: _bufferingEvents,
      cacheHitRate: _cacheHits / (_cacheHits + _cacheMisses),
      predictionAccuracy: _correctPredictions / _totalPredictions,
      averageSynthesisTime: _totalSynthesisMs / _synthesisCount,
    );
  }
}
```

---

## Testing Strategy

### Unit Tests

```dart
// Test prediction logic
test('BehaviorPredictor predicts next chapter for sequential reader', () {
  final predictor = BehaviorPredictor(tracker);
  
  // Simulate sequential reading pattern
  tracker.recordChapterSwitch(from: 'ch1', to: 'ch2', completion: 0.95);
  tracker.recordChapterSwitch(from: 'ch2', to: 'ch3', completion: 0.90);
  tracker.recordChapterSwitch(from: 'ch3', to: 'ch4', completion: 0.92);
  
  // At 80% of chapter 4, should predict chapter 5
  final state = PlaybackState(
    currentChapter: 'ch4',
    position: Duration(minutes: 8),
    duration: Duration(minutes: 10), // 80% complete
  );
  
  final predictions = await predictor.predict(state);
  
  expect(predictions.any((p) => p.type == PredictionType.nextChapter), true);
  expect(predictions.first.chapterId, 'ch5');
});

// Test resource constraints
test('ResourceMonitor blocks synthesis on low battery', () {
  final monitor = ResourceMonitor(battery, storage);
  
  battery.setBatteryLevel(15); // Low battery
  battery.setCharging(false);
  
  expect(monitor.canSynthesize(), false);
});
```

### Integration Tests

```dart
testWidgets('First segment pre-synthesis eliminates play button lag', (tester) async {
  final controller = await setupPlaybackController();
  
  // Load chapter
  await controller.loadChapter(testChapter);
  
  // Verify first segment synthesized
  final firstSegmentCached = await cache.isReady(firstSegmentKey);
  expect(firstSegmentCached, true);
  
  // Measure play latency
  final startTime = DateTime.now();
  await controller.play();
  final playLatency = DateTime.now().difference(startTime);
  
  // Should start playing immediately (<500ms)
  expect(playLatency.inMilliseconds, lessThan(500));
});
```

### Benchmark Tests

Extend existing benchmark in `developer_screen.dart`:

```dart
// Add pre-synthesis benchmark mode
enum BenchmarkMode {
  jit,           // Current just-in-time synthesis
  preSynthesis,  // With first-segment pre-synthesis
  fullPrefetch,  // With full chapter pre-synthesis
}

void _runBenchmark(String voiceId, BenchmarkMode mode) {
  // ... existing code ...
  
  if (mode == BenchmarkMode.preSynthesis) {
    // Pre-synthesize first segment before "play"
    await _synthesizeFirstSegment();
    // Then measure buffering (should be 0s for first segment)
  }
}
```

---

## Migration Path

### Phase 1: Add Infrastructure (Non-Breaking)
- Create `SmartSynthesisManager` class
- Create `BehaviorPredictor` class
- Create `ResourceMonitor` class
- Add user settings (default: off)

### Phase 2: Enable First-Segment Pre-Synthesis
- Modify `loadChapter()` to pre-synthesize first segment
- Add feature flag: `Features.preSynthesisEnabled`
- Default: disabled, A/B test with 10% of users

### Phase 3: Enable Predictive Synthesis
- Add behavior tracking
- Enable next-chapter prediction
- Enable seek hotspot prediction
- Gradually increase rollout to 50%, then 100%

### Phase 4: Full Smart Synthesis
- Enable all strategies
- Make default for all users
- Allow opt-out in settings

---

## Performance Targets

| Metric | Current | Phase 1 | Phase 2 | Target |
|--------|---------|---------|---------|--------|
| **First play latency** | 7.4s | 0.5s | 0.5s | <0.5s |
| **Seek latency (hotspot)** | 2.5s | 2.5s | 0.2s | <0.2s |
| **Chapter switch (sequential)** | 7.4s | 0.5s | 0.5s | <0.5s |
| **Cache hit rate** | ~0% | ~50% | ~95% | >95% |
| **Battery drain** | baseline | +2% | +5% | <5% |

---

## Conclusion

This architecture provides a **flexible, extensible foundation** for smart synthesis:

- ✅ **Priority-based synthesis** ensures critical needs met first
- ✅ **Resource awareness** respects battery and storage constraints
- ✅ **Behavior prediction** anticipates user needs
- ✅ **Analytics tracking** enables continuous optimization
- ✅ **User control** allows customization and opt-out

**Next**: Implement Phase 1 components and validate with benchmark tests.
