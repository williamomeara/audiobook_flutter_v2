# Segment Readiness UI

## Overview

This feature provides visual feedback to users about which segments of text are ready for playback. Segments that have not yet been synthesized appear slightly greyed out, while synthesized segments appear with full clarity.

## User Experience

### Visual Design

```
┌─────────────────────────────────────────────────────────────┐
│                      Chapter 1                               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  "It is a truth universally acknowledged, that a single    │  ← Full opacity (synthesized)
│  man in possession of a good fortune, must be in want of   │  ← Full opacity (synthesized)
│  a wife."                                                  │  ← Full opacity (synthesized)
│                                                             │
│  "However little known the feelings or views of such a     │  ← 60% opacity (in progress)
│  man may be on his first entering a neighbourhood, this    │  ← 40% opacity (queued)
│  truth is so well fixed in the minds of the surrounding    │  ← 40% opacity (queued)
│  families, that he is considered as the rightful property  │  ← 40% opacity (queued)
│  of some one or other of their daughters."                 │  ← 40% opacity (queued)
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Opacity Levels

| State | Opacity | Description |
|-------|---------|-------------|
| **Synthesized (Ready)** | 100% | Segment cached and ready for playback |
| **Synthesizing (In Progress)** | 60% | Currently being synthesized |
| **Queued** | 40% | In prefetch queue, not yet started |
| **Not Queued** | 30% | Beyond prefetch window |

### Visual Transition

When a segment finishes synthesis, it smoothly animates from greyed to full opacity:

```dart
AnimatedOpacity(
  opacity: segment.isReady ? 1.0 : segment.opacity,
  duration: Duration(milliseconds: 300),
  curve: Curves.easeInOut,
  child: Text(segment.text),
)
```

---

## Architecture

### Segment Readiness State

```dart
enum SegmentState {
  notQueued,    // Beyond prefetch window
  queued,       // In prefetch queue
  synthesizing, // Currently being synthesized
  ready,        // Cached and ready to play
  error,        // Synthesis failed
}

class SegmentReadiness {
  final int segmentIndex;
  final SegmentState state;
  final double? progress; // 0.0-1.0 for synthesizing state
  
  double get opacity {
    switch (state) {
      case SegmentState.ready:
        return 1.0;
      case SegmentState.synthesizing:
        return 0.6 + (progress ?? 0.0) * 0.4; // 0.6-1.0
      case SegmentState.queued:
        return 0.4;
      case SegmentState.notQueued:
        return 0.3;
      case SegmentState.error:
        return 1.0; // Full opacity with error indicator
    }
  }
}
```

### State Management

```dart
// lib/app/segment_readiness_provider.dart

final segmentReadinessProvider = StateNotifierProvider.family<
    SegmentReadinessNotifier, 
    Map<int, SegmentReadiness>, 
    String // bookId
>((ref, bookId) => SegmentReadinessNotifier(bookId));

class SegmentReadinessNotifier extends StateNotifier<Map<int, SegmentReadiness>> {
  SegmentReadinessNotifier(this.bookId) : super({});
  
  final String bookId;
  
  /// Called when synthesis starts for a segment
  void onSynthesisStarted(int segmentIndex) {
    state = {
      ...state,
      segmentIndex: SegmentReadiness(
        segmentIndex: segmentIndex,
        state: SegmentState.synthesizing,
        progress: 0.0,
      ),
    };
  }
  
  /// Called with synthesis progress updates
  void onSynthesisProgress(int segmentIndex, double progress) {
    if (state[segmentIndex]?.state != SegmentState.synthesizing) return;
    
    state = {
      ...state,
      segmentIndex: SegmentReadiness(
        segmentIndex: segmentIndex,
        state: SegmentState.synthesizing,
        progress: progress,
      ),
    };
  }
  
  /// Called when synthesis completes
  void onSynthesisComplete(int segmentIndex) {
    state = {
      ...state,
      segmentIndex: SegmentReadiness(
        segmentIndex: segmentIndex,
        state: SegmentState.ready,
      ),
    };
  }
  
