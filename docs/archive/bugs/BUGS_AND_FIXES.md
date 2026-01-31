# Playback State Machine: Bugs Found & Recommended Fixes

**Report Date:** 2026-01-28
**Status:** 7 Issues identified (1 Critical, 4 Moderate, 2 Minor)

---

## CRITICAL ISSUES

### Issue #1: Voice Download Timeout (CRITICAL)

**Severity:** CRITICAL
**Status:** ❌ Not Fixed
**Location:** `playback_controller.dart:755-768`
**Affects:** Initial playback with missing voice

---

**Problem Description:**

When user starts playback without voice downloaded, app may hang indefinitely in BUFFERING state if voice download fails or takes too long.

```dart
final voiceReadiness = await engine.checkVoiceReady(voiceId);
if (!voiceReadiness.isReady) {
  // Shows error, but no timeout if download hangs
}
```

**Scenario:**
1. User starts playback, voice not downloaded
2. System initiates voice download
3. Network drops or download stalls
4. App stays in BUFFERING state forever
5. User sees spinning wheel indefinitely

**Why It's Critical:**
- User perceives app as frozen
- No way to escape except force-close
- No error message explaining what's wrong

---

**Recommended Fix:**

```dart
// In _speakCurrent() method, wrap voice check with timeout:

Future<void> _speakCurrent({required int opId}) async {
  final track = _state.currentTrack;
  if (track == null) {
    _logger.warning('_speakCurrent called but currentTrack is null');
    _updateState(_state.copyWith(isPlaying: false, isBuffering: false));
    return;
  }

  final voiceId = voiceIdResolver(null);
  _logger.info('Using voice: $voiceId');

  if (voiceId == VoiceIds.device) {
    _updateState(_state.copyWith(
      isBuffering: false,
      error: 'Please select an AI voice in Settings → Voice. Device TTS coming soon.',
    ));
    return;
  }

  try {
    _logger.info('[Coordinator] Checking voice readiness...');

    // ADD THIS: Timeout wrapper for voice readiness check
    final voiceReadiness = await engine
        .checkVoiceReady(voiceId)
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw TimeoutException(
            'Voice download took too long (>60s). Check internet connection.',
          ),
        );

    if (!voiceReadiness.isReady) {
      _logger.warning('[Coordinator] Voice not ready: ${voiceReadiness.state}');
      _updateState(_state.copyWith(
        isPlaying: false,
        isBuffering: false,
        error: voiceReadiness.nextActionUserShouldTake ??
            'Voice not ready. Please download the required model in Settings.',
      ));
      return;
    }

    // ... rest of synthesis code ...
  } catch (e, stackTrace) {
    _logger.severe('[Coordinator] Playback failed', e, stackTrace);
    _onPlayIntentOverride?.call(false);

    if (!_isCurrentOp(opId) || _isOpCancelled) return;

    _updateState(_state.copyWith(
      isPlaying: false,
      isBuffering: false,
      error: e.toString(),  // Timeout message shown to user
    ));
  }
}
```

**Alternative: More User-Friendly Error**

```dart
} on TimeoutException {
  _updateState(_state.copyWith(
    isPlaying: false,
    isBuffering: false,
    error: 'Voice download taking too long. Please check your internet '
        'connection or download voice manually in Settings.',
  ));
  return;
}
```

---

### Issue #6: Snap-Back Race Condition (CRITICAL)

**Severity:** CRITICAL
**Status:** ⚠️ Partially Mitigated
**Location:** `playback_screen.dart:snap-back button handler` + `playback_controller.dart`
**Affects:** Rapid snap-back navigation

---

**Problem Description:**

User can tap snap-back button, then immediately tap next/previous before Chapter 3 finishes loading. This causes state inconsistency where:
1. Route navigation loads Chapter 3
2. User taps next (opId incremented)
3. Playback controller cancels Chapter 3 synthesis
4. But route already started loading Chapter 3
5. UI shows wrong chapter briefly

