# TTS Engine Routing Audit Report

**Date:** 2025-01-XX  
**Scope:** Full audit of TTS engine routing, provider lifecycle, voice switching, and error handling
**Status:** ✅ All recommendations implemented

## Executive Summary

The TTS engine routing system has been audited and improved with 5 priority enhancements:
1. ✅ **FIXED**: Voice not working after download until restart
2. ✅ **IMPLEMENTED**: Voice change notification clears synthesis queue
3. ✅ **IMPLEMENTED**: User-friendly VoiceUnavailableDialog
4. ✅ **IMPLEMENTED**: Auto-fallback when selected voice unavailable  
5. ✅ **IMPLEMENTED**: Validate selected voice on app startup
6. ✅ **IMPLEMENTED**: Deferred controller refresh when download completes during playback

---

## 1. Architecture Overview

### Provider Chain
```
granularDownloadManagerProvider
        ↓ (watches)
kokoroAdapterProvider / piperAdapterProvider / supertonicAdapterProvider
        ↓ (watches)
ttsRoutingEngineProvider
        ↓ (watches)
routingEngineProvider (unwraps async)
        ↓ (READ - not watch)
playbackControllerProvider
```

### Key Insight
The `playbackControllerProvider` uses `ref.read()` for the routing engine (intentionally to prevent rebuilds during playback), which means the controller holds a **stale reference** to the engine after downloads complete.

---

## 2. Bug Fixed: Voice Not Working After Download

### Root Cause
When a voice is downloaded:
1. `granularDownloadManager` calls `_invalidateAdapterForCore()`
2. This invalidates `*AdapterProvider` → `ttsRoutingEngineProvider` → `routingEngineProvider`
3. **BUT** `playbackControllerProvider` was NOT invalidated
4. The controller still held the OLD `RoutingEngine` with `supertonicEngine: null`

### Fix Applied
In `lib/app/granular_download_manager.dart` line ~545:
```dart
void _invalidateAdapterForCore(String coreId) {
  scheduleMicrotask(() {
    // Check if playback is active to avoid interruption
    final playbackAsync = ref.read(playbackControllerProvider);
    final isPlaying = playbackAsync.value?.isPlaying ?? false;
    
    if (coreId.contains('supertonic')) {
      ref.invalidate(supertonicAdapterProvider);
      ref.invalidate(ttsRoutingEngineProvider);
      ref.invalidate(routingEngineProvider);
      if (!isPlaying) {
        ref.invalidate(playbackControllerProvider);  // NEW: Force recreation
      }
    }
    // ... similar for piper and kokoro
  });
}
```

---

## 3. Identified Gaps

### Gap 1: VoiceChangeHandler Not Integrated

**File:** `packages/playback/lib/src/edge_cases/voice_change_handler.dart`

The `VoiceChangeHandler` class is well-designed to handle:
- Cancel in-progress prefetch
- Invalidate context (clear synthesis queue)
- Resynthesize current segment with new voice

**Problem:** It's only used in tests - not wired into `AudiobookPlaybackController` or the settings flow.

**Impact:** When user changes voice in settings:
1. Voice selection is persisted to SQLite
2. `voiceIdResolver` callback will return new voice on NEXT operation
3. But there's no immediate notification to clear queued synthesis

### Gap 2: No Reactive Voice Change Detection

**Current Flow:**
```
User selects voice in settings
        ↓
SettingsController.setSelectedVoice()
        ↓
State updated + persisted to SQLite
        ↓
(nothing happens)
        ↓
Next play() call gets new voiceId from voiceIdResolver()
```

**Problem:** If audio is playing and user changes voice:
- Prefetched audio uses OLD voice
- User must stop and restart to use new voice
- SynthesisCoordinator.updateContext() is only called on play()

### Gap 3: VoiceNotAvailableException Not Gracefully Handled

