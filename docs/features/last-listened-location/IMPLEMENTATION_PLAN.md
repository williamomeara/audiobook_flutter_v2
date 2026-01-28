# Last Listened Location - Implementation Plan

## Phase 1: Database Schema (Day 1) ✅ COMPLETED

### 1.1 Create Migration v4

**File:** `lib/app/database/migrations/migration_v4.dart`

```dart
import 'package:sqflite/sqflite.dart';

Future<void> migrateV3ToV4(Database db) async {
  // Create chapter_positions table
  await db.execute('''
    CREATE TABLE chapter_positions (
      book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      chapter_index INTEGER NOT NULL,
      segment_index INTEGER NOT NULL,
      is_primary INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY(book_id, chapter_index)
    )
  ''');
  
  // Index for quick primary lookup
  await db.execute('''
    CREATE INDEX idx_chapter_positions_primary 
    ON chapter_positions(book_id, is_primary) 
    WHERE is_primary = 1
  ''');
}
```

### 1.2 Update Database Manager

**File:** `lib/app/database/database.dart`

```dart
// Update version constant
const int kDatabaseVersion = 4;

// Add migration case in onUpgrade
case 3:
  await migrateV3ToV4(db);
  continue nextVersion;
```

### 1.3 Create ChapterPositionDao

**File:** `lib/app/database/daos/chapter_position_dao.dart`

```dart
class ChapterPositionDao {
  final Database _db;
  
  ChapterPositionDao(this._db);
  
  /// Save or update a chapter position
  Future<void> saveChapterPosition({
    required String bookId,
    required int chapterIndex,
    required int segmentIndex,
    required bool isPrimary,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert(
      'chapter_positions',
      {
        'book_id': bookId,
        'chapter_index': chapterIndex,
        'segment_index': segmentIndex,
        'is_primary': isPrimary ? 1 : 0,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  /// Get the primary position for a book
  Future<ChapterPosition?> getPrimaryPosition(String bookId) async {
    final results = await _db.query(
      'chapter_positions',
      where: 'book_id = ? AND is_primary = 1',
      whereArgs: [bookId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return ChapterPosition.fromMap(results.first);
  }
  
  /// Get position for a specific chapter
  Future<ChapterPosition?> getChapterPosition(
    String bookId, 
    int chapterIndex,
  ) async {
    final results = await _db.query(
      'chapter_positions',
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return ChapterPosition.fromMap(results.first);
  }
  
  /// Get all positions for a book
  Future<Map<int, ChapterPosition>> getAllPositions(String bookId) async {
    final results = await _db.query(
      'chapter_positions',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'chapter_index',
    );
    return {
      for (final row in results)
        row['chapter_index'] as int: ChapterPosition.fromMap(row)
    };
  }
  
  /// Clear primary flag from all positions for a book
  Future<void> clearPrimaryFlag(String bookId) async {
    await _db.update(
      'chapter_positions',
      {'is_primary': 0},
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }
  
  /// Delete all positions for a book
  Future<void> deleteBookPositions(String bookId) async {
    await _db.delete(
      'chapter_positions',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }
}

/// Chapter position data class
class ChapterPosition {
  final int chapterIndex;
  final int segmentIndex;
  final bool isPrimary;
  final DateTime updatedAt;
  
  const ChapterPosition({
    required this.chapterIndex,
    required this.segmentIndex,
    required this.isPrimary,
    required this.updatedAt,
  });
  
  factory ChapterPosition.fromMap(Map<String, dynamic> map) {
    return ChapterPosition(
      chapterIndex: map['chapter_index'] as int,
      segmentIndex: map['segment_index'] as int,
      isPrimary: (map['is_primary'] as int) == 1,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}
```

---

## Phase 2: Providers (Day 2) ✅ COMPLETED

### 2.1 Add Position Provider

**File:** `lib/app/playback_providers.dart`

```dart
/// Provider for ChapterPositionDao
final chapterPositionDaoProvider = Provider<ChapterPositionDao>((ref) {
  final db = ref.watch(databaseProvider);
  return ChapterPositionDao(db);
});

/// Whether user is in browsing mode for a book
final browsingModeProvider = StateProvider.family<bool, String>(
  (ref, bookId) => false,
);

/// Primary position for a book (snap-back target)
final primaryPositionProvider = FutureProvider.family<ChapterPosition?, String>(
  (ref, bookId) async {
    final dao = ref.read(chapterPositionDaoProvider);
    return dao.getPrimaryPosition(bookId);
  },
);

/// All chapter positions for a book
final chapterPositionsProvider = FutureProvider.family<Map<int, ChapterPosition>, String>(
  (ref, bookId) async {
    final dao = ref.read(chapterPositionDaoProvider);
    return dao.getAllPositions(bookId);
  },
);
```