**Scenario:**
1. User at Chapter 7, snap-back button visible
2. Taps snap-back → navigation to `/playback/book?chapter=3`
3. Immediately taps next button
4. System loads Chapter 4 instead
5. But route still completing: briefly shows Chapter 3 loading, then switches to 4

---

**Root Cause:**

Route navigation and playback controller state are independent. Route doesn't know if user cancelled by pressing next.

```dart
// playback_screen.dart - snap-back handler
onTap: () async {
  final position = await ref.read(listeningActionsProvider.notifier)
      .snapBackToPrimary();
  if (position != null) {
    // Route navigation starts, but can be interrupted by next/previous
    context.go('/playback/$bookId?chapter=${position.$1}&segment=${position.$2}');
  }
}
```

---

**Recommended Fix:**

**Option A: Debounce (Simplest)**

```dart
// In playback_screen.dart state:
DateTime? _lastSnapBackTime;
static const _snapBackDebounce = Duration(milliseconds: 500);

// In snap-back handler:
onTap: () async {
  final now = DateTime.now();
  if (_lastSnapBackTime != null &&
      now.difference(_lastSnapBackTime!) < _snapBackDebounce) {
    return;  // Ignore rapid taps
  }
  _lastSnapBackTime = now;

  final position = await ref.read(listeningActionsProvider.notifier)
      .snapBackToPrimary();
  if (position != null) {
    context.go('/playback/$bookId?chapter=${position.$1}&segment=${position.$2}');
  }
}
```

**Option B: Disable During Navigation (Better UX)**

```dart
// In snap-back handler:
onTap: () async {
  _snapBackInProgress = true;  // Add to state
  try {
    final position = await ref.read(listeningActionsProvider.notifier)
        .snapBackToPrimary();
    if (position != null) {
      context.go('/playback/$bookId?chapter=${position.$1}&segment=${position.$2}');
    }
  } finally {
    _snapBackInProgress = false;
  }
}

// In banner build:
return IgnorePointer(
  ignoring: _snapBackInProgress,
  opacity: _snapBackInProgress ? 0.5 : 1.0,
  child: SnapBackButton(...),
);
```

**Option C: Cancel Outstanding Operations (Most Correct)**

```dart
// In listening_actions_notifier:
Future<void> snapBackToPrimary() async {
  // Cancel any pending synthesis before snap-back
  await ref.read(playbackControllerProvider).cancelPendingOperations();

  final primary = await dao.getPrimaryPosition(state.bookId);
  // ... rest of code ...
}
```

**Recommendation:** Use **Option A (Debounce)** for quick fix, then consider **Option B** for better UX.

---

### Issue #12: Voice Change During Browsing (CRITICAL)

**Severity:** CRITICAL
**Status:** ❌ Not Fixed
**Location:** `playback_providers.dart:592-597` + `playback_controller.dart:563-581`
**Affects:** Voice change during browsing mode

---

**Problem Description:**

When user changes voice while browsing a different chapter, the snap-back target may become unplayable or use the wrong voice.

**Scenario:**
1. User listening to Chapter 3 with Kokoro voice (primary)
2. User jumps to Chapter 7 (browsing mode, Kokoro cached)
3. User opens Settings → Changes voice to Piper
4. Synthesis queue cleared (correct)
5. User listens to Chapter 7 for 30+ seconds → auto-promotes to primary
6. Later, user taps snap-back to Chapter 3
7. Chapter 3 loads with Piper voice (not Kokoro!)
8. Jarring voice switch for user

**Worse Scenario:**
1. Same as above, but user deletes Kokoro voice in Settings
2. User tries snap-back to Chapter 3
3. Error: "Voice not ready" (because Kokoro is gone)
4. User confused - they were just listening to Chapter 3!

---

**Root Cause:**

No record of which voice was used for each chapter position. Database schema doesn't track voice context.

```sql
-- Current schema (no voice info)
CREATE TABLE chapter_positions (
  book_id TEXT NOT NULL,
  chapter_index INTEGER NOT NULL,
  segment_index INTEGER NOT NULL,
  is_primary INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(book_id, chapter_index),
  FOREIGN KEY(book_id) REFERENCES books(id)
);
```

