# Voice Selection Loading Bug

## Bug Report
- **Symptom**: After app rebuild/restart, opening a book shows stuck loading screen
- **Workaround**: Going to Settings and selecting a voice (even same one) fixes it
- **Root cause**: Race condition between settings async load and playback provider initialization

## Root Cause Analysis

### The Race Condition

1. `SettingsController.build()` returns default state immediately with `selectedVoice = 'none'`
2. Settings are loaded from SQLite asynchronously via `_loadFromSqlite()`
3. `PlaybackControllerNotifier.build()` runs and:
   - Reads `settingsProvider.selectedVoice` → gets `'none'` (default)
   - Sets `_currentVoice = 'none'`
   - Sets up listener for voice changes
4. **Race**: If settings finish loading BEFORE the listener is set up, the voice change is missed
5. Result: `_currentVoice` stays as `'none'` even though actual voice is selected

### Why Settings Fix It

When user goes to Settings and selects a voice:
- This triggers `settingsProvider` state change
- Listener fires with `prev = 'none'`, `next = 'actual_voice'`
- `_currentVoice` gets updated
- Playback works

## Fix Applied

### Fix 1: Voice Listener (Initial Attempt - Insufficient)

**File**: `lib/app/playback_providers.dart`

**Change**: Added `fireImmediately: true` to the voice change listener

This fix alone was insufficient - playback controller was still stuck at initialization.

### Fix 2: Eliminate Cascading Rebuilds (Root Cause)

**Root Cause**: `ref.watch()` calls in provider initialization chain caused cascading rebuilds
that blocked playback controller initialization forever.

**Files Modified**:
1. `lib/app/tts_providers.dart`
2. `lib/app/playback_providers.dart`

**Changes**:
- Changed `ref.watch()` to `ref.read()` in adapter providers and ttsRoutingEngineProvider
- Changed `ref.watch()` to `ref.read()` in intelligentCacheManagerProvider and audioCacheProvider

**Provider Chain Fixed**:
```
playbackControllerProvider
  → routingEngineProvider
    → ttsRoutingEngineProvider (ref.watch → ref.read)
      → kokoroAdapterProvider (ref.watch → ref.read)
      → piperAdapterProvider (ref.watch → ref.read)  
      → supertonicAdapterProvider (ref.watch → ref.read)
      → intelligentCacheManagerProvider (ref.watch → ref.read)
```

**Why `ref.watch()` was problematic**:
- `ref.watch()` in FutureProviders causes provider to be invalidated and re-run when dependencies change
- Settings async load triggers rebuild cascade
- Rebuild resets provider to loading state
- Playback screen sees loading state forever

**Why `ref.read()` fixes it**:
- `ref.read()` gets current value without establishing dependency
- Provider runs once and completes
- No rebuild when settings load later

## Testing

1. Build and install app fresh
2. Start app and go to book
3. Should load without getting stuck (provider chain completes initialization)
