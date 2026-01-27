import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:core_domain/core_domain.dart';
import 'package:playback/playback.dart';

import '../../../../theme/app_colors.dart';

/// Model representing the visual state of a segment for text display.
class SegmentDisplayState {
  final bool isActive;
  final bool isPast;
  final bool isReady;
  final bool isSynthesizing;
  
  const SegmentDisplayState({
    required this.isActive,
    required this.isPast,
    required this.isReady,
    required this.isSynthesizing,
  });
}

/// A widget span for an active segment, enabling precise scrolling.
/// 
/// Active segments use a GestureDetector with a GlobalKey for 
/// Scrollable.ensureVisible to work.
class ActiveSegmentSpan extends StatelessWidget {
  final String text;
  final TextStyle style;
  final GlobalKey segmentKey;
  final VoidCallback onTap;
  
  const ActiveSegmentSpan({
    super.key,
    required this.text,
    required this.style,
    required this.segmentKey,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: segmentKey,
      onTap: onTap,
      child: Text('$text ', style: style),
    );
  }
}

/// Build text styling for a segment based on its state.
TextStyle buildSegmentTextStyle({
  required AppThemeColors colors,
  required SegmentDisplayState state,
}) {
  Color textColor;
  if (state.isActive) {
    textColor = colors.textHighlight; // amber-400 for current
  } else if (state.isPast) {
    textColor = colors.textPast; // slate-500 for past
  } else if (state.isReady) {
    textColor = colors.textSecondary; // slate-300 for ready future
  } else {
    textColor = colors.textTertiary.withValues(alpha: 0.5); // slate-700 for not downloaded
  }
  
  return TextStyle(
    fontSize: 17,
    height: 1.7,
    color: textColor,
    fontWeight: state.isActive ? FontWeight.w500 : FontWeight.normal,
  );
}

/// Build a synthesizing indicator span.
InlineSpan buildSynthesizingIndicator(AppThemeColors colors) {
  return TextSpan(
    text: '(synthesizing...) ',
    style: TextStyle(
      fontSize: 11,
      color: colors.textTertiary.withValues(alpha: 0.7),
      fontStyle: FontStyle.italic,
    ),
  );
}

/// Build spans for all segments in the queue.
/// 
/// Returns a list of InlineSpans to be used in a RichText widget.
/// The [activeSegmentKey] is set when building the active segment.
List<InlineSpan> buildSegmentSpans({
  required List<AudioTrack> queue,
  required int currentIndex,
  required Map<int, SegmentReadiness> segmentReadiness,
  required AppThemeColors colors,
  required GlobalKey activeSegmentKey,
  required void Function(int) onSegmentTap,
}) {
  final List<InlineSpan> spans = [];
  
  for (int index = 0; index < queue.length; index++) {
    final item = queue[index];
    final isActive = index == currentIndex;
    final isPast = index < currentIndex;
    
    // Get segment readiness (1.0 = ready, lower = not ready)
    final readiness = segmentReadiness[index];
    final isReady = readiness?.opacity == 1.0;
    final isSynthesizing = readiness?.state == SegmentState.synthesizing && !isPast && !isActive;
    
    final state = SegmentDisplayState(
      isActive: isActive,
      isPast: isPast,
      isReady: isReady,
      isSynthesizing: isSynthesizing,
    );
    
    final textStyle = buildSegmentTextStyle(colors: colors, state: state);
    
    // Use WidgetSpan for active segment to enable precise scrolling
    if (isActive) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: ActiveSegmentSpan(
          text: item.text,
          style: textStyle,
          segmentKey: activeSegmentKey,
          onTap: () => onSegmentTap(index),
        ),
      ));
    } else {
      // Use regular TextSpan for non-active segments
      spans.add(TextSpan(
        text: '${item.text} ',
        style: textStyle,
        recognizer: TapGestureRecognizer()..onTap = () => onSegmentTap(index),
      ));
    }
    
    // Add synthesizing indicator ONLY for segments currently being synthesized
    if (isSynthesizing) {
      spans.add(buildSynthesizingIndicator(colors));
    }
  }
  
  return spans;
}