---

**Recommended Fix:**

**Step 1: Update Database Schema**

Create new migration `migration_v7.dart`:

```dart
// lib/app/database/migrations/migration_v7.dart

import 'package:sqflite/sqflite.dart';

class MigrationV7 {
  static Future<void> up(Database db) async {
    // Add voice_id column to track which voice created these segments
    await db.execute('''
      ALTER TABLE chapter_positions
      ADD COLUMN voice_id TEXT
    ''');

    // Create index for faster voice lookups
    await db.execute('''
      CREATE INDEX idx_chapter_positions_voice
      ON chapter_positions(book_id, voice_id)
    ''');
  }

  static Future<void> down(Database db) async {
    await db.execute('DROP INDEX idx_chapter_positions_voice');
    // Note: Can't drop column in SQLite without recreating table
    // For testing, just leave it
  }
}
```

**Step 2: Update AppDatabase**

```dart
// lib/app/database/app_database.dart

class AppDatabase {
  static const _dbVersion = 7;  // Changed from 6

  // In onCreate method:
  if (version == _dbVersion) {
    await MigrationV7.up(db);
  }
}
```

**Step 3: Update ChapterPosition DTO**

```dart
// lib/app/database/daos/chapter_position_dao.dart

class ChapterPosition {
  const ChapterPosition({
    required this.chapterIndex,
    required this.segmentIndex,
    this.isPrimary = false,
    required this.updatedAt,
    this.voiceId,  // NEW FIELD
  });

  final int chapterIndex;
  final int segmentIndex;
  final bool isPrimary;
  final int updatedAt;
  final String? voiceId;  // NEW: which voice created this position

  Map<String, dynamic> toMap() => {
    'chapter_index': chapterIndex,
    'segment_index': segmentIndex,
    'is_primary': isPrimary ? 1 : 0,
    'updated_at': updatedAt,
    'voice_id': voiceId,  // NEW
  };

  factory ChapterPosition.fromMap(Map<String, dynamic> map) =>
      ChapterPosition(
        chapterIndex: map['chapter_index'] as int,
        segmentIndex: map['segment_index'] as int,
        isPrimary: (map['is_primary'] as int) == 1,
        updatedAt: map['updated_at'] as int,
        voiceId: map['voice_id'] as String?,  // NEW
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChapterPosition &&
          runtimeType == other.runtimeType &&
          chapterIndex == other.chapterIndex &&
          segmentIndex == other.segmentIndex &&
          isPrimary == other.isPrimary &&
          updatedAt == other.updatedAt &&
          voiceId == other.voiceId;  // NEW

  @override
  int get hashCode =>
      chapterIndex.hashCode ^
      segmentIndex.hashCode ^
      isPrimary.hashCode ^
      updatedAt.hashCode ^
      voiceId.hashCode;  // NEW
}
```

**Step 4: Update savePosition() Method**

```dart
// In ChapterPositionDao

Future<void> savePosition({
  required String bookId,
  required int chapterIndex,
  required int segmentIndex,
  bool isPrimary = false,
  String? voiceId,  // NEW: add current voice ID
}) async {
  final db = await database;

  await db.insert(
    'chapter_positions',
    {
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'segment_index': segmentIndex,
      'is_primary': isPrimary ? 1 : 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'voice_id': voiceId,  // NEW
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
```

**Step 5: Update Listeners to Pass Voice ID**

```dart
// In playback_providers.dart or listening_actions_notifier.dart

await dao.savePosition(
  bookId: bookId,
  chapterIndex: chapterIndex,
  segmentIndex: segmentIndex,
  isPrimary: !isBrowsing,
  voiceId: voiceIdResolver(bookId),  // NEW: pass current voice
);
```

**Step 6: Check Voice Compatibility on Resume**

