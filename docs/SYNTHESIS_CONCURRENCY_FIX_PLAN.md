# TTS Synthesis Concurrency & Cancellation Fixes Plan

## Problem Statement

Two audit reports have identified critical issues in the TTS synthesis system:

1. **Concurrency Issues** - Race conditions, weak backpressure, unsynchronized state
2. **Cancellation/Cleanup Issues** - Missing lifecycle handling, incomplete in-flight cancellation

## Approach

Implement targeted fixes prioritized by severity, focusing on the HIGH and MEDIUM issues first.

---

## Workplan

### Phase 1: Critical Concurrency Fixes (HIGH)

- [x] **1.1 Add AsyncLock for shared mutable state**
  - Location: `packages/playback/lib/src/synthesis/synthesis_coordinator.dart`
  - Add mutex protection for `_queue`, `_pendingByKey`, `_inFlightKeys`
  - Use the existing `_AsyncLock` pattern from buffer scheduler

- [x] **1.2 Fix semaphore backpressure in worker loop**
  - Location: `synthesis_coordinator.dart` lines 486-495
  - Make worker wait for semaphore availability before dispatching
  - Replace `unawaited(_processRequest())` with proper await/backpressure

- [x] **1.3 Fix race condition in `_inFlightKeys` management**
  - Location: `synthesis_coordinator.dart` lines 632-636
  - Move `_inFlightKeys.add()` to after semaphore acquisition
  - Ensure atomic tracking of in-flight requests

### Phase 2: ~~Critical Lifecycle Fixes (HIGH)~~ N/A

~~- [ ] **2.1 Add App Lifecycle Handler**~~
  - ~~Location: Add to `lib/ui/screens/playback_screen.dart` or `lib/app/`~~
  - ~~Implement `AppLifecycleListener` to pause playback when app is backgrounded~~
  - ~~Prevent battery drain from synthesis running in background~~

**NOTE:** Removed - audiobook app requires background synthesis for lock-screen listening. App uses `audio_service` for background playback.

### Phase 3: Medium Priority Cleanup Fixes

- [ ] **3.1 Fix `_waitingForSegmentCompleter` cleanup**
  - Location: `lib/app/playback_controller.dart` `dispose()` method
  - Complete with error on dispose to prevent memory leak

- [ ] **3.2 Add worker loop cancellation signal**
  - Location: `synthesis_coordinator.dart` `_processRequest()`
  - Check `_disposed` flag before starting synthesis
  - Add early exit checks in synthesis loop

- [ ] **3.3 Atomize queue-size check**
  - Location: `synthesis_coordinator.dart` lines 284-287
  - Lock the region from size check to add

### Phase 4: Low Priority & Testing

- [ ] **4.1 Ensure semaphore release only after acquire**
  - Verify try/finally pattern is consistent

- [ ] **4.2 Add telemetry/logging for concurrency issues**
  - Track semaphore contention
  - Log dropped requests, in-flight imbalances

- [ ] **4.3 Run existing tests to verify no regressions**
  - `flutter test packages/playback/`

---

## Notes

### Key Files to Modify
1. `packages/playback/lib/src/synthesis/synthesis_coordinator.dart` - Main concurrency fixes
2. `lib/app/playback_controller.dart` - Completer cleanup
3. `lib/ui/screens/playback_screen.dart` or new lifecycle file - App lifecycle handling

### Existing Pattern to Follow
- `_AsyncLock` pattern from buffer scheduler (lines 22-43) should be reused for consistency

### Testing Considerations
- Stress test concurrent `queueRange()` + `reset()` calls
- Test app backgrounding/foregrounding during synthesis
- Verify no memory leaks with long playback sessions

### Risk Assessment
- Phase 1 changes are internal to synthesis coordinator - low regression risk
- Phase 2 adds new lifecycle behavior - needs careful testing
- All changes should be backward compatible
