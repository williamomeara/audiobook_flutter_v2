# Playback Loading Issue - Root Cause Analysis and Fix

## Problem Description
When clicking "Library > Book > Start Reading", the app enters an infinite loading state, showing "Loading chapter..." indefinitely. Clicking back and trying again fixes the issue.

## Root Cause
The issue was caused by a cascading rebuild loop in the Riverpod provider dependency chain:

1. **Provider Dependencies**: The playback initialization chain was:
   - `playbackStateProvider` → watches → `playbackControllerProvider`
   - `playbackControllerProvider.build()` → reads → `routingEngineProvider`
   - `routingEngineProvider` → **watches** → `ttsRoutingEngineProvider`
   - `ttsRoutingEngineProvider` → **watches** → adapter providers (Kokoro, Piper, Supertonic)
   - Adapter providers → **watch** → `granularDownloadManagerProvider`

2. **The Problem**: All these `ref.watch()` calls created a reactive dependency chain. When any download state changed:
   - `granularDownloadManagerProvider` would update
   - This would cause adapter providers to rebuild and return to loading state
   - This would cause `ttsRoutingEngineProvider` to rebuild
   - This would cause `routingEngineProvider` to rebuild
   - This would trigger cascading rebuilds up the chain

3. **Why the Second Click Works**: By the time the user clicks back and tries again, the `granularDownloadManagerProvider` is already fully initialized and cached. The rebuild cascade doesn't happen, so the providers complete initialization successfully.

## Solution
Changed all `ref.watch()` calls in the TTS provider initialization chain to `ref.read()`. This ensures:

- **No cascading rebuilds**: During provider initialization, we only read the current state once
- **Initialization completes**: The provider chain can finish its async build without being interrupted by dependency changes
- **State updates still work**: Downloads can still update state in the UI through other mechanisms (watches in UI widgets remain in place)

## Files Modified

### 1. `lib/app/playback_providers.dart`
- Line 22: Changed `ref.watch(ttsRoutingEngineProvider.future)` → `ref.read(ttsRoutingEngineProvider.future)`
- **Reason**: Prevents `routingEngineProvider` from rebuilding when underlying TTS dependencies change

### 2. `lib/app/tts_providers.dart`
- Lines 17, 18, 25: Kokoro adapter - changed all `ref.watch()` → `ref.read()`
- Lines 35, 36, 44: Piper adapter - changed all `ref.watch()` → `ref.read()`
- Lines 54, 55, 62: Supertonic adapter - changed all `ref.watch()` → `ref.read()`
- Lines 71, 72, 73, 74: Routing engine - changed all `ref.watch()` → `ref.read()`
- Line 86: Audio cache provider - changed `ref.watch()` → `ref.read()`
- **Reason**: Prevents these providers from rebuilding when `granularDownloadManagerProvider` state changes

### 3. `lib/app/granular_download_manager.dart`
- Line 26: Changed `ref.watch(appPathsProvider.future)` → `ref.read(appPathsProvider.future)`
- **Reason**: Consistency - app paths don't change during the app lifecycle, no need to watch

## Technical Explanation

### Why `ref.read()` vs `ref.watch()`?

**`ref.watch(provider)`**:
- Creates a reactive dependency
- When the provider updates, the consumer rebuilds
- **Used for**: UI state that needs to react to changes

**`ref.read(provider)`**:
- Reads the current value once
- Does NOT create a reactive dependency
- Does NOT cause rebuilds when the provider changes
- **Used for**: One-time initialization values

### Why This Matters for Playback

During playback initialization, we need the TTS engines to be available, but we don't need them to reinitialize if download states change. The download manager can update its state (and the UI will reflect it), but the playback controller shouldn't be continuously reinitializing its engines.

## Impact

- **Fixes**: Infinite loading state on first click to Start Reading
- **Preserves**: Download functionality and UI updates continue to work normally
- **No regression**: Existing UI watches remain in place where needed

## Testing Recommendations

1. Click Library → Select a Book → Click "Start Reading"
   - Should load and display playback UI without hanging
   
2. Download a voice while on the playback screen
   - Download progress should still update
   - Playback should not interrupt or reset

3. Switch between books
   - Each book should load without issues

4. Navigate back and forth between screens
   - No stale states or memory leaks expected