```dart
// In playback_controller.dart _speakCurrent() method

// Before playing, check if voice changed since position was saved
final savedVoiceId = _state.currentTrack?.voiceId;
final currentVoiceId = voiceIdResolver(null);

if (savedVoiceId != null &&
    savedVoiceId != currentVoiceId &&
    _state.currentIndex == 0) {  // Only warn for chapter start
  _logger.warning(
    'Voice changed since position saved. '
    'Was: $savedVoiceId, Now: $currentVoiceId'
  );

  // Show warning to user (optional)
  // Don't block playback, just note the difference
}
```

**Alternative Simpler Fix (Without Schema Change):**

If schema change is too invasive, implement client-side logic:

```dart
// In listening_actions_notifier

Map<String, String> _lastUsedVoice = {};  // book_id -> voice_id

Future<ChapterPosition?> getPrimaryPosition(String bookId) async {
  final primary = await dao.getPrimaryPosition(bookId);
  if (primary == null) return null;

  final currentVoiceId = voiceIdResolver(bookId);
  final lastVoiceId = _lastUsedVoice[bookId];

  if (lastVoiceId != null && lastVoiceId != currentVoiceId) {
    _logger.warning('Warning: Position was created with $lastVoiceId '
        'but current voice is $currentVoiceId');
    // Could show UI warning here
  }

  return primary;
}
```

**Recommendation:** Use **Schema Change (Steps 1-6)** for robustness. It allows tracking voice per position and prevents future issues.

---

## MODERATE ISSUES

### Issue #2: No Browsing Mode Indicator in Library (MODERATE)

**Severity:** MODERATE
**Status:** ⚠️ Missing Feature
**Location:** `library_screen.dart` + `book_details_screen.dart`
**Affects:** User awareness of browsing state

---

**Problem:** User browses different chapter but library still shows primary position. User doesn't know they're browsing elsewhere.