### 2.2 Add Listening Actions Notifier

**File:** `lib/app/listening_actions_notifier.dart`

```dart
/// Actions for managing listening position and browsing
class ListeningActionsNotifier extends Notifier<void> {
  @override
  void build() {}
  
  /// Jump to a chapter, entering browsing mode if needed
  Future<void> jumpToChapter(
    String bookId, 
    int currentChapter,
    int currentSegment,
    int targetChapter,
  ) async {
    final isBrowsing = ref.read(browsingModeProvider(bookId));
    final dao = ref.read(chapterPositionDaoProvider);
    
    if (!isBrowsing) {
      // First jump - save current as primary
      await dao.clearPrimaryFlag(bookId);
      await dao.saveChapterPosition(
        bookId: bookId,
        chapterIndex: currentChapter,
        segmentIndex: currentSegment,
        isPrimary: true,
      );
      ref.read(browsingModeProvider(bookId).notifier).state = true;
    } else {
      // Already browsing - just save current position
      await dao.saveChapterPosition(
        bookId: bookId,
        chapterIndex: currentChapter,
        segmentIndex: currentSegment,
        isPrimary: false,
      );
    }
    
    // Get target position (existing position or start)
    final targetPosition = await dao.getChapterPosition(bookId, targetChapter);
    final targetSegment = targetPosition?.segmentIndex ?? 0;
    
    // Invalidate providers
    ref.invalidate(chapterPositionsProvider(bookId));
    ref.invalidate(primaryPositionProvider(bookId));
    
    // TODO: Actually navigate to target chapter/segment via playback controller
  }
  
  /// Snap back to primary position
  Future<void> snapBackToPrimary(String bookId) async {
    final dao = ref.read(chapterPositionDaoProvider);
    final primary = await dao.getPrimaryPosition(bookId);
    
    if (primary == null) return;
    
    // Exit browsing mode
    ref.read(browsingModeProvider(bookId).notifier).state = false;
    
    // TODO: Navigate to primary position
  }
  
  /// Commit current position as new primary (user wants to stay here)
  Future<void> commitCurrentPosition(
    String bookId,
    int currentChapter,
    int currentSegment,
  ) async {
    final dao = ref.read(chapterPositionDaoProvider);
    
    await dao.clearPrimaryFlag(bookId);
    await dao.saveChapterPosition(
      bookId: bookId,
      chapterIndex: currentChapter,
      segmentIndex: currentSegment,
      isPrimary: true,
    );
    
    // Exit browsing mode
    ref.read(browsingModeProvider(bookId).notifier).state = false;
    
    // Invalidate providers
    ref.invalidate(chapterPositionsProvider(bookId));
    ref.invalidate(primaryPositionProvider(bookId));
  }
}

final listeningActionsProvider = NotifierProvider<ListeningActionsNotifier, void>(
  ListeningActionsNotifier.new,
);
```

---

## Phase 3: Playback Screen Integration (Day 3-4) ✅ COMPLETED

### 3.1 Extend Existing "Resume Auto-Scroll" Button

**Key Insight:** Instead of adding a separate snap-back button, we extend the existing `_JumpToCurrentButton` in `text_display.dart` to handle cross-chapter navigation.

**File:** `lib/ui/screens/playback/widgets/text_display/text_display.dart`

Modify the existing button to detect browsing mode:

