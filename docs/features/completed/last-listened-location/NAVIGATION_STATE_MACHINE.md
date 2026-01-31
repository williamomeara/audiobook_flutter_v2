# Navigation State Machine

## Overview

This document describes the complete navigation flow for audiobook playback, including the "preview mode" feature that allows users to browse chapters while audio continues playing.

## Simplified Architecture

The PlaybackScreen handles both active playback and preview mode in a single screen, switching between them based on context:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PLAYBACK SCREEN MODES                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────┐      │
│   │                        PLAYBACK SCREEN                            │      │
│   │                                                                   │      │
│   │  ┌─────────────────┐              ┌─────────────────┐            │      │
│   │  │  ACTIVE MODE    │              │  PREVIEW MODE   │            │      │
│   │  │                 │   tap        │                 │            │      │
│   │  │ • Full controls │◄─ segment ───│ • Mini player   │            │      │
│   │  │ • Audio playing │              │ • Text browsing │            │      │
│   │  │ • Auto-scroll   │              │ • No auto-save  │            │      │
│   │  │                 │              │                 │            │      │
│   │  └─────────────────┘              └─────────────────┘            │      │
│   │           ▲                               ▲                       │      │
│   │           │                               │                       │      │
│   │    Navigate to                     Navigate to                    │      │
│   │    same chapter                  different chapter                │      │
│   │    as playing                    than playing                     │      │
│   │           │                               │                       │      │
│   └───────────┼───────────────────────────────┼───────────────────────┘      │
│               │                               │                              │
│               └───────────┬───────────────────┘                              │
│                           │                                                  │
│                    BookDetailsScreen                                         │
│                    (tap any chapter)                                         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Navigation Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          NAVIGATION FLOW (EXPANDED)                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────┐                                                           │
│   │   Library    │                                                           │
│   │   Screen     │                                                           │
│   └──────┬───────┘                                                           │
│          │ tap book                                                          │
│          ▼                                                                   │
│   ┌──────────────┐         tap chapter         ┌──────────────┐             │
│   │    Book      │ ───────────────────────────►│   Playback   │             │
│   │   Details    │                             │    Screen    │             │
│   │   Screen     │◄────────────────────────────│              │             │
│   └──────┬───────┘         back button         └──────────────┘             │
│          │                                            ▲                      │
│          │ (if audio playing different book)         │                      │
│          │ PREVIEW MODE: Mini player + text          │                      │
│          │                                            │                      │
│   ┌──────▼───────┐    tap "Start Listening"   ┌──────┴──────┐             │
│   │  Different   │ ───────────────────────────►│   Playback  │             │
│   │    Book      │ or tap text segment         │   (Active)  │             │
│   │   Details    │                             │             │             │
│   │  (Preview)   │◄─────────────────────────────│             │             │
│   └──────────────┘     tap mini player        └─────────────┘             │
│                                                                              │
│   Key: Preview mode allows browsing different books while audio plays.     │
│        Mini player shows what's currently playing.                          │
│        Tapping text or "Start Listening" switches playback.                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## PlaybackScreen Modes

### Active Mode (Default)
Shown when:
- No audio is currently playing, OR
- User navigates to the same chapter that's playing

Features:
- Full playback controls (play/pause, skip, speed, sleep timer)
- Segment seek slider
- Auto-scroll to current segment
- Progress auto-saved every 30 seconds

### Preview Mode
Shown when:
- Audio IS playing in one context (Book A, Chapter 3)
- User navigates to view a DIFFERENT context:
  - Different chapter of same book, OR
  - Different book entirely

Features:
- **Mini player** at bottom showing what's currently playing (Book A's audio)
- "Tap to play" hint above mini player
- Chapter text is displayed (for reading/browsing)
- Tapping any segment → switches audio to that position, exits preview mode
- Tapping mini player → navigates to the currently playing chapter/book
- Clicking "Start Listening" button → commits to this book, starts from beginning or saved position
- Progress NOT auto-saved (just browsing)

**Cross-Book Preview Example:**
- Book A, Chapter 3 is playing (audio ongoing)
- User navigates to Book B's Book Details
- Taps a chapter in Book B → enters Preview Mode
- Sees Book B's text with Book A's mini player at bottom
- Either:
  - Clicks "Start Listening" → stops Book A, starts playing Book B
  - Taps a segment in Book B → switches to that segment in Book B
  - Taps mini player → returns to Book A, Chapter 3

## State Transitions

