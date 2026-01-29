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
│                              NAVIGATION FLOW                                 │
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
│   └──────────────┘         back button         └──────────────┘             │
│                                                                              │
│   Key: PlaybackScreen automatically enters preview mode if the              │
│        requested chapter differs from the currently playing chapter.        │
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
- Audio IS playing a different chapter
- User navigates to view another chapter

Features:
- **Mini player** at bottom showing what's currently playing
- "Tap to play" hint above mini player
- Chapter text is displayed (for reading/browsing)
- Tapping any segment → switches audio to that position, exits preview mode
- Tapping mini player → navigates to the currently playing chapter
- Progress NOT auto-saved (just browsing)

## State Transitions

```
┌─────────────────────────────────────────────────────────────────┐
│                    PREVIEW MODE TRANSITIONS                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────┐                    ┌─────────────┐            │
│   │   ACTIVE    │  navigate to       │   PREVIEW   │            │
│   │    MODE     │  different   ────► │    MODE     │            │
│   │             │  chapter           │             │            │
│   └─────────────┘                    └──────┬──────┘            │
│         ▲                                   │                    │
│         │                                   │                    │
│         │     tap segment                   │                    │
│         │     (switches audio)              │                    │
│         └───────────────────────────────────┘                    │
│                                                                  │
│         ▲                                   │                    │
│         │     tap mini player               │                    │
│         │     (go to playing chapter)       │                    │
│         └───────────────────────────────────┘                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
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

## State Persistence

### On App Close
- Current position auto-saved every 30 seconds (active mode only)
- Primary position preserved in SQLite
- Audio state is lost (must restart playback)

### On App Resume
- Primary position loaded from database
- "Continue Listening" button available
- Mini player hidden until playback starts
