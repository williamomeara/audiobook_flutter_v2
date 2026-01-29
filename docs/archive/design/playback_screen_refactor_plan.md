# Playback Screen Refactoring Plan

## Current State

**File:** `lib/ui/screens/playback_screen.dart`  
**Lines:** 1,915 lines  
**Widget Count:** 12 major widget builders + ~15 helper methods  
**Complexity:** High (multiple responsibilities mixed together)

---

## Current Structure Analysis

### State Variables (Lines 35-75)
- Initialization flags
- Scroll controller + auto-scroll state
- View mode (cover vs text)
- Sleep timer state
- Orientation animation
- Cache verification counters
- Auto-save timer

### Lifecycle Methods (Lines 135-365)
- `initState()` - Multiple setup calls
- `dispose()` - Timer cleanup
- `didChangeMetrics()` - Orientation change detection
- `_initializePlayback()` - Complex async initialization

### Playback Control Methods (Lines 441-692)
- `_togglePlay()` / `_nextSegment()` / `_previousSegment()`
- `_nextChapter()` / `_previousChapter()`
- `_setPlaybackRate()` / `_increaseSpeed()` / `_decreaseSpeed()`
- Sleep timer management
- Save progress and pop

### Main Build Method (Lines 710-860)
- Complex library/book loading
- Orientation handling
- Layout switching (portrait/landscape)
- Error states

### Widget Builders (~1,000 lines)
| Widget | Lines | Responsibility |
|--------|-------|----------------|
| `_buildHeader` | ~50 | Chapter title, navigation |
| `_buildErrorBanner` | ~15 | Error display |
| `_buildLandscapeLayout` | ~80 | Landscape wrapper |
| `_buildPortraitLayout` | ~40 | Portrait wrapper |
| `_buildCoverView` | ~60 | Book cover display |
| `_buildCoverPlaceholder` | ~30 | Cover fallback |
| `_buildTextDisplay` | ~180 | **Largest** - Scrollable text with segments |
| `_buildTimeRemainingRow` | ~70 | Duration display |
| `_buildPlaybackControls` | ~230 | **Second largest** - All controls |
| `_buildPlayButton` | ~30 | Play/pause button |
| `_buildLandscapeControls` | ~140 | Landscape control panel |
| `_buildLandscapeBottomBar` | ~90 | Landscape bottom bar |

---

## Refactoring Goals

1. **Single Responsibility** - Each file handles one concern
2. **Testability** - Widgets can be tested in isolation
3. **Maintainability** - Changes are localized
4. **Reusability** - Common patterns extracted
5. **State Management** - Clear separation of state from UI

---

## Proposed File Structure

```
lib/ui/screens/playback/
├── playback_screen.dart              # Main scaffold (~200 lines)
│   └── Handles: Initialization, orientation, layout switching
│
├── playback_state_controller.dart    # State management (~150 lines)  
│   └── Handles: Playback actions, timers, auto-advance
│
├── layouts/
│   ├── portrait_layout.dart          # Portrait view (~80 lines)
│   └── landscape_layout.dart         # Landscape view (~100 lines)
│
├── widgets/
│   ├── playback_header.dart          # Chapter title, navigation (~60 lines)
│   ├── cover_view.dart               # Cover image display (~100 lines)
│   ├── text_display/
│   │   ├── text_display.dart         # Main text view (~100 lines)
│   │   └── segment_tile.dart         # Individual segment widget (~80 lines)
│   ├── controls/
│   │   ├── playback_controls.dart    # Main controls wrapper (~80 lines)
│   │   ├── play_button.dart          # Play/pause button (~40 lines)
│   │   ├── speed_control.dart        # Speed adjustment (~50 lines)
│   │   ├── sleep_timer_control.dart  # Sleep timer (~50 lines)
│   │   └── chapter_nav_buttons.dart  # Prev/next chapter (~40 lines)
│   ├── progress/
│   │   ├── time_remaining_row.dart   # Time remaining display (~80 lines)
│   │   └── segment_slider.dart       # Already exists, may move here
│   └── landscape/
│       ├── landscape_controls.dart   # Landscape control panel (~150 lines)
│       └── landscape_bottom_bar.dart # Landscape bottom bar (~100 lines)
│
└── dialogs/
    ├── no_voice_dialog.dart          # Voice selection prompt (~40 lines)
    ├── sleep_timer_dialog.dart       # Sleep timer picker (~60 lines)
    └── chapter_jump_dialog.dart      # Future: Chapter jump (~100 lines)
```

**Total: ~1,440 lines across 18 files** (vs 1,915 in 1 file)

---

## Refactoring Phases

### Phase 1: Extract Dialogs (Quick Win)
**Effort:** 30 minutes  
**Impact:** Low risk, immediate cleanup

Extract to `lib/ui/screens/playback/dialogs/`:
- [ ] `no_voice_dialog.dart` - Current `_showNoVoiceDialog()` method
- [ ] `sleep_timer_dialog.dart` - Sleep timer sheet (currently inline)

### Phase 2: Extract Widget Components
**Effort:** 2-3 hours  
**Impact:** Significant code reduction

