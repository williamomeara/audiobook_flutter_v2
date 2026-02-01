# Voice Selection Button with Warmup Indicator - Implementation Plan

## Overview

Add a voice selection button to the playback UI that:
1. **Shows the currently selected voice** with a compact, tasteful design
2. **Indicates warmup/loading state** so users understand what the app is doing
3. **Opens a voice picker** for quick voice changes during playback
4. **Maintains visual elegance** appropriate for a premium audiobook experience

---

## Design Research & Inspiration

### Competitor Patterns

#### Speechify
- Uses voice avatars with a small circular icon
- Premium voices indicated with subtle badge
- Voice switching accessible via tap, opens bottom sheet
- Loading states use subtle shimmer/pulse

#### Audible
- Narrator shown in metadata, not changeable during playback
- Speed controls prominent, voice is fixed
- Clean, minimal controls

#### Apple Podcasts / Books
- System voice toggle (on/off)
- Speed control uses segmented control style
- Loading uses system spinner with "Loading..." text

#### Other TTS Apps
- ElevenLabs: Voice dropdown with waveform animation during generation
- Natural Reader: Voice button with engine icon, loading ring around button
- Murf: Voice chip with avatar, pulsing during processing

### Best Practices for Loading States

1. **Communicate what's happening**: "Preparing voice..." not just a spinner
2. **Show progress when possible**: Determinate vs indeterminate
3. **Prevent interaction with clear disabled state**: Don't let users tap while loading
4. **Maintain layout stability**: Don't shift elements when state changes
5. **Use motion purposefully**: Subtle pulse/glow, not distracting

---

## Proposed Design

### Location Options

| Location | Pros | Cons |
|----------|------|------|
| **Header row (top bar)** | Always visible, quick access | Limited space, competes with title |
| **Near playback controls (bottom)** | Near other controls | Bottom area already crowded |
| **Above segment display (new row)** | Clear visibility, expandable | New UI element, takes vertical space |
| **Speed control area** | Groups settings together | May confuse with speed |

**Recommendation**: **Header area** (right side) or **Near speed control** in a compact form.

### Widget States

#### 1. Ready State (Normal)
```
┌──────────────────────────────────────────┐
│ 🎤 Emma F1                           ▼  │
└──────────────────────────────────────────┘
```
- Voice icon (mic/speaker) + Voice name
- Subtle dropdown indicator
- Tappable to open picker

#### 2. Warming Up State
```
┌──────────────────────────────────────────┐
│ ◐ Preparing Emma...                     │
└──────────────────────────────────────────┘
```
- Animated loading indicator (rotating or pulsing)
- "Preparing {voice}..." text
- Button disabled (visually muted)
- Optional: ring animation around button

#### 3. Error State
```
┌──────────────────────────────────────────┐
│ ⚠️ Voice unavailable                 ▼  │
└──────────────────────────────────────────┘
```
- Warning icon
- Error text
- Still tappable to select different voice

#### 4. No Voice Selected
```
┌──────────────────────────────────────────┐
│ 🎤 Select voice                      ▼  │
└──────────────────────────────────────────┘
```
- Prompt to select
- Tappable to open picker

### Visual Design

#### Pill/Chip Style (Recommended)
- Rounded pill shape with subtle border or background
- Compact but tappable (min 44pt height for touch target)
- Consistent with Material Design 3 chips

#### Color States
| State | Background | Text | Icon |
|-------|------------|------|------|
| Ready | `primary.withOpacity(0.1)` | `text` | `primary` |
| Warming | `primary.withOpacity(0.05)` | `textSecondary` | Animated, `primary` |
| Error | `danger.withOpacity(0.1)` | `danger` | `danger` |
| Disabled | `border` | `textTertiary` | `textTertiary` |