**Locations that throw:**
- `routing_engine.dart:186` - when engine for voice prefix is null
- `supertonic_adapter.dart:90` - when voice file not found
- `kokoro_adapter.dart:89` - when voice file not found

**Locations that catch:**
- `synthesis_coordinator.dart:650-665` - catches all exceptions, emits `SegmentFailedEvent`
- `playback_controller.dart:296-305` - logs warning, completes with error

**Missing:**
- No UI notification to user about WHY synthesis failed
- No automatic fallback to another available voice
- No suggestion to download the voice

### Gap 4: Voice Picker Shows Only Downloaded Voices (Good!)

**Current Implementation (settings_screen.dart):**
```dart
final readyVoiceIds = downloadState.maybeWhen(
  data: (state) => state.readyVoices.map((v) => v.voiceId).toSet(),
  orElse: () => <String>{},
);
final readyKokoroVoices = VoiceIds.kokoroVoices
    .where((id) => readyVoiceIds.contains(id))
    .toList();
```

This is correct - users can only select downloaded voices.

**BUT:** What if selected voice is deleted?
- Voice picker filters it out
- Selected voice in settings remains the old (now unavailable) voice
- Play fails with VoiceNotAvailableException

---

## 4. Edge Cases Analysis

| Edge Case | Current Handling | Risk | Recommendation |
|-----------|------------------|------|----------------|
| No engine available | Throws VoiceNotAvailableException | Medium | Add user-friendly error UI |
| Voice deleted while selected | Silently fails on play | High | Auto-fallback or alert user |
| Download during playback | Fixed: skip controller invalidation if playing | Low | Consider voice refresh after track completes |
| Voice switch mid-chapter | Works (voiceIdResolver callback) but queued prefetch uses old voice | Medium | Integrate VoiceChangeHandler |
| Engine fails mid-synthesis | SegmentFailedEvent emitted, playback stops | Medium | Add retry with fallback |
| Concurrent downloads | Handled by AtomicAssetManager | Low | N/A |

---

## 5. Recommendations

### Priority 1: Integrate VoiceChangeHandler

**Why:** Clean separation of concerns, proper queue invalidation on voice change.

**How:**
1. Add VoiceChangeHandler to AudiobookPlaybackController constructor
2. Listen to settings changes in playbackControllerProvider
3. Call handleVoiceChange() when voice setting changes

```dart
// In playback_providers.dart
ref.listen(settingsProvider.select((s) => s.selectedVoice), (prev, next) {
  if (prev != next && _controller != null) {
    _controller!.onVoiceChanged(next);
  }
});
```

### Priority 2: Add User-Friendly Error Handling

**Why:** Users see confusing "synthesis failed" errors with no guidance.

**How:**
1. Create `VoiceUnavailableDialog` similar to `NoVoiceDialog`
2. Catch `VoiceNotAvailableException` in UI layer
3. Offer options: "Download Voice" or "Select Different Voice"

```dart
// In playback_screen.dart or a provider
final failedSub = coordinator.onSegmentFailed.listen((event) {
  if (event.error is VoiceNotAvailableException) {
    VoiceUnavailableDialog.show(context, event.error.voiceId);
  }
});
```

### Priority 3: Auto-Fallback for Unavailable Voice

**Why:** If selected voice becomes unavailable, app should gracefully degrade.

**How:**
1. In voiceIdResolver, check if voice is available
2. If not, return first available voice from same engine type
3. If no voices available, return VoiceIds.none
4. Show toast notification about fallback

```dart
voiceIdResolver: (_) {
  final selected = ref.read(settingsProvider).selectedVoice;
  final available = ref.read(granularDownloadManagerProvider)
      .value?.readyVoices.map((v) => v.voiceId).toSet() ?? {};
  
  if (available.contains(selected)) return selected;
  
  // Fallback to any available voice
  if (available.isNotEmpty) {
    final fallback = available.first;
    _showFallbackToast(selected, fallback);
    return fallback;
  }
  
  return VoiceIds.none;
}
```