```dart
class _JumpToCurrentButton extends ConsumerWidget {
  const _JumpToCurrentButton({
    required this.bookId,
    required this.currentChapter,
    required this.onJumpToCurrent,  // Existing same-chapter scroll
  });
  
  final String bookId;
  final int currentChapter;
  final VoidCallback onJumpToCurrent;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final primaryAsync = ref.watch(primaryPositionProvider(bookId));
    
    // Determine if we're browsing a different chapter
    final primary = primaryAsync.valueOrNull;
    final isBrowsingDifferentChapter = 
        primary != null && primary.chapterIndex != currentChapter;
    
    // Button text and action differ based on state
    final String label;
    final VoidCallback onTap;
    
    if (isBrowsingDifferentChapter) {
      // Cross-chapter: snap back to primary position
      label = 'Back to Ch.${primary.chapterIndex + 1}';
      onTap = () => ref.read(listeningActionsProvider.notifier)
          .snapBackToPrimary(bookId);
    } else {
      // Same chapter: just scroll (existing behavior)
      label = 'Jump to Audio';
      onTap = onJumpToCurrent;
    }
    
    return Material(
      color: colors.primary,
      borderRadius: BorderRadius.circular(24),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.my_location, size: 18, color: colors.primaryForeground),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.primaryForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### 3.2 Update Button Visibility Logic

The button should appear when:
1. **Same chapter, scrolled away**: `!autoScrollEnabled` (existing)
2. **Different chapter (browsing)**: `currentChapter != primaryPosition.chapterIndex`

```dart
// In TextDisplayView build method
final showJumpButton = !widget.autoScrollEnabled || 
    (primaryPosition.valueOrNull?.chapterIndex != widget.chapterIndex);

if (showJumpButton)
  Positioned(
    bottom: 16,
    right: 16,
    child: _JumpToCurrentButton(
      bookId: widget.bookId,
      currentChapter: widget.chapterIndex,
      onJumpToCurrent: widget.onJumpToCurrent,
    ),
  ),
```

### 3.3 Original Snap-Back Button Approach (Alternative)

**File:** `lib/ui/screens/playback_screen.dart`

If we want a separate, always-visible button when browsing:

```dart
Widget _buildSnapBackButton(BuildContext context, String bookId) {
  final isBrowsing = ref.watch(browsingModeProvider(bookId));
  final primaryAsync = ref.watch(primaryPositionProvider(bookId));
  
  if (!isBrowsing) return const SizedBox.shrink();
  
  return primaryAsync.when(
    data: (primary) {
      if (primary == null) return const SizedBox.shrink();
      
      return TextButton.icon(
        onPressed: () => ref.read(listeningActionsProvider.notifier)
            .snapBackToPrimary(bookId),
        icon: const Icon(Icons.my_location),
        label: Text('Back to Ch.${primary.chapterIndex + 1}'),
      );
    },
    loading: () => const SizedBox.shrink(),
    error: (_, __) => const SizedBox.shrink(),
  );
}
```

### 3.2 Track Chapter Jumps

Update chapter navigation to use `ListeningActionsNotifier`:

```dart
void _onChapterSelected(int targetChapter) {
  final playbackState = ref.read(playbackStateProvider);
  
  ref.read(listeningActionsProvider.notifier).jumpToChapter(
    widget.bookId,
    _currentChapterIndex,
    playbackState.currentIndex,
    targetChapter,
  );
}
```

### 3.3 Auto-Promote After Duration

Add timer to promote browsing position after 30 seconds of listening:

```dart
Timer? _browsingPromotionTimer;

void _startBrowsingPromotionTimer() {
  _browsingPromotionTimer?.cancel();
  final isBrowsing = ref.read(browsingModeProvider(widget.bookId));
  
  if (!isBrowsing) return;
  
  _browsingPromotionTimer = Timer(const Duration(seconds: 30), () {
    if (!mounted) return;
    final playbackState = ref.read(playbackStateProvider);
    if (!playbackState.playing) return;  // Only if still playing
    
    ref.read(listeningActionsProvider.notifier).commitCurrentPosition(
      widget.bookId,
      _currentChapterIndex,
      playbackState.currentIndex,
    );
  });
}

// Call this when playback resumes
void _onPlaybackResumed() {
  _startBrowsingPromotionTimer();
}

