# Last Listened Location - Implementation Plan

## Phase 1: Database Schema (Day 1)

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

## Phase 2: Providers (Day 2)

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

## Phase 3: Playback Screen Integration (Day 3-4)

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

## Phase 4: Book Details Integration (Day 5)

### 4.1 Update Chapter List Badges

Show primary position indicator:

```dart
Widget _buildChapterBadge(int chapterIndex, String bookId) {
  final primaryAsync = ref.watch(primaryPositionProvider(bookId));
  final isPrimary = primaryAsync.valueOrNull?.chapterIndex == chapterIndex;
  
  if (isPrimary) {
    return const Icon(Icons.my_location, size: 16, color: Colors.blue);
  }
  
  // ... existing badge logic
}
```

### 4.2 Update Continue Listening Logic

Prefer primary position over last saved position:

```dart
void _onContinueListening(String bookId) async {
  final dao = ref.read(chapterPositionDaoProvider);
  final primary = await dao.getPrimaryPosition(bookId);
  
  if (primary != null) {
    // Resume from primary position
    context.push('/playback/$bookId?chapter=${primary.chapterIndex}&segment=${primary.segmentIndex}');
  } else {
    // Fall back to book.progress
    final book = ref.read(libraryProvider).value?.books
        .firstWhere((b) => b.id == bookId);
    context.push('/playback/$bookId?chapter=${book?.progress.chapterIndex ?? 0}');
  }
}
```

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
4. `test/unit/database/chapter_position_dao_test.dart`
5. `test/unit/listening_actions_notifier_test.dart`

### Modified Files
1. `lib/app/database/database.dart` - Add version bump and migration
2. `lib/app/playback_providers.dart` - Add position providers
3. `lib/ui/screens/playback_screen.dart` - Add snap-back UI, browsing tracking
4. `lib/ui/screens/book_details_screen.dart` - Add primary badge, update resume logic

---

## Estimated Timeline

| Phase | Description | Duration |
|-------|-------------|----------|
| 1 | Database schema + DAO | 2-3 hours |
| 2 | Providers | 1-2 hours |
| 3 | Playback screen integration | 3-4 hours |
| 4 | Book details integration | 2-3 hours |
| 5 | Testing | 2-3 hours |
| **Total** | | **10-15 hours** |