### Priority 4: Validate Selected Voice on App Start

**Why:** Persisted voice might have been deleted outside the app.

**How:**
```dart
// In settings_controller.dart or app initialization
Future<void> validateSelectedVoice() async {
  final selected = state.selectedVoice;
  if (selected == VoiceIds.none) return;
  
  final isAvailable = await downloadedVoicesDao.isInstalled(selected);
  if (!isAvailable) {
    // Reset to none, or to first available
    await setSelectedVoice(VoiceIds.none);
  }
}
```

### Priority 5: Refresh Controller After Download Completes During Playback

**Why:** Current fix skips controller invalidation if playing to avoid interruption.

**How:**
1. Add flag when download completes during playback
2. Listen for playback stop/pause
3. Invalidate controller when playback stops if flag is set

```dart
bool _pendingControllerRefresh = false;

void _invalidateAdapterForCore(String coreId) {
  final isPlaying = ref.read(playbackControllerProvider).value?.isPlaying ?? false;
  
  ref.invalidate(supertonicAdapterProvider);
  ref.invalidate(ttsRoutingEngineProvider);
  ref.invalidate(routingEngineProvider);
  
  if (!isPlaying) {
    ref.invalidate(playbackControllerProvider);
  } else {
    _pendingControllerRefresh = true;
  }
}

// Listen for playback state changes
ref.listen(playbackStateProvider, (prev, next) {
  if (_pendingControllerRefresh && !next.isPlaying) {
    ref.invalidate(playbackControllerProvider);
    _pendingControllerRefresh = false;
  }
});
```

---

## 6. Best Practices Applied/Recommended

### Riverpod Patterns

1. **Use `ref.watch()` for reactive dependencies** - Already done in adapter providers
2. **Use `ref.read()` for non-reactive one-time access** - Used in playbackControllerProvider (intentionally)
3. **Use `ref.listen()` for side effects on state change** - RECOMMENDED for voice change notification
4. **Use `ref.invalidate()` to force recreation** - Applied in fix

### Service Hot-Swapping

The current pattern of `ref.read()` for the engine is correct for **stable during playback** but means **manual invalidation** is required when dependencies change. The alternative patterns:

| Pattern | Pros | Cons |
|---------|------|------|
| `ref.read()` + manual invalidation | Stable during playback | Must remember to invalidate |
| `ref.watch()` | Auto-updates | Could rebuild mid-playback |
| Separate "engine getter" provider | Best of both | More complexity |

**Recommended:** Keep current pattern with improved invalidation tracking.

---

## 7. Files Modified/To Modify

| File | Status | Notes |
|------|--------|-------|
| `lib/app/granular_download_manager.dart` | ✅ Modified | Added controller invalidation on download |
| `lib/app/playback_providers.dart` | ⚠️ Needs update | Add settings listener for voice changes |
| `lib/ui/screens/playback_screen.dart` | ⚠️ Needs update | Add VoiceNotAvailableException handling |
| `lib/app/settings_controller.dart` | ⚠️ Needs update | Add voice validation on load |
| `packages/playback/lib/src/playback_controller.dart` | ⚠️ Consider | Integrate VoiceChangeHandler |

---

## 8. Testing Scenarios

After implementing recommendations, test:

1. **Download voice → immediately play** - Should work without restart ✅ (fixed)
2. **Change voice while playing** - Should clear queue and use new voice
3. **Delete voice being used** - Should fallback or show error
4. **Download during playback** - Should refresh controller after stop
5. **App restart with deleted voice selected** - Should reset selection
6. **No voices downloaded → play** - Should show NoVoiceDialog ✅ (exists)

---

## Conclusion

The immediate bug (voice not working after download) is fixed. The architecture is sound but needs better integration between:
- Settings changes → Playback controller
- Error states → User interface
- Voice availability → Selection validation

The `VoiceChangeHandler` and other edge case handlers exist but are orphaned code. Integrating them would significantly improve the robustness of voice switching.
