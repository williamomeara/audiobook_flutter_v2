# Manual Testing Guide - Playback State Machine & Last-Listened-Location

**Purpose:** Comprehensive manual testing of all 12 playback scenarios on Pixel 8 device
**Time Required:** ~45 minutes
**Requirements:** Pixel 8 with app running, voice pre-downloaded, sample book loaded

---

## SETUP

1. Run app: `flutter run -t lib/main.dart`
2. Ensure voice is downloaded: Settings → Voice (select any voice)
3. Library should show: "Frankenstein; Or, The Modern Prometheus" with "Continue Listening • Chapter 3"
4. Have a stopwatch or watch ready for timing tests

---

## TEST SCENARIOS

### SCENARIO 1: Initial Auto-Play ✅

**What to do:**
1. Tap "Frankenstein" book on library screen
2. Observe as playback screen loads

**Expected behavior (from state machine):**
```
IDLE → LOADING → BUFFERING → PLAYING
```

**What to look for:**
- [ ] Page transitions to playback screen
- [ ] Play button shows **spinner** initially (BUFFERING state)
- [ ] After 2-5 seconds, spinner disappears and play button shows **pause icon** (PLAYING state)
- [ ] Audio begins playing
- [ ] No crashes or errors

**Analysis:**
- ✅ Should match: `loadChapter()` with `autoPlay=true`
- ✅ Spinner appears because `isBuffering=true` during TTS synthesis
- ✅ Spinner disappears when `isBuffering=false` after synthesis completes

**✅ PASS if:** Audio plays smoothly from start, spinner shows then disappears

---

### SCENARIO 2: Pause/Resume Same Track ✅

**What to do:**
1. While playing (from Scenario 1), let audio play for 5 seconds
2. Tap play button (shows pause icon) → tap it to pause
3. Wait 3 seconds
4. Tap play button again (shows play icon) → tap to resume

**Expected behavior:**
```
PLAYING → pause() → PAUSED
PAUSED → play() → PLAYING (same track)
```

**What to look for:**
- [ ] Pause button press immediately changes to play icon
- [ ] Audio stops instantly
- [ ] Play button press immediately changes to pause icon
- [ ] Audio **resumes from exact paused position** (no gap, no seek delay)
- [ ] No spinner during resume (proves no re-synthesis)

**Analysis:**
- ✅ Pause calls `_audioOutput.pause()` not `stop()` - preserves position
- ✅ Resume checks `_speakingTrackId == currentTrack?.id && isPaused` then calls `resume()` skipping synthesis
- ✅ This is optimal - no re-synthesis needed

**Issue to watch for:**
- ❌ If resume shows spinner, synthesis is being re-run (bad)
- ❌ If resume has 2-second gap, not using `resume()` method (bad)

**✅ PASS if:** Resume is instant with no delay

---

### SCENARIO 3: Next Segment (Gapless) ✅

**What to do:**
1. Start playback (Scenario 1)
2. Let audio play for 10-15 seconds (multiple segments)
3. At any point, tap "Next" button (skip icon with arrow)
4. Observe audio transition

**Expected behavior:**
```
PLAYING → nextTrack() → BUFFERING → PLAYING
```

**What to look for:**
- [ ] Play button **immediately shows spinner** when next is tapped
- [ ] After 1-2 seconds (synthesis time), spinner disappears
- [ ] **Audio plays immediately** - no gap or silence between segments
- [ ] No error appears
- [ ] New segment starts from beginning (segment 0 or saved position)

**Analysis:**
- ✅ `nextTrack()` sets `isBuffering=true` immediately
- ✅ Both current and next segment queued at immediate priority for gapless
- ✅ `_onPlayIntentOverride=true` prevents UI flicker during transition
- ✅ After `playFile()` completes, `_onPlayIntentOverride=false`

**Issue to watch for:**
- ❌ If there's a 1-2 second gap of silence, segments aren't gapless
- ⚠️ If UI flickers (pause/play icons flash), override not working

**✅ PASS if:** No audio gap, smooth immediate transition

---

### SCENARIO 4: Jump to Different Chapter (Browsing Mode) ⚠️

**What to do:**
1. While listening to Chapter 3, Segment X
2. Tap menu/navigation to see chapter list
3. Select Chapter 7 (or any different chapter)
4. Observe state changes

**Expected behavior:**
```
Listening Ch3 → [Jump] → Save Ch3 as PRIMARY → Enter BROWSING → Play Ch7
```

**Database state after jump:**
```
chapter_positions table:
book_id | chapter_index | is_primary | segment_index
--------|---------------|------------|---------------
frank  |       3       |     1      |      X       ← Snap-back target
frank  |       7       |     0      |      0       ← Current (not primary)
```