// Cancel when paused
void _onPlaybackPaused() {
  _browsingPromotionTimer?.cancel();
}
```

---

## Phase 4: Book Details Integration (Day 5) ✅ COMPLETED

### 4.1 Update Chapter List Badges

**Status: COMPLETED** - The chapter list now uses `primaryPosition` to determine which chapter shows the "CONTINUE HERE" badge.

Show primary position indicator:

```dart
// Use primary position for "current chapter" indicator (badge, highlighting)
// Falls back to book.progress if no primary position is set
final currentChapterIndex = primaryPosition?.chapterIndex ?? book.progress.chapterIndex;
final isCurrentChapter = index == currentChapterIndex;
```

### 4.2 Update Continue Listening Logic

**Status: COMPLETED** - Continue Listening button and chapter taps now navigate with query params.

- PlaybackScreen now accepts `initialChapter` and `initialSegment` parameters
- GoRouter route updated to parse `?chapter=X&segment=Y` query params
- Continue Listening button passes primary position params when available
- Chapter list onTap navigates directly to that chapter with segment 0 (or primary segment if current chapter)

---

## Testing Checklist

### Unit Tests
- [ ] `ChapterPositionDao.saveChapterPosition` inserts/updates correctly
- [ ] `ChapterPositionDao.getPrimaryPosition` returns correct position
- [ ] `ChapterPositionDao.clearPrimaryFlag` clears all primary flags
- [ ] `ListeningActionsNotifier.jumpToChapter` saves position and enters browsing mode
- [ ] `ListeningActionsNotifier.snapBackToPrimary` navigates and exits browsing mode
- [ ] `ListeningActionsNotifier.commitCurrentPosition` promotes and exits browsing

### Integration Tests
- [ ] Jump chapter → snap back workflow
- [ ] Auto-promotion after 30 seconds
- [ ] Multiple chapter browsing with positions preserved
- [ ] Exit playback → return → correct resume position

### Manual Testing
- [ ] Verify snap-back button appears when browsing
- [ ] Verify primary badge shows on chapter list
- [ ] Verify "Continue Listening" respects primary position
- [ ] Verify positions survive app restart

---

## Files to Create/Modify

### New Files
1. `lib/app/database/migrations/migration_v4.dart`
2. `lib/app/database/daos/chapter_position_dao.dart`
3. `lib/app/listening_actions_notifier.dart`
4. `lib/ui/widgets/mini_player.dart`
5. `test/unit/database/chapter_position_dao_test.dart`
6. `test/unit/listening_actions_notifier_test.dart`

### Modified Files
1. `lib/app/database/database.dart` - Add version bump and migration
2. `lib/app/playback_providers.dart` - Add position providers
3. `lib/ui/screens/playback_screen.dart` - Add snap-back UI, browsing tracking
4. `lib/ui/screens/book_details_screen.dart` - Add primary badge, update resume logic
5. `lib/main.dart` - Add mini-player wrapper to app

---

## Phase 5: Mini-Player Integration (Day 6-7)

### Overview

Add a persistent mini-player (like YouTube Music/Spotify) that appears at the bottom of screens while audio is playing. This allows users to browse the app while playback continues, with quick access to playback controls.

### Design Principles (Best Practices)

**Placement & Visibility:**
- Display at the bottom of the screen, above the navigation bar (if present)
- Persist across most screens while playback is active
- **DO NOT show on:** Settings screens, Downloads screen, full Playback screen
- **DO show on:** Library screen, Book Details screen

**Interaction Patterns:**
1. **Tap on mini-player:** Navigate to full playback screen
2. **Swipe up:** Expand to full playback screen (optional enhancement)
3. **Tap play/pause:** Toggle playback without navigation
4. **Tap skip (if shown):** Skip to next segment

**Visual Design:**
- Height: 56-64dp (compact but tappable)
- Content: Book cover thumbnail, title, play/pause button, optional progress indicator
- Background: Match app theme, slight elevation or border to distinguish from content
- Animation: Slide up/down when appearing/disappearing

### 5.1 Create MiniPlayer Widget

**File:** `lib/ui/widgets/mini_player.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback_providers.dart';
import '../../app/library_controller.dart';
import '../theme/app_colors.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(playbackStateProvider);
    final libraryAsync = ref.watch(libraryProvider);
    final colors = context.appColors;

    // Don't show if nothing is playing
    if (!playbackState.isPlaying && !playbackState.isPaused) {
      return const SizedBox.shrink();
    }

    // Don't show if no book is loaded
    final bookId = playbackState.bookId;
    if (bookId == null) {
      return const SizedBox.shrink();
    }

    return libraryAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (library) {
        final book = library.books.where((b) => b.id == bookId).firstOrNull;
        if (book == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => context.push('/playback/$bookId'),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(
                top: BorderSide(color: colors.border, width: 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  // Book cover thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: book.coverImage != null
                          ? Image.memory(book.coverImage!, fit: BoxFit.cover)
                          : Container(
                              color: colors.primary.withValues(alpha: 0.1),
                              child: Icon(Icons.book, color: colors.primary),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Title and progress
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colors.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Segment ${playbackState.currentIndex + 1}/${playbackState.queue.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Play/Pause button
                  IconButton(
                    onPressed: () {
                      final controller = ref.read(playbackControllerProvider.notifier);
                      if (playbackState.isPlaying) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                    },
                    icon: Icon(
                      playbackState.isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 32,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
```

### 5.2 Create MiniPlayerScaffold Wrapper

**File:** `lib/ui/widgets/mini_player_scaffold.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mini_player.dart';

/// Wraps a screen with a mini-player at the bottom when playback is active.
/// 
/// Usage: Wrap screens where the mini-player should appear.
class MiniPlayerScaffold extends ConsumerWidget {
  const MiniPlayerScaffold({
    super.key,
    required this.child,
    this.showMiniPlayer = true,
  });

  final Widget child;
  final bool showMiniPlayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!showMiniPlayer) return child;

    return Column(
      children: [
        Expanded(child: child),
        const MiniPlayer(),
      ],
    );
  }
}
```

### 5.3 Integration with Router

**File:** `lib/main.dart` - Update routes to use MiniPlayerScaffold

For screens that should show the mini-player:

```dart
// Library screen
GoRoute(
  path: '/',
  builder: (context, state) => const MiniPlayerScaffold(
    child: LibraryScreen(),
  ),
),

// Book details screen  
GoRoute(
  path: '/book/:id',
  builder: (context, state) {
    final bookId = state.pathParameters['id']!;
    return MiniPlayerScaffold(
      child: BookDetailsScreen(bookId: bookId),
    );
  },
),
```

For screens that should NOT show the mini-player:

```dart
// Settings screen - no mini-player
GoRoute(
  path: '/settings',
  builder: (context, state) => const SettingsScreen(),
),

// Playback screen - no mini-player (it IS the player)
GoRoute(
  path: '/playback/:bookId',
  builder: (context, state) {
    final bookId = state.pathParameters['bookId']!;
    return PlaybackScreen(bookId: bookId);
  },
),
```

### 5.4 Enhanced Mini-Player Features (Optional)

For a more polished experience, consider these enhancements:

**Progress Indicator:**
```dart
// Add a thin progress bar at the bottom of the mini-player
Positioned(
  bottom: 0,
  left: 0,
  right: 0,
  child: LinearProgressIndicator(
    value: playbackState.currentIndex / playbackState.queue.length,
    backgroundColor: colors.border,
    valueColor: AlwaysStoppedAnimation(colors.primary),
    minHeight: 2,
  ),
),
```

**Swipe-to-Dismiss:**
```dart
Dismissible(
  key: Key('mini-player-$bookId'),
  direction: DismissDirection.down,
  onDismissed: (_) {
    ref.read(playbackControllerProvider.notifier).stop();
  },
  child: // ... mini-player content
)
```

**Expand Animation (Hero-style):**
Using `Hero` widget to animate between mini-player and full player.

### Where Mini-Player Should Appear

| Screen | Show Mini-Player | Reason |
|--------|-----------------|--------|
| Library | ✅ Yes | Browse books while listening |
| Book Details | ✅ Yes | View chapter list while listening |
| Playback | ❌ No | Already showing full player |
| Settings | ❌ No | Settings should be focused, distraction-free |
| Downloads | ❌ No | System management, not content browsing |
| Voice Selection | ❌ No | Sub-settings, focused task |

### Testing Considerations

- [ ] Mini-player appears when playback starts
- [ ] Mini-player disappears when playback stops
- [ ] Tapping mini-player navigates to full playback screen
- [ ] Play/pause button works correctly
- [ ] Mini-player doesn't appear on excluded screens
- [ ] Mini-player updates when book/chapter changes
- [ ] Mini-player respects theme (light/dark mode)

---

## Estimated Timeline

| Phase | Description | Duration |
|-------|-------------|----------|
| 1 | Database schema + DAO | 2-3 hours |
| 2 | Providers | 1-2 hours |
| 3 | Playback screen integration | 3-4 hours |
| 4 | Book details integration | 2-3 hours |
| 5 | Mini-player integration | 3-4 hours |
| 6 | Testing | 2-3 hours |
| **Total** | | **14-19 hours** |