Extract to `lib/ui/screens/playback/widgets/`:
- [ ] `playback_header.dart` - `_buildHeader()` → `PlaybackHeader` widget
- [ ] `cover_view.dart` - `_buildCoverView()` + `_buildCoverPlaceholder()` → `CoverView` widget
- [ ] `time_remaining_row.dart` - `_buildTimeRemainingRow()` → `TimeRemainingRow` widget
- [ ] `play_button.dart` - `_buildPlayButton()` → `PlayButton` widget

### Phase 3: Extract Control Widgets
**Effort:** 2-3 hours  
**Impact:** Reduces largest widget builders

Extract to `lib/ui/screens/playback/widgets/controls/`:
- [ ] `speed_control.dart` - Speed adjustment row
- [ ] `sleep_timer_control.dart` - Sleep timer row  
- [ ] `chapter_nav_buttons.dart` - Prev/next chapter buttons
- [ ] `playback_controls.dart` - Assembles control components

### Phase 4: Extract Text Display
**Effort:** 2-3 hours  
**Impact:** Reduces most complex widget

Extract to `lib/ui/screens/playback/widgets/text_display/`:
- [ ] `segment_tile.dart` - Individual segment widget (currently inline)
- [ ] `text_display.dart` - `_buildTextDisplay()` → `TextDisplayView` widget

### Phase 5: Extract Layouts
**Effort:** 1-2 hours  
**Impact:** Cleaner main build method

Extract to `lib/ui/screens/playback/layouts/`:
- [ ] `portrait_layout.dart` - `_buildPortraitLayout()`
- [ ] `landscape_layout.dart` - `_buildLandscapeLayout()` + `_buildLandscapeControls()` + `_buildLandscapeBottomBar()`

### Phase 6: State Management Refactor
**Effort:** 3-4 hours  
**Impact:** Better testability, cleaner state

Consider:
- [ ] Create `PlaybackScreenController` class (or Notifier)
- [ ] Move timer logic (sleep, auto-save) to controller
- [ ] Move playback actions to controller
- [ ] Keep widget state minimal (UI only)

---

## Implementation Strategy

### Option A: Incremental Extraction
Extract one component at a time, test, commit. Lower risk but slower.

```
Week 1: Phases 1-2 (Dialogs + Simple widgets)
Week 2: Phase 3 (Controls)
Week 3: Phases 4-5 (Text display + Layouts)
Week 4: Phase 6 (State management - optional)
```

### Option B: Big Bang Refactor
Extract all at once in a feature branch. Faster but higher risk.

```
Day 1: Create folder structure, move all widgets
Day 2: Fix imports, run tests
Day 3: Manual testing, fixes
```

**Recommended:** Option A (Incremental) - Each commit is testable and revertible.

---

## Widget Communication Pattern

### Current (Implicit)
```dart
// Parent owns all state and callbacks
Widget _buildPlayButton(...) {
  return IconButton(
    onPressed: _togglePlay,  // Method on parent
    ...
  );
}
```

### Proposed (Explicit Props)
```dart
// Extracted widget receives explicit callbacks
class PlayButton extends StatelessWidget {
  final bool isPlaying;
  final bool isBuffering;
  final VoidCallback onToggle;
  
  // Build method
}

// Usage in parent
PlayButton(
  isPlaying: playbackState.isPlaying,
  isBuffering: playbackState.isBuffering,
  onToggle: _togglePlay,
)
```

---

## File Size Targets

| File | Target Lines | Notes |
|------|--------------|-------|
| playback_screen.dart | ~200 | Main scaffold only |
| Any widget file | ~100-150 | Single responsibility |
| Dialogs | ~40-80 | Simple, focused |
| Layouts | ~80-100 | Layout composition only |

---

## Testing Considerations

### Current State
- Hard to test individual components
- Must render entire PlaybackScreen

### After Refactor
- Each widget testable in isolation
- Mock playback state easily
- Test controls without full playback setup

### Test Files to Create
```
test/ui/screens/playback/
├── playback_screen_test.dart
├── widgets/
│   ├── play_button_test.dart
│   ├── speed_control_test.dart
│   └── text_display_test.dart
└── dialogs/
    └── sleep_timer_dialog_test.dart
```

---

## Migration Checklist

- [ ] Create `lib/ui/screens/playback/` folder
- [ ] Phase 1: Extract dialogs
- [ ] Phase 2: Extract simple widgets
- [ ] Phase 3: Extract controls
- [ ] Phase 4: Extract text display
- [ ] Phase 5: Extract layouts
- [ ] Phase 6: State management (optional)
- [ ] Update imports in main app
- [ ] Run full test suite
- [ ] Manual testing (all features work)
- [ ] Delete old monolithic file
- [ ] Update this document

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Breaking playback | Medium | Test each extraction thoroughly |
| Import issues | Low | Use barrel file (index.dart) |
| State bugs | Medium | Keep state in one place initially |
| Regression | Medium | Run all 422 tests after each phase |

---

## Estimated Total Effort

| Phase | Time |
|-------|------|
| Phase 1 (Dialogs) | 30 min |
| Phase 2 (Simple widgets) | 2-3 hours |
| Phase 3 (Controls) | 2-3 hours |
| Phase 4 (Text display) | 2-3 hours |
| Phase 5 (Layouts) | 1-2 hours |
| Phase 6 (State - optional) | 3-4 hours |
| Testing & fixes | 2-3 hours |
| **Total** | **~12-18 hours** |

Can be spread over multiple sessions.