  /// Called when segment is added to prefetch queue
  void onSegmentQueued(int segmentIndex) {
    if (state[segmentIndex]?.state == SegmentState.ready) return;
    
    state = {
      ...state,
      segmentIndex: SegmentReadiness(
        segmentIndex: segmentIndex,
        state: SegmentState.queued,
      ),
    };
  }
  
  /// Batch update for initial state
  void setInitialState(List<int> queuedSegments, List<int> readySegments) {
    final newState = <int, SegmentReadiness>{};
    
    for (final index in readySegments) {
      newState[index] = SegmentReadiness(
        segmentIndex: index,
        state: SegmentState.ready,
      );
    }
    
    for (final index in queuedSegments) {
      if (!newState.containsKey(index)) {
        newState[index] = SegmentReadiness(
          segmentIndex: index,
          state: SegmentState.queued,
        );
      }
    }
    
    state = newState;
  }
}
```

---

## UI Implementation

### Playback Screen Text Widget

```dart
// lib/ui/widgets/readable_text.dart

class ReadableText extends ConsumerWidget {
  final String bookId;
  final List<TextSegment> segments;
  final int currentSegmentIndex;
  
  const ReadableText({
    required this.bookId,
    required this.segments,
    required this.currentSegmentIndex,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readinessMap = ref.watch(segmentReadinessProvider(bookId));
    
    return SingleChildScrollView(
      child: RichText(
        text: TextSpan(
          children: segments.asMap().entries.map((entry) {
            final index = entry.key;
            final segment = entry.value;
            final readiness = readinessMap[index];
            
            return TextSpan(
              text: segment.text,
              style: _getStyle(context, index, readiness),
            );
          }).toList(),
        ),
      ),
    );
  }
  
  TextStyle _getStyle(
    BuildContext context, 
    int segmentIndex, 
    SegmentReadiness? readiness,
  ) {
    final baseStyle = Theme.of(context).textTheme.bodyLarge!;
    final opacity = readiness?.opacity ?? 0.3;
    
    // Highlight current segment
    if (segmentIndex == currentSegmentIndex) {
      return baseStyle.copyWith(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        color: baseStyle.color?.withOpacity(opacity),
      );
    }
    
    return baseStyle.copyWith(
      color: baseStyle.color?.withOpacity(opacity),
    );
  }
}
```

### Animated Version for Smooth Transitions

```dart
// lib/ui/widgets/animated_readable_text.dart

class AnimatedReadableText extends ConsumerStatefulWidget {
  final String bookId;
  final List<TextSegment> segments;
  final int currentSegmentIndex;
  
  const AnimatedReadableText({
    required this.bookId,
    required this.segments,
    required this.currentSegmentIndex,
  });
  
  @override
  ConsumerState<AnimatedReadableText> createState() => _AnimatedReadableTextState();
}

class _AnimatedReadableTextState extends ConsumerState<AnimatedReadableText> {
  Map<int, double> _animatedOpacities = {};
  
  @override
  Widget build(BuildContext context) {
    final readinessMap = ref.watch(segmentReadinessProvider(widget.bookId));
    
    // Animate opacity changes
    ref.listen(segmentReadinessProvider(widget.bookId), (prev, next) {
      _handleOpacityChanges(prev ?? {}, next);
    });
    
    return ListView.builder(
      itemCount: widget.segments.length,
      itemBuilder: (context, index) {
        final segment = widget.segments[index];
        final readiness = readinessMap[index];
        final targetOpacity = readiness?.opacity ?? 0.3;
        
        return TweenAnimationBuilder<double>(
          tween: Tween(
            begin: _animatedOpacities[index] ?? 0.3,
            end: targetOpacity,
          ),
          duration: Duration(milliseconds: 300),
          builder: (context, opacity, child) {
            _animatedOpacities[index] = opacity;
            
            return Opacity(
              opacity: opacity,
              child: _buildSegment(context, segment, index),
            );
          },
        );
      },
    );
  }
  
