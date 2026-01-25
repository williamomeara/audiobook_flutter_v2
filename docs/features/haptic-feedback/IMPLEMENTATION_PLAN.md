# Haptic Feedback Implementation Plan

## Overview

This document outlines our strategy for adding haptic feedback to the audiobook app, based on modern UX research and platform guidelines for audio applications.

---

## Research Summary

### When to Use Haptics in Audio Apps ✅

| Use Case | Haptic Type | Rationale |
|----------|-------------|-----------|
| **Play/Pause toggle** | Light impact | Confirms state change without interrupting audio |
| **Chapter navigation** | Medium impact | Signals significant position change |
| **Scrubbing/seeking** | Transient "ticks" | Helps users feel time intervals without looking |
| **Volume at limit** | Heavy impact | Signals hard boundary (min/max) |
| **Speed adjustment** | Light selection | Confirms speed step change |
| **Download complete** | Success pattern | Important notification |
| **Error states** | Error pattern | Alert without audio interruption |
| **Long-press actions** | Medium impact | Confirms gesture recognition |

### When NOT to Use Haptics ❌ (Red Flags)

| Anti-Pattern | Why It's Bad |
|--------------|--------------|
| **Every button tap** | Creates "sensory noise," dilutes important feedback |
| **Back navigation** | Minor navigation doesn't need confirmation |
| **Continuous beat sync** | Battery drain, numbing after 2 minutes |
| **Menu item selection** | Too frequent, causes "haptic fatigue" |
| **Overlapping with audio** | Motor buzz can interfere with listening |
| **Queue/playlist changes** | Visual confirmation is sufficient |

### The Golden Rules (2024-2025)

1. **"Haptics should be felt, not heard"** - If the haptic creates audible buzz, reduce intensity
2. **Limit to high-value interactions** - Use sparingly for maximum impact
3. **Provide user control** - Always allow disabling haptics
4. **Test on real devices** - Emulators don't vibrate, haptic motors vary
5. **Pair with visual cues** - Never rely solely on haptics

---

## Implementation Plan for Audiobook App

### Phase 1: Core Playback Controls

**Priority: HIGH**

| Control | Haptic | Flutter Method |
|---------|--------|----------------|
| Play button | Light impact | `HapticFeedback.lightImpact()` |
| Pause button | Medium impact | `HapticFeedback.mediumImpact()` |
| Next chapter | Medium impact | `HapticFeedback.mediumImpact()` |
| Previous chapter | Medium impact | `HapticFeedback.mediumImpact()` |
| Speed increase/decrease | Selection click | `HapticFeedback.selectionClick()` |

### Phase 2: Seeking & Boundaries

**Priority: MEDIUM**

| Control | Haptic | Notes |
|---------|--------|-------|
| Seek bar drag | Ticks at intervals | Every 10% or minute marker |
| Reach start of book | Heavy impact | Hard boundary |
| Reach end of book | Heavy impact | Hard boundary |
| Volume at max | Heavy impact | Limit warning |
| Volume at min | Heavy impact | Limit warning |

### Phase 3: Notifications & States

**Priority: LOW**

| Event | Haptic | Notes |
|-------|--------|-------|
| Download complete | Success pattern | Only when app in foreground |
| Download failed | Error pattern | Alert user |
| Chapter marked complete | Light impact | Subtle confirmation |
| Sleep timer expired | Medium impact | Before audio stops |

---

## Technical Implementation

### Flutter Approach

```dart
import 'package:flutter/services.dart';

// Centralized haptic helper
class AppHaptics {
  static bool _enabled = true;
  
  static void setEnabled(bool enabled) => _enabled = enabled;
  
  static void light() {
    if (_enabled) HapticFeedback.lightImpact();
  }
  
  static void medium() {
    if (_enabled) HapticFeedback.mediumImpact();
  }
  
  static void heavy() {
    if (_enabled) HapticFeedback.heavyImpact();
  }
  
  static void selection() {
    if (_enabled) HapticFeedback.selectionClick();
  }
}
```

### Usage Pattern

```dart
// In playback_screen.dart
void _togglePlayPause() {
  final isPlaying = ref.read(playbackStateProvider).isPlaying;
  
  // Haptic feedback based on new state
  if (isPlaying) {
    AppHaptics.medium(); // Stopping feels "heavier"
  } else {
    AppHaptics.light(); // Starting feels "lighter"
  }
  
  ref.read(playbackControllerProvider.notifier).togglePlayPause();
}
```

### Android Permissions

Ensure `android/app/src/main/AndroidManifest.xml` has:

```xml
<uses-permission android:name="android.permission.VIBRATE" />
```

### Settings Integration

Add to settings screen:

```dart
// New setting
final hapticFeedbackEnabledProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsProvider);
  return settings.hapticFeedbackEnabled;
});

// Settings UI
SwitchListTile(
  title: Text('Haptic Feedback'),
  subtitle: Text('Vibration for playback controls'),
  value: settings.hapticFeedbackEnabled,
  onChanged: (value) => ref.read(settingsProvider.notifier).setHapticFeedback(value),
),
```

---

## What We Will NOT Implement

To avoid "haptic fatigue":

- ❌ Navigation button taps (back, menu)
- ❌ List item selection
- ❌ Tab switching
- ❌ Text segment highlighting
- ❌ Queue/library changes
- ❌ Beat-synced vibration (too battery-intensive)

---

## Testing Checklist

- [ ] Test on physical Android device
- [ ] Test on physical iOS device (if available)
- [ ] Verify haptics respect system silent/vibrate modes
- [ ] Verify setting toggle works
- [ ] Test haptic intensity doesn't create audible buzz
- [ ] Test during active playback (no interference)
- [ ] Verify no haptics on unsupported platforms (web)

---

## Implementation Tasks

### Phase 1 Tasks ✅ COMPLETE

- [x] Create `AppHaptics` utility class (`lib/utils/app_haptics.dart`)
- [x] Add `hapticFeedbackEnabled` setting (`lib/app/settings_controller.dart`)
- [x] Add toggle to settings screen (`lib/ui/screens/settings_screen.dart`)
- [x] Implement for Play/Pause button
- [x] Implement for Next/Previous chapter (with boundary feedback)
- [x] Implement for Speed controls (with limit feedback)
- [x] Add VIBRATE permission to Android manifest

### Phase 2 Tasks (Future)

- [ ] Implement seek bar tick haptics
- [ ] Add boundary haptics (volume, position limits)

### Phase 3 Tasks (Future)

- [ ] Download completion haptics
- [ ] Sleep timer expiry haptic

---

## References

- [Apple Human Interface Guidelines: Playing Haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- [Google Design: Sound & Touch](https://design.google/library/ux-sound-haptic-material-design)
- [Flutter HapticFeedback Documentation](https://api.flutter.dev/flutter/services/HapticFeedback-class.html)
- [haptic_feedback package](https://pub.dev/packages/haptic_feedback) (for advanced patterns)