#### Animation
- **Warmup**: Circular progress ring around icon OR pulsing glow
- **Transition**: Fade between states (150-200ms)
- **Appear**: Fade in on first load (don't animate on every rebuild)

---

## Technical Implementation

### New State: Engine Warmup Status

Add warmup tracking to PlaybackViewState:

```dart
// In playback_view_state.dart
enum EngineWarmupStatus {
  notStarted,
  warming,
  ready,
  failed,
}

// Add to ActiveState
class ActiveState extends PlaybackViewState {
  // ... existing fields
  final EngineWarmupStatus warmupStatus;
  final String? warmupError;
}
```

### Update PlaybackViewNotifier

```dart
// In playback_view_notifier.dart
void _handleWarmupStarted(String voiceId) {
  final current = state;
  if (current is ActiveState) {
    state = current.copyWith(
      warmupStatus: EngineWarmupStatus.warming,
    );
  }
}

void _handleWarmupComplete(bool success, String? error) {
  final current = state;
  if (current is ActiveState) {
    state = current.copyWith(
      warmupStatus: success ? EngineWarmupStatus.ready : EngineWarmupStatus.failed,
      warmupError: error,
    );
  }
}
```

### New Widget: VoiceSelectionButton

```dart
// lib/ui/screens/playback/widgets/voice_selection_button.dart

class VoiceSelectionButton extends ConsumerWidget {
  final VoidCallback onTap;
  final EngineWarmupStatus warmupStatus;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final voiceId = settings.selectedVoice;
    final colors = context.appColors;
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: _decoration(warmupStatus, colors),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: warmupStatus == EngineWarmupStatus.warming ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildIcon(warmupStatus, colors),
                const SizedBox(width: 8),
                _buildText(voiceId, warmupStatus, colors),
                if (warmupStatus != EngineWarmupStatus.warming) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 18, color: colors.textSecondary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildIcon(EngineWarmupStatus status, AppThemeColors colors) {
    switch (status) {
      case EngineWarmupStatus.warming:
        return SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(colors.primary),
          ),
        );
      case EngineWarmupStatus.failed:
        return Icon(Icons.warning_amber_rounded, size: 18, color: colors.danger);
      default:
        return Icon(Icons.mic, size: 18, color: colors.primary);
    }
  }
  
  String _buildText(String voiceId, EngineWarmupStatus status, ...) {
    if (status == EngineWarmupStatus.warming) {
      return 'Preparing...';
    }
    if (voiceId == VoiceIds.none) {
      return 'Select voice';
    }
    return VoiceDisplayNames.get(voiceId);  // e.g., "Emma F1"
  }
}
```

### Integration into Playback Header

Modify `PlaybackHeader` to include the voice button:

```dart
// In playback_header.dart

class PlaybackHeader extends StatelessWidget {
  // ... existing props
  final EngineWarmupStatus warmupStatus;
  final VoidCallback onVoiceTap;
  
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Back button
        IconButton(...),
        
        // Book/Chapter title (Expanded)
        Expanded(child: _buildTitleColumn()),
        
        // NEW: Voice selection button
        VoiceSelectionButton(
          warmupStatus: warmupStatus,
          onTap: onVoiceTap,
        ),
        
        // View toggle button
        IconButton(...),
      ],
    );
  }
}
```

### Voice Picker Bottom Sheet

Reuse existing voice picker logic from settings, adapted for playback:

```dart
void _showVoicePicker(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => VoicePickerSheet(
      onVoiceSelected: (voiceId) {
        Navigator.pop(context);
        // Change voice and trigger warmup
        ref.read(settingsProvider.notifier).setSelectedVoice(voiceId);
        ref.read(playbackViewProvider.notifier).handleEvent(
          VoiceChanged(voiceId: voiceId),
        );
      },
    ),
  );
}
```

---

## File Changes Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `lib/app/playback/state/playback_view_state.dart` | Modify | Add `EngineWarmupStatus` enum and fields |
| `lib/app/playback/playback_view_notifier.dart` | Modify | Track warmup status, emit updates |
| `lib/ui/screens/playback/widgets/voice_selection_button.dart` | **New** | Voice button widget |
| `lib/ui/screens/playback/widgets/playback_header.dart` | Modify | Add voice button |
| `lib/ui/screens/playback/layouts/portrait_layout.dart` | Modify | Pass warmup status to header |
| `lib/ui/screens/playback/layouts/landscape_layout.dart` | Modify | Pass warmup status (maybe different position) |
| `lib/ui/screens/playback_screen.dart` | Modify | Add voice picker callback, wire state |

---

## Implementation Steps

### Phase 1: State Infrastructure
1. [ ] Add `EngineWarmupStatus` enum to playback state
2. [ ] Add warmup tracking fields to `ActiveState`
3. [ ] Update `PlaybackViewNotifier` to track warmup start/complete
4. [ ] Wire warmup status through existing warmUp call

### Phase 2: Voice Button Widget
1. [ ] Create `VoiceSelectionButton` widget
2. [ ] Implement all visual states (ready, warming, error, no voice)
3. [ ] Add warmup animation (CircularProgressIndicator or custom)
4. [ ] Create `VoiceDisplayNames` utility for friendly names

### Phase 3: Playback Header Integration
1. [ ] Modify `PlaybackHeader` to accept warmup status
2. [ ] Add voice button to header row
3. [ ] Style for both portrait and landscape layouts
4. [ ] Test layout at different screen sizes

### Phase 4: Voice Picker Integration
1. [ ] Create or reuse `VoicePickerSheet` for playback context
2. [ ] Wire up voice change event
3. [ ] Handle warmup restart when voice changes

### Phase 5: Polish & Testing
1. [ ] Animation refinement
2. [ ] Accessibility (screen reader, labels)
3. [ ] Test with real warmup timing (2-45 seconds)
4. [ ] Edge cases: voice unavailable mid-playback, download needed

---

## Accessibility Considerations

- **Semantics label**: "Voice: Emma F1, tap to change" or "Voice loading, please wait"
- **Live region**: Announce when warmup completes ("Voice ready")
- **Disabled state**: `excludeSemantics: true` during loading to avoid confusing screen readers
- **Touch target**: Minimum 44x44 logical pixels

---

## Edge Cases

1. **Voice download not complete**: Show "Download required" state, tap navigates to downloads
2. **Voice becomes unavailable during playback**: Show error state, prompt to select new voice
3. **Network required for voice**: Handle offline gracefully
4. **Multiple quick voice changes**: Debounce or cancel previous warmup

---

## Open Questions

1. Should landscape mode have the voice button in a different location?
2. Do we want a more elaborate "first time" experience explaining voice options?
3. Should warmup show a percentage progress (if trackable) or just indeterminate?
4. Should voice change during playback immediately restart synthesis or queue after current segment?

---

## Mockups (ASCII)

### Portrait - Header with Voice Button
```
┌─────────────────────────────────────────────────────┐
│ ← │     Book Title          │ 🎤 Emma ▼ │ 📖/🖼    │
│   │     Chapter 1           │            │         │
└─────────────────────────────────────────────────────┘
│                                                     │
│                   [Text Display]                    │
│                   or Cover View                     │
│                                                     │
├─────────────────────────────────────────────────────┤
│                 [Playback Controls]                 │
└─────────────────────────────────────────────────────┘
```

### Voice Button - Warmup State
```
┌────────────────────────────────────┐
│ ◐  Preparing Emma...             │
│ (disabled, muted colors)          │
└────────────────────────────────────┘
```

### Voice Picker Bottom Sheet
```
┌─────────────────────────────────────────────────────┐
│ ─────                                               │
│                                                     │
│            Select Voice                             │
│                                                     │
│ ─────────────────────────────────────────────────── │
│   Piper Voices                                      │
│   ○ Emma F1                          ⚡ Fast        │
│   ○ Ryan M1                          ⚡ Fast        │
│ ─────────────────────────────────────────────────── │
│   Supertonic Voices                                 │
│   ● Ava F1                           ✓ Selected    │
│   ○ Alex M1                                         │
│ ─────────────────────────────────────────────────── │
│   Kokoro Voices                                     │
│   ○ Heart                            🎭 Expressive │
│ ─────────────────────────────────────────────────── │
│            [Download More Voices]                   │
└─────────────────────────────────────────────────────┘
```

---

## Estimated Effort

| Phase | Effort | Notes |
|-------|--------|-------|
| Phase 1: State | 1-2 hours | Straightforward state additions |
| Phase 2: Widget | 2-3 hours | Custom widget with animations |
| Phase 3: Integration | 1-2 hours | Layout adjustments |
| Phase 4: Picker | 1-2 hours | Reusing existing logic |
| Phase 5: Polish | 2-3 hours | Accessibility, edge cases |
| **Total** | **8-12 hours** | |

---

## Success Criteria

1. ✅ User can see which voice is selected at a glance
2. ✅ User understands when the app is warming up the engine
3. ✅ Voice changes are quick (picker accessible from playback screen)
4. ✅ UI remains elegant and uncluttered
5. ✅ Warmup status is accurate and updates in real-time
6. ✅ Works well in both portrait and landscape orientations