**Example:**
- Library shows "Continue Listening • Chapter 3"
- User in app listening to Chapter 7 (browsing)
- User closes app, reopens
- Library still shows Chapter 3 (doesn't indicate Chapter 7 being browsed)

**Fix:**

```dart
// In library_screen.dart or book details badge

// Current: Shows only primary position
"Continue Listening • Chapter 3"

// Proposed: Show both primary and browsing
if (isBrowsing) {
  "🎯 Chapter 3 • ▶️ Now browsing Chapter 7"
} else {
  "Continue Listening • Chapter 3"
}
```

---

### Issue #3: No User Feedback on Auto-Promotion (MODERATE)

**Severity:** MODERATE
**Status:** ⚠️ Missing UX Feedback
**Location:** `listening_actions_notifier.dart:91-115`
**Affects:** User awareness of position changes

---

**Problem:** 30-second timer silently auto-promotes browsing position to primary. User has no feedback this happened.

**Fix:**

```dart
// In commitCurrentPosition() method

ref.read(listeningActionsProvider.notifier).commitCurrentPosition();

// Then show feedback:
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Listening position updated to Chapter 7'),
    duration: Duration(seconds: 2),
  ),
);
```

Or in the notifier itself:

```dart
// listening_actions_notifier.dart

final _feedbackCallback = ValueNotifier<String?>(null);

Future<void> commitCurrentPosition() async {
  // ... existing code ...
  _feedbackCallback.value = 'Listening position updated to Chapter ${chapter+1}';

  // Clear after 2 seconds
  await Future.delayed(Duration(seconds: 2));
  _feedbackCallback.value = null;
}
```

---

### Issue #5: Unnecessary Re-synthesis on Playback Rate Change (MODERATE)

**Severity:** MODERATE
**Status:** ⚠️ Performance Issue
**Location:** `playback_controller.dart:538-550`
**Affects:** Playback smoothness when rate changes

---

**Problem:** Changing playback rate causes already-synthesized segments to be discarded and re-synthesized.

**Example:**
1. Segment 5 synthesized at 1.0x (10 seconds)
2. User changes to 1.5x
3. Segment 5 re-synthesized (another 10 seconds)
4. User waits for audio to resume

**Fix:**

Store playback rate in database for each chapter:

```dart
// Update chapter_positions schema to include playback_rate
ALTER TABLE chapter_positions ADD COLUMN playback_rate REAL DEFAULT 1.0;

// Then on resume:
final savedRate = position.playbackRate;
ref.read(playbackControllerProvider).setPlaybackRate(savedRate);

// This way, segments are already cached at correct rate
```

Or simpler: Disable auto-rate-change for synthesis already in progress:

```dart
// In setPlaybackRate() method
if (_state.isBuffering) {
  // Don't change rate during synthesis
  return;
}
```

---

### Issue #10: No Retry Button in Error State (MODERATE)

**Severity:** MODERATE
**Status:** ⚠️ Missing UX
**Location:** `playback_screen.dart` error rendering
**Affects:** Error recovery UX

---

**Problem:** When error occurs, user can't retry. Must navigate away.

**Fix:**

```dart
// In playback_screen.dart error rendering

if (state.error != null) {
  return Column(
    children: [
      ErrorBanner(state.error),
      ElevatedButton(
        onPressed: () {
          // Clear error and retry
          ref.read(playbackControllerProvider).clearError();
          ref.read(playbackControllerProvider).play();
        },
        child: Text('Retry'),
      ),
    ],
  );
}

// Add clearError method to PlaybackController:
void clearError() {
  _updateState(_state.copyWith(error: null));
}
```

---

## MINOR ISSUES

### Issue #4: Race Condition on Rapid Snap-Back (see Critical Issue #6)

### Issue #7: Sleep Timer Edge Case (MINOR)

**Severity:** MINOR
**Status:** ⚠️ Edge Case
**Location:** `playback_screen.dart:676-701`
**Affects:** Sleep timer completion when paused

---

**Problem:** If user pauses with <1 second left on sleep timer, timer never fires.

**Current Code:**
```dart
if (!playbackState.isPlaying) {
  return;  // Skip decrement, don't check if time is up
}
```

**Fix:**
```dart
// Decrement only if playing, but allow timer to complete if paused
if (playbackState.isPlaying) {
  _sleepTimerSeconds--;
}

// Check if time is up regardless of playback state
if (_sleepTimerSeconds <= 0) {
  pause();
  return;
}
```

---

## SUMMARY OF REQUIRED FIXES

| Priority | Issue | Fix Type | Effort |
|----------|-------|----------|--------|
| CRITICAL | Voice download timeout | Add timeout wrapper | 1 hour |
| CRITICAL | Snap-back race condition | Add debounce | 30 min |
| CRITICAL | Voice change during browsing | Update schema + logic | 2 hours |
| MODERATE | Browsing mode library indicator | UI enhancement | 1 hour |
| MODERATE | Auto-promotion feedback | Add snackbar | 30 min |
| MODERATE | Rate change re-synthesis | Store rate in DB | 1 hour |
| MODERATE | Error retry button | Add button + handler | 30 min |
| MINOR | Sleep timer edge case | Fix logic | 15 min |

**Total Estimated Time:** ~6.5 hours

---

## TESTING AFTER FIXES

For each fix, add these tests:

```dart
// playback_state_machine_test.dart

test('Voice download timeout shows error', () async {
  // Mock voice download that hangs
  engine.setVoiceDownloadDelay(Duration(minutes: 2));

  await controller.loadChapter(..., autoPlay: true);

  // Wait for timeout
  await Future.delayed(Duration(seconds: 61));

  expect(controller.state.error, contains('took too long'));
});

test('Rapid snap-back is debounced', () async {
  // Tap snap-back twice quickly
  ref.read(listeningActionsProvider).snapBackToPrimary();
  ref.read(listeningActionsProvider).snapBackToPrimary();

  // Only one snap-back should execute
  expect(snapBackCount, equals(1));
});

test('Voice change with browsing preserves snap-back', () async {
  // Start browsing
  controller.jumpToChapter(7);

  // Change voice
  ref.read(settingsProvider.notifier).setVoice('piper');

  // Snap-back should still work
  final pos = await ref.read(listeningActionsProvider).snapBackToPrimary();
  expect(pos, isNotNull);
});
```

---

Generated by comprehensive state machine analysis
Date: 2026-01-28