  Widget _buildSegment(BuildContext context, TextSegment segment, int index) {
    final isCurrentSegment = index == widget.currentSegmentIndex;
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isCurrentSegment 
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
          : null,
      child: Text(
        segment.text,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}
```

---

## Integration Points

### With Buffer Scheduler

```dart
// packages/playback/lib/src/buffer_scheduler.dart

class BufferScheduler {
  final SegmentReadinessNotifier? readinessNotifier;
  
  Future<void> _synthesizeSegment(int index) async {
    // Notify UI that synthesis is starting
    readinessNotifier?.onSynthesisStarted(index);
    
    try {
      // Actual synthesis (with progress callback if supported)
      await _ttsService.synthesize(
        segment: _segments[index],
        onProgress: (progress) {
          readinessNotifier?.onSynthesisProgress(index, progress);
        },
      );
      
      // Notify UI that synthesis completed
      readinessNotifier?.onSynthesisComplete(index);
      
    } catch (e) {
      readinessNotifier?.onSynthesisError(index, e);
      rethrow;
    }
  }
  
  void _updatePrefetchQueue(List<int> queuedIndices) {
    for (final index in queuedIndices) {
      readinessNotifier?.onSegmentQueued(index);
    }
  }
}
```

### With Audio Cache

```dart
// lib/app/segment_readiness_initializer.dart

class SegmentReadinessInitializer {
  final AudioCache _cache;
  final SegmentReadinessNotifier _notifier;
  
  /// Initialize readiness state from cache
  Future<void> initializeFromCache({
    required String bookId,
    required String voiceId,
    required int segmentCount,
  }) async {
    final readySegments = <int>[];
    
    for (var i = 0; i < segmentCount; i++) {
      final key = '${voiceId}_${bookId}_$i';
      if (await _cache.exists(key)) {
        readySegments.add(i);
      }
    }
    
    _notifier.setInitialState([], readySegments);
  }
}
```

---

## Accessibility

### Screen Reader Support

```dart
Widget _buildAccessibleSegment(TextSegment segment, SegmentReadiness? readiness) {
  final stateDescription = switch (readiness?.state) {
    SegmentState.ready => 'Ready for playback',
    SegmentState.synthesizing => 'Preparing audio',
    SegmentState.queued => 'Queued for preparation',
    SegmentState.notQueued => 'Not yet queued',
    SegmentState.error => 'Audio preparation failed',
    null => 'Not yet queued',
  };
  
  return Semantics(
    label: '${segment.text}. $stateDescription',
    child: _buildVisualSegment(segment, readiness),
  );
}
```

### Color Contrast

Ensure greyed text still meets WCAG AA contrast requirements:

```dart
class AccessibleOpacity {
  static double getAccessibleOpacity(SegmentState state, bool isDarkMode) {
    // Ensure minimum 4.5:1 contrast ratio for AA compliance
    final minOpacity = isDarkMode ? 0.5 : 0.4;
    
    switch (state) {
      case SegmentState.ready:
        return 1.0;
      case SegmentState.synthesizing:
        return math.max(0.7, minOpacity);
      case SegmentState.queued:
        return math.max(0.5, minOpacity);
      case SegmentState.notQueued:
        return minOpacity;
      case SegmentState.error:
        return 1.0;
    }
  }
}
```

---

## Future Enhancements

### Phase 1 (Current)
- [x] Basic opacity states (ready vs not ready)
- [x] Integration with buffer scheduler
- [x] Initial cache-based state

### Phase 2 (Future)
- [ ] Progress indicators within segments (subtle underline)
- [ ] Tap-to-prioritize synthesis for specific segment
- [ ] Visual connection between playing audio and highlighted text

### Phase 3 (Future)
- [ ] Chapter-level readiness indicator in table of contents
- [ ] Estimated time to segment readiness
- [ ] Batch synthesis progress overlay

---

## Success Metrics

| Metric | Target |
|--------|--------|
| User understanding of readiness | > 80% understand what opacity means (A/B test) |
| Perceived playback responsiveness | > 4/5 rating |
| Accessibility compliance | WCAG AA for all opacity levels |
| Animation smoothness | 60 fps during opacity transitions |

---

**Document Version**: 1.0  
**Last Updated**: 2026-01-07  
**Status**: Ready for Implementation
