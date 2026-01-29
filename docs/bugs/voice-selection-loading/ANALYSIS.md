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

**File**: `lib/app/playback_providers.dart`

**Change**: Added `fireImmediately: true` to the voice change listener

```dart
ref.listen(
  settingsProvider.select((s) => s.selectedVoice),
  (prev, next) {
    final previousVoice = _currentVoice;
    _currentVoice = next;  // Keep _currentVoice in sync
    // ... rest of handler
  },
  fireImmediately: true,  // <-- This ensures initial sync
);
```

**How it works**:
- `fireImmediately: true` causes the callback to fire once immediately with current value
- If settings already loaded, callback gets actual voice and syncs `_currentVoice`
- If settings not yet loaded, callback gets 'none', then fires again when settings load

## Testing

1. Build and install app fresh
2. Start app and go to book
3. Should load without getting stuck (voice already synced from settings)
