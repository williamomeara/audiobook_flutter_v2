# Bug: Parallel Synthesis Threads Setting Does Not Work

**Status:** ✅ RESOLVED (dead code removed)

## Summary

The `parallelSynthesisThreads` setting in `RuntimePlaybackConfig` is dead code. Changing this value has no effect on the app's behavior because:
1. There is no UI to change it
2. Even if there were, the code that determines concurrency doesn't read this value
3. Even if it did read it, the PlaybackController wouldn't update dynamically

## Current Architecture

### How Parallel Concurrency SHOULD Work

```
User changes setting → Config updated → PlaybackController uses new value
```

### How It ACTUALLY Works

```
                                    ╔═══════════════════════════════════════╗
                                    ║  parallelSynthesisThreads (UNUSED)    ║
                                    ║  - Has setter: setParallelSynthesisThreads()
                                    ║  - NEVER CALLED from UI               ║
                                    ║  - NEVER READ by getOptimalConcurrency()
                                    ╚═══════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════════════════════╗
║                         WHAT ACTUALLY CONTROLS CONCURRENCY                     ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                                 ║
║  1. User runs calibration (Settings > Voice Performance > Optimize)            ║
║                              ↓                                                  ║
║  2. Calibration stores result in: engineCalibration[engineType].optimalConcurrency
║                              ↓                                                  ║
║  3. getOptimalConcurrency() reads ONLY from engineCalibration                  ║
║                              ↓                                                  ║
║  4. PlaybackController created with fixed concurrency (NOT dynamic)            ║
║                                                                                 ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

## Code Evidence

### 1. `setParallelSynthesisThreads()` is NEVER called

```dart
// lib/app/config/config_providers.dart:84
Future<void> setParallelSynthesisThreads(int? threads) async {
  await updateConfig(
      (config) => config.copyWith(parallelSynthesisThreads: threads));
}
```

**Search result:** `grep -r "setParallelSynthesisThreads" --include="*.dart"` returns ONLY the definition, never a call.

### 2. `getOptimalConcurrency()` ignores `parallelSynthesisThreads`

```dart
// lib/app/config/runtime_playback_config.dart:387
int getOptimalConcurrency(String engineType) {
  final key = engineType.toLowerCase();
  // ONLY checks engineCalibration, NOT parallelSynthesisThreads!
  if (engineCalibration != null && engineCalibration!.containsKey(key)) {
    final data = engineCalibration![key]!;
    return data['optimalConcurrency'] as int? ?? _defaultConcurrency(key);
  }
  return _defaultConcurrency(key);  // Falls back to PlaybackConfig defaults
}
```

### 3. PlaybackController creates orchestrator ONCE with fixed concurrency

```dart
// packages/playback/lib/src/playback_controller.dart:94-98
_parallelOrchestrator = PlaybackConfig.parallelSynthesisEnabled
    ? ParallelSynthesisOrchestrator(
        maxConcurrency: parallelConcurrency ?? PlaybackConfig.kokoroConcurrency,
        memoryMonitor: memoryMonitor ?? MockMemoryMonitor(),
      )
    : null {
```

The orchestrator is created in the constructor and never recreated when config changes.

### 4. Developer screen gives instructions for UI that doesn't exist

```dart
// lib/ui/screens/developer_screen.dart:1326-1328
To apply this setting:
1. Go to Settings > Advanced
2. Set "Parallel Threads" to ${optimal.concurrency}
```

**Reality:** There is no "Settings > Advanced" screen and no "Parallel Threads" control.

## Impact

- Users cannot manually override parallel synthesis concurrency
- The only way to change concurrency is via calibration (which runs a benchmark)
- The developer screen gives incorrect instructions after auto-tune

## Proposed Fixes

### Option A: Remove Dead Code (Simplest)

Remove `parallelSynthesisThreads` from `RuntimePlaybackConfig` entirely. Calibration already works correctly.

**Pros:**
- Simplest fix
- Less code to maintain
- Calibration is the "correct" way anyway

**Cons:**
- No manual override for power users

### Option B: Make Manual Override Work

1. Add UI in settings to set `parallelSynthesisThreads`
2. Modify `getOptimalConcurrency()` to check `parallelSynthesisThreads` first:
   ```dart
   int getOptimalConcurrency(String engineType) {
     // Manual override takes precedence
     if (parallelSynthesisThreads != null) {
       return parallelSynthesisThreads!;
     }
     // Then check calibration
     // ...
   }
   ```
3. Make PlaybackController listen for config changes and recreate orchestrator

**Pros:**
- Power users can override
- Complete feature

**Cons:**
- More complex
- Requires controller restart logic
- May cause playback interruption on change

### Option C: Remove Dead Code + Update Developer Screen

Same as Option A, but also fix the developer screen text to say:

```
"Calibration applied! Your optimal concurrency of ${optimal.concurrency}x 
will be used automatically for this voice engine."
```

## Recommendation

**Option C** - Remove dead code and fix the misleading instructions. The calibration system already works well and provides a better UX than manual override (users don't need to understand what "parallel threads" means).

## Resolution

Applied Option C:
- Removed `parallelSynthesisThreads` field from `RuntimePlaybackConfig`
- Removed `setParallelSynthesisThreads()` from `config_providers.dart`
- Updated developer screen instructions to point to calibration instead
- Updated tests to remove references to the removed field

## Files Involved

| File | Issue |
|------|-------|
| `lib/app/config/runtime_playback_config.dart` | Contains unused `parallelSynthesisThreads` |
| `lib/app/config/config_providers.dart` | Contains never-called `setParallelSynthesisThreads()` |
| `lib/ui/screens/developer_screen.dart` | Contains incorrect instructions |
| `test/unit/config/runtime_playback_config_test.dart` | Tests for unused feature |