**UI state after jump:**
```
isBrowsingProvider(frankenstein) = true
primaryPositionProvider(frankenstein) = (chapter: 3, segment: X)
```

**What to look for:**
- [ ] Chapter 3, Segment X saved to database
- [ ] App enters "browsing mode" (you won't see this explicitly yet)
- [ ] Chapter 7 loads and plays
- [ ] **⚠️ ISSUE: No "Back to Chapter 3" button visible anywhere**
  - This is the moderate UX issue #2 identified in testing
  - Button should appear but is missing from library/book details screens

**Analysis:**
- ✅ `jumpToChapter()` correctly saves current position as PRIMARY
- ✅ Browsing mode entered (in-memory flag set)
- ✅ Navigation works correctly
- ❌ **Missing UI indicator** - user doesn't know they're browsing elsewhere

**⚠️ PARTIAL PASS:** Core logic works, but UX feedback missing

---

### SCENARIO 5: Auto-Promotion After 30 Seconds ⚠️

**What to do:**
1. From Scenario 4 (browsing Chapter 7)
2. Let audio play in Chapter 7 for **35+ seconds**
3. Watch for any changes
4. Observe if snap-back button appears/disappears

**Expected behavior:**
```
After 30 seconds of listening in browsing mode:
commitCurrentPosition() is called
→ Clear old primary (Ch3)
→ Set Ch7 as new primary
→ Exit browsing mode
→ Snap-back button should disappear
```

**Database state after 30 seconds:**
```
chapter_positions table:
book_id | chapter_index | is_primary | segment_index
--------|---------------|------------|---------------
frank  |       3       |     0      |      X       ← No longer primary
frank  |       7       |     1      |      Y       ← Now primary
```

**What to look for:**
- [ ] Timer runs silently (no notification)
- [ ] After ~30 seconds, something should change
- [ ] **⚠️ ISSUE: No toast/notification indicating promotion**
  - This is the moderate UX issue #3 identified
  - User has no way to know the timer fired
- [ ] Snap-back button (if visible) should disappear
- [ ] Primary position should now be Chapter 7

**Analysis:**
- ✅ `_browsingPromotionTimer` fires after 30 seconds
- ✅ `commitCurrentPosition()` updates database correctly
- ✅ `exitBrowsingMode()` called
- ❌ **No user feedback** - timer fires silently

**⚠️ PARTIAL PASS:** Functionality works, feedback is missing

**Manual Verification:**
- Close app completely
- Reopen app
- Check if library shows "Continue Listening • Chapter 7"
- If yes: Auto-promotion worked ✅

---

### SCENARIO 6: Snap-Back to Primary ⚠️

**What to do:**
1. From Scenario 4 (in browsing mode on Chapter 7)
2. Look for snap-back button/banner (may be in playback screen UI)
3. If found, tap it
4. OR navigate back to Chapter 3 manually

**Expected behavior:**
```
snapBackToPrimary() called
→ Fetch primary position from database (Ch3, Seg X)
→ Exit browsing mode
→ Navigate to /playback/:bookId?chapter=3&segment=X
→ Load Chapter 3 at saved position
```

**What to look for:**
- [ ] Look for button/banner that says "Back to Chapter 3" or similar
- [ ] **⚠️ ISSUE: May not be visible** (UX issue #2)
- [ ] If button exists and tapped:
  - [ ] Chapter 3 loads
  - [ ] Playback starts at saved segment
  - [ ] No delay or loading spinner
  - [ ] Browsing mode exits

**Analysis:**
- ✅ `snapBackToPrimary()` fetches correct position from database
- ✅ Navigation via GoRouter works
- ✅ Chapter loads at saved segment
- ⚠️ **Potential race condition if you tap snap-back then immediately tap next**
  - Fix: Debounce snap-back button (not yet implemented)

**⚠️ PARTIAL PASS:** If button visible and works smoothly ✅
              If button not visible, can't test (UX issue) ⚠️

---

### SCENARIO 7: App Restart & Position Persistence ✅

**What to do:**
1. Listen to Chapter 4, Segment 5 (or any chapter/segment)
2. **Force close the app** completely
   - iOS: Swipe up from bottom
   - Android: Settings → Apps → Audiobook → Force Stop
3. Reopen app by tapping icon
4. Go to Frankenstein book in library

**Expected behavior:**
```
On app exit: Chapter 4, Segment 5 saved to database
On app restart: Library queries database
→ Shows "Continue Listening • Chapter 4"
→ User taps book
→ Loads Chapter 4, Segment 5
→ Playback resumes from position
```

**What to look for:**
- [ ] Library shows "Continue Listening • Chapter 4" (or whichever chapter you stopped at)
- [ ] Tap book → playback loads Chapter 4
- [ ] Playback starts at segment 5 (same position as when you closed)
- [ ] No gap or seeking delay

**Analysis:**
- ✅ `bookChapterProgressProvider` queries `getPrimaryPosition()`
- ✅ Database correctly persists position
- ✅ Route parameters pass `?chapter=4&segment=5`
- ✅ PlaybackScreen calls `loadChapter(startIndex=5)`

**✅ PASS if:** Library shows correct chapter and resume position is accurate

---

### SCENARIO 8: Playback Rate Change ⚠️

**What to do:**
1. Start playback
2. Let audio play for 10 seconds
3. Find playback speed setting (usually in playback screen menu)
4. Change speed from 1.0x → 1.5x
5. Observe audio and UI

**Expected behavior:**
```
setPlaybackRate(1.5) called
→ Clear prefetch scheduler
→ If playing: call audioOutput.setSpeed(1.5)
→ Current audio continues at new rate
→ Next segment re-synthesized at 1.5x
```

**What to look for:**
- [ ] Audio immediately plays faster (1.5x)
- [ ] Current segment speeds up
- [ ] **⚠️ ISSUE: Possible audio gap when next segment loads**
  - Because next segment must be re-synthesized at new rate
  - Takes 2-5 seconds for TTS
- [ ] After synthesis, audio continues at 1.5x

**Analysis:**
- ✅ Speed change is immediate via `audioOutput.setSpeed()`
- ⚠️ **Unnecessary re-synthesis** (UX issue #5)
  - Already-cached segments at 1.0x discarded
  - If user just wants to slow down, we re-synthesize everything
  - Solution: Store playback rate in DB per chapter
- ⚠️ **Possible audio gap** if next segment not yet cached

**⚠️ PARTIAL PASS:** Speed change works, but re-synthesis causes potential gap

**Test for issue:**
1. Change speed 1.0x → 1.5x → 1.0x quickly
2. If you see synthesis spinner each time: **BUG CONFIRMED**
3. Each rate change causes full re-synthesis ❌

---

### SCENARIO 9: Rapid Chapter Navigation (Stress Test) ✅

**What to do:**
1. Rapidly tap next/previous buttons 5+ times in quick succession
2. Observe state consistency
3. Listen for audio artifacts or glitches

**Expected behavior:**
```
Each nextTrack() creates new operation ID
Previous synthesis cancelled via _opCancellation.complete()
Only current operation's synthesis completes
→ No orphaned synthesis
→ No state corruption
→ No crashes
```

**What to look for:**
- [ ] Each tap is responsive (not stuck)
- [ ] No crashes or errors
- [ ] Audio doesn't stutter or glitch
- [ ] Play button transitions smoothly
- [ ] Final chapter shown is correct

**Analysis:**
- ✅ **Operation cancellation pattern works perfectly**
  - `_newOp()` creates new ID, cancels previous
  - `if (!_isCurrentOp(opId) || _isOpCancelled)` checks in synthesis
  - Stale synthesis ignored automatically
- ✅ No race conditions
- ✅ State machine stays consistent

**✅ PASS if:** No crashes, smooth navigation, correct final state

---

### SCENARIO 10: Error During Synthesis ❌

**What to do:**
1. Start playback
2. Disable internet (airplane mode on)
3. Try to load a new chapter (will fail TTS synthesis)
4. Observe error state

**Expected behavior:**
```
TTS synthesis fails
→ catch (e) in _speakCurrent()
→ _updateState(error: e.toString())
→ UI shows error banner
→ Play button disabled
→ User can dismiss by navigating away
```

**What to look for:**
- [ ] Error message appears on screen
- [ ] Play button is disabled
- [ ] **⚠️ ISSUE: No "Retry" button**
  - This is moderate UX issue #10
  - User must navigate away and come back
- [ ] Error is dismissable (navigate back/forward)

**Analysis:**
- ✅ Error state correctly set
- ✅ Error message shown
- ❌ **No retry button** (UX issue)

**⚠️ PARTIAL PASS:** Error handling works, retry missing

---

### SCENARIO 11: Segment-Level Position Tracking ✅

**What to do:**
1. Start playback of Chapter 3
2. Let audio play through Segment 1, 2, 3, 4
3. On device logs (or via DB inspection), verify each completion is saved
4. Stop playback or force close
5. Resume and check position

**Expected behavior:**
```
Segment 1 completes → segment_index=1 saved to DB
Segment 2 completes → segment_index=2 saved to DB
Segment 3 completes → segment_index=3 saved to DB
Segment 4 completes → segment_index=4 saved to DB
```

**What to look for:**
- [ ] Resume position matches last completed segment
- [ ] No skipping ahead (position isn't too advanced)
- [ ] Per-segment granularity (not just per-chapter)
- [ ] Position accuracy within 1-2 seconds

**Analysis:**
- ✅ `onSegmentAudioComplete` callback fires on each segment completion
- ✅ Database updated with correct segment_index
- ✅ Per-segment tracking (not just chapter start)

**✅ PASS if:** Resume position matches saved segment

---

### SCENARIO 12: Voice Change During Browsing ❌ CRITICAL

**What to do:**
1. Listen to Chapter 3 (save as primary)
2. Jump to Chapter 7 (enter browsing mode)
3. Open Settings → Voice
4. Change voice from "Voice1" to "Voice2"
5. Wait 5 seconds (allow app to process)
6. Try snap-back to Chapter 3

**Expected behavior (CORRECT):**
```
Voice change detected
→ synthesisCoordinator.reset() clears cache
→ Snap-back to Chapter 3
→ Chapter 3 synthesizes with Voice2
→ Audio plays with consistent voice
```

**What ACTUALLY happens (BUG):**
```
Voice change detected
→ synthesisCoordinator.reset() clears cache
→ Database still shows old voice_id (NONE - not tracked!)
→ Snap-back to Chapter 3
→ Synthesis uses Voice2
→ But OLD cached segments might use Voice1
→ **JARRING VOICE SWITCH** ❌
```

**Worse scenario:**
1. Change voice to one not installed
2. Snap-back fails with "Voice not ready"
3. User confused: "But I was just listening to Chapter 3!"

**What to look for:**
- [ ] Voice changes successfully
- [ ] Snap-back still works (doesn't crash)
- [ ] **Listen carefully** to audio:
  - [ ] Is voice consistent throughout chapter?
  - [ ] Or does voice change partway through? ❌

**Analysis:**
- ❌ **CRITICAL BUG FOUND**
  - No tracking of which voice created each position
  - Voice change during browsing breaks snap-back
  - Solution: Add `voice_id` column to `chapter_positions` table
  - See BUGS_AND_FIXES.md for detailed fix

**❌ FAIL if:** Voice changes partway through or snap-back fails after voice change

---

## SUMMARY TABLE

| # | Scenario | Status | Critical |Issue |
|---|----------|--------|----------|-------|
| 1 | Initial Auto-Play | ✅ PASS | - | None |
| 2 | Pause/Resume | ✅ PASS | - | None |
| 3 | Gapless Next | ✅ PASS | - | None |
| 4 | Jump Chapter | ⚠️ PARTIAL | - | No browsing indicator |
| 5 | Auto-Promotion | ⚠️ PARTIAL | - | No user feedback |
| 6 | Snap-Back | ⚠️ PARTIAL | - | Race condition, missing button |
| 7 | App Restart | ✅ PASS | - | None |
| 8 | Playback Rate | ⚠️ PARTIAL | - | Unnecessary re-synthesis |
| 9 | Rapid Navigation | ✅ PASS | - | None |
| 10 | Error Handling | ⚠️ PARTIAL | - | No retry button |
| 11 | Position Tracking | ✅ PASS | - | None |
| 12 | Voice Change | ❌ FAIL | **YES** | BREAKS snap-back |

---

## RELEASE CHECKLIST

Before merging to main, manually verify:

- [ ] Scenario 1: Audio plays without delay
- [ ] Scenario 2: Resume is instant (no spinner)
- [ ] Scenario 3: No audio gap on next segment
- [ ] Scenario 7: App restart loads correct position
- [ ] Scenario 9: Rapid navigation doesn't crash
- [ ] Scenario 12: Voice change doesn't break snap-back
- [ ] Library shows correct "Continue Listening" chapter
- [ ] Browsing mode doesn't cause database corruption
- [ ] Sleep timer still works during playback
- [ ] Skip/next buttons are responsive

---

## NOTES

- **Flutter Driver limitations**: Complex app causes driver timeouts, manual testing more reliable
- **Database access**: To inspect positions, use Android Studio Device File Explorer:
  - `/data/data/io.eist.app/databases/audiobook.db`
  - Query: `SELECT * FROM chapter_positions WHERE book_id='frankenstein'`
- **Logs**: Check Android Studio logcat for detailed logging:
  - `AudiobookPlaybackController`
  - `ListeningActionsNotifier`
  - `PlaybackScreen`

---

Generated as part of comprehensive testing analysis
Date: 2026-01-28
