# Seek Bar Implementation Plan

## Current State

The playback screen currently has:
- **LinearProgressIndicator** showing segment progress (read-only, not interactive)
- **Segment tap-to-seek**: Users can tap on text segments to seek
- **No draggable seek bar** for scrubbing through audio

## User Need

Users want to:
1. See their position within the current segment/chapter
2. Drag to seek forward/backward
3. Get tactile feedback while scrubbing (haptic ticks)

## Challenges

### Challenge 1: TTS Audio Model is Different

This is **not** a traditional audio player with a fixed-length audio file. Instead:
- Audio is **synthesized on-demand** via TTS
- Each chapter has multiple **segments** (sentences/paragraphs)
- Segment audio may or may not be cached
- We don't know total duration until all segments are synthesized

### Challenge 2: What Does "Position" Mean?

Options for what the seek bar represents:

| Model | Seek Unit | Pros | Cons |
|-------|-----------|------|------|
| **Segment-based** | Current segment N of M | Simple, matches existing UI | Can't seek within a segment |
| **Duration-based** | Time within chapter | Natural for audio | Requires duration calculation |
| **Hybrid** | Time within current segment | Most accurate | Complex implementation |

## Proposed Solution

### Phase 1: Enhanced Segment Progress Bar (Simple)

Convert the current `LinearProgressIndicator` to a **draggable slider** for segment selection.

**User Experience:**
- Drag to select segment (1 to N)
- Haptic tick at each segment boundary
- Heavy haptic at chapter start/end
- Release to seek to that segment

**Implementation:**
```dart
Slider(
  value: currentSegmentIndex.toDouble(),
  min: 0,
  max: (totalSegments - 1).toDouble(),
  divisions: totalSegments - 1,
  onChanged: (value) {
    AppHaptics.selection(); // Tick on each segment
    _previewSegmentIndex = value.toInt();
  },
  onChangeEnd: (value) {
    _seekToSegment(value.toInt());
  },
)
```

**Pros:**
- Simple to implement
- Matches current playback model
- No duration calculation needed
- Natural for TTS-synthesized content

**Cons:**
- Can't seek within a segment
- Segment lengths vary

---

### Phase 2: Time-Based Seek Bar (Advanced)

Add a time-based seek bar **within the current segment**.

**Requirements:**
1. Track audio duration of current segment
2. Show current position in seconds
3. Allow drag to seek within segment
4. Update when segment changes

**Implementation:**
```dart
StreamBuilder<Duration>(
  stream: audioPlayer.positionStream,
  builder: (context, snapshot) {
    final position = snapshot.data ?? Duration.zero;
    final duration = audioPlayer.duration ?? Duration.zero;
    
    return Slider(
      value: position.inMilliseconds.toDouble(),
      max: duration.inMilliseconds.toDouble(),
      onChanged: (value) {
        // Tick every 10 seconds
        if ((value / 10000).floor() != (_lastTickValue / 10000).floor()) {
          AppHaptics.selection();
        }
        _previewPosition = Duration(milliseconds: value.toInt());
      },
      onChangeEnd: (value) {
        audioPlayer.seek(Duration(milliseconds: value.toInt()));
      },
    );
  },
)
```

**Challenges:**
- Need to expose position/duration from playback provider
- May require changes to `packages/playback`

---

## Recommended Approach

**Start with Phase 1 (Segment Slider)** because:
1. It fits the TTS model naturally
2. Minimal changes to playback architecture
3. Provides immediate value
4. Can be enhanced later

### Phase 1 Implementation Tasks

- [ ] Replace `LinearProgressIndicator` with `Slider` in portrait controls
- [ ] Replace `LinearProgressIndicator` with `Slider` in landscape bottom bar
- [ ] Add segment preview while dragging
- [ ] Add haptic ticks at segment boundaries
- [ ] Add heavy haptic at chapter boundaries (segment 0 and last)
- [ ] Show segment number and/or title while dragging

### UI Mockup

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│   Segment 5 of 23                                          │
│   ●───────────●──────────────────────────────────────○     │
│   1          5                                      23     │
│                                                            │
│   [Preview: "The old man walked slowly down the..."]       │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## Future Enhancements

### Phase 3: Chapter Overview Bar

Add a chapter-level seek bar above the segment bar:

```
Chapter 3 of 12
●────────●─────────────────────────────○
1        3                            12
```

### Phase 4: Waveform Visualization

Show a waveform or duration bar for cached segments:
- Grey: Not yet synthesized
- Blue: Cached and ready
- Orange: Currently playing

---

## Questions to Resolve

1. **Show segment preview text while dragging?**
   - Could show first few words of the target segment

2. **Snap to segments or smooth dragging?**
   - Recommend snap (divisions on Slider) for clarity

3. **Update existing landscape and portrait progress bars?**
   - Yes, both should become draggable

4. **Handle very long chapters (100+ segments)?**
   - May need to show every 5th or 10th segment as a tick