```
┌──────────────────────────────────────────────────────────────────────┐
│              PREVIEW MODE TRANSITIONS (SAME & CROSS-BOOK)             │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│   SAME BOOK NAVIGATION:                                              │
│   ┌─────────────┐                    ┌─────────────┐                │
│   │   ACTIVE    │  navigate to       │   PREVIEW   │                │
│   │    MODE     │  different   ────► │    MODE     │                │
│   │             │  chapter           │ (same book) │                │
│   │ Book A, Ch 1│                    │ Book A, Ch 5│                │
│   └─────────────┘                    └──────┬──────┘                │
│         ▲                                   │                        │
│         │                                   │                        │
│         │     tap segment                   │                        │
│         │     (switches audio in A)         │                        │
│         └───────────────────────────────────┘                        │
│                                                                       │
│   CROSS-BOOK NAVIGATION:                                             │
│   ┌─────────────┐                    ┌─────────────┐                │
│   │   ACTIVE    │  navigate to       │   PREVIEW   │                │
│   │    MODE     │  different   ────► │    MODE     │                │
│   │             │  book              │             │                │
│   │ Book A, Ch 1│                    │ Book B, Ch 3│                │
│   │ (playing)   │                    │ (browsing)  │                │
│   └─────────────┘                    └──────┬──────┘                │
│         ▲                                   │                        │
│         │                                   │                        │
│         │     tap "Start Listening"         │                        │
│         │     or tap segment                │                        │
│         │     (switches to Book B)          │                        │
│         └───────────────────────────────────┘                        │
│         ▲                                   │                        │
│         │     tap mini player               │                        │
│         │     (return to Book A)            │                        │
│         └───────────────────────────────────┘                        │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

## Audio State

```
┌─────────────────────────────────────────────────────────────────┐
│                      AUDIO STATES                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────┐     play()      ┌──────────┐                     │
│   │  IDLE    │ ───────────────►│ PLAYING  │◄─────┐              │
│   │          │                 │          │      │              │
│   └────┬─────┘                 └────┬─────┘      │              │
│        │                            │            │              │
│        │                     pause()│      play()│              │
│        │                            ▼            │              │
│        │                       ┌──────────┐      │              │
│        │                       │  PAUSED  │──────┘              │
│        │                       │          │                     │
│        │                       └────┬─────┘                     │
│        │                            │                           │
│        │◄───────────────────────────┘                           │
│                   stop() / chapter ends                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Position Tracking

### Primary Position
- The "Continue Listening" position
- Stored in `chapter_positions` table with `is_primary = true`
- Updated when:
  - User taps segment in preview mode (commits to new position)
  - User starts playback from BookDetails
  - Auto-save timer fires during active playback
  - Chapter navigation (next/previous)
- NOT updated during preview mode browsing

### Chapter Positions
- Per-chapter resume positions
- Stored in `chapter_positions` table with `is_primary = false`
- Used when returning to a previously-visited chapter

## UI Components by Mode

### Active Mode UI
```
┌────────────────────────────────────────┐
│ ← Book Title                      📖  │  Header
│   Chapter Title                        │
├────────────────────────────────────────┤
│                                        │
│   [Segment text displayed here...]     │  Text View
│                                        │
├────────────────────────────────────────┤
│ ──●────────────────────────── 12/45    │  Seek Slider
│ 15m remaining in chapter               │  Time Info
├────────────────────────────────────────┤
│  0.75x  ─  +     ⏰ 30m remaining     │  Speed/Timer
├────────────────────────────────────────┤
│   ⏮️   ◀️     ▶️      ▶️   ⏭️         │  Controls
└────────────────────────────────────────┘
```

### Preview Mode UI
```
┌────────────────────────────────────────┐
│ ← Book Title                      📖  │  Header
│   Chapter Title (PREVIEWING)           │
├────────────────────────────────────────┤
│                                        │
│   [Segment text - tap to play...]      │  Text View
│                                        │
├────────────────────────────────────────┤
│   👆 Tap any paragraph to play         │  Hint
├────────────────────────────────────────┤
│ 📚 Now Playing                    ▶️ › │  Mini Player
│    Chapter 3: The Adventure            │
└────────────────────────────────────────┘
```

## Key Design Decisions

### Single Screen vs Two Screens
Previously, we had separate `ChapterPreviewScreen` and `PlaybackScreen`. Now unified into one `PlaybackScreen` with two modes. Benefits:
- Less code duplication
- Smoother transitions (no navigation, just UI change)
- Reuses all segment display, scrolling, and styling logic
- Simpler mental model for users

### Why Mini Player in Preview Mode
- Shows what's currently playing without interrupting browsing
- Provides quick access to return to the playing chapter
- Play/pause control remains accessible
- Visual distinction from active playback mode

### Segment Tap Behavior
- **Active mode**: Seek to that segment (audio continues in same chapter)
- **Preview mode**: Switch audio to that chapter/segment (commits to new position)

This makes the user's intent explicit:
- Just scrolling = browsing, no commitment
- Tapping a segment = "I want to listen from here"

## Explore Mode (Cross-Book Preview)

"Explore mode" refers to the ability to browse other books while audio continues playing in the mini player.

### Workflow
1. **Book A is playing** (audio ongoing in background)
   - User can be on Library screen, Book A's details, or browsing Book A in preview mode

2. **Navigate to Book B's details**
   - Mini player shows Book A's audio (what's currently playing)
   - Book B content is available for preview

3. **Preview Book B's chapters**
   - Tap a chapter in Book B → enters Preview Mode
   - Text of Book B is displayed
   - Mini player at bottom shows Book A's audio (no interruption)
   - Hint: "Tap any paragraph to play" (to switch to Book B)

4. **Switch to Book B (3 options)**
   - **Option 1**: Click "Start Listening" on Book B details
     - Stops Book A playback
     - Starts Book B from beginning or saved position
   - **Option 2**: Tap a segment in Book B's preview text
     - Immediately switches audio to that segment in Book B
   - **Option 3**: Tap mini player
     - Returns to Book A's playback (where you were)

### Key Points
- Audio only plays ONE book at a time
- Mini player always shows what's currently playing (not what you're previewing)
- Preview mode doesn't auto-save progress (just browsing)
- Switching books via "Start Listening" or text tap saves that as new primary position
- You can browse many books without changing what's playing

## State Persistence

### On App Close
- Current position auto-saved every 30 seconds (active mode only)
- Primary position preserved in SQLite
- Audio state is lost (must restart playback)

### On App Resume
- Primary position loaded from database
- "Continue Listening" button available
- Mini player hidden until playback starts
