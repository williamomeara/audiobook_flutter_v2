import 'package:flutter/material.dart';
import 'package:core_domain/core_domain.dart';
import 'package:playback/playback.dart';

import '../../../../theme/app_colors.dart';
import 'code_block_widget.dart';

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

/// A tappable segment span widget.
///
/// Uses GestureDetector instead of TapGestureRecognizer to avoid memory leaks.
/// For active segments, accepts a GlobalKey for Scrollable.ensureVisible.
class SegmentSpanWidget extends StatelessWidget {
  final String text;
  final TextStyle style;
  final VoidCallback onTap;
  final GlobalKey? segmentKey;

  const SegmentSpanWidget({
    super.key,
    required this.text,
    required this.style,
    required this.onTap,
    this.segmentKey,
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
/// Uses WidgetSpan with GestureDetector for all segments to avoid
/// TapGestureRecognizer memory leaks.
/// The [activeSegmentKey] is set on the active segment for scrolling.
/// 
/// For special segment types (code, figure), uses dedicated widgets.
List<InlineSpan> buildSegmentSpans({
  required List<AudioTrack> queue,
  required int currentIndex,
  required Map<int, SegmentReadiness> segmentReadiness,
  required AppThemeColors colors,
  required GlobalKey activeSegmentKey,
  required void Function(int) onSegmentTap,
  required bool isDarkMode,
  void Function(int)? onSkipSegment,
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
    
    // Handle special segment types
    if (item.segmentType == SegmentType.code) {
      spans.add(_buildCodeBlockSpan(
        item: item,
        index: index,
        isActive: isActive,
        isDarkMode: isDarkMode,
        onTap: () => onSegmentTap(index),
        onSkip: onSkipSegment != null ? () => onSkipSegment(index) : null,
        segmentKey: isActive ? activeSegmentKey : null,
      ));
      continue;
    }
    
    if (item.segmentType == SegmentType.figure) {
      spans.add(_buildFigureBlockSpan(
        item: item,
        index: index,
        isActive: isActive,
        isDarkMode: isDarkMode,
        onTap: () => onSegmentTap(index),
        segmentKey: isActive ? activeSegmentKey : null,
      ));
      continue;
    }

    final textStyle = buildSegmentTextStyle(colors: colors, state: state);

    // Use WidgetSpan for all segments to avoid TapGestureRecognizer memory leaks
    // Active segment gets the GlobalKey for precise scrolling
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: SegmentSpanWidget(
        text: item.text,
        style: textStyle,
        onTap: () => onSegmentTap(index),
        segmentKey: isActive ? activeSegmentKey : null,
      ),
    ));

    // Add synthesizing indicator ONLY for segments currently being synthesized
    if (isSynthesizing) {
      spans.add(buildSynthesizingIndicator(colors));
    }
  }

  return spans;
}

/// Build a code block span using CodeBlockWidget.
WidgetSpan _buildCodeBlockSpan({
  required AudioTrack item,
  required int index,
  required bool isActive,
  required bool isDarkMode,
  required VoidCallback onTap,
  VoidCallback? onSkip,
  GlobalKey? segmentKey,
}) {
  final language = item.metadata?['language'] as String? ?? 'plaintext';
  
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: SizedBox(
      key: segmentKey,
      width: double.infinity,
      child: CodeBlockWidget(
        text: item.text,
        language: language,
        isDarkMode: isDarkMode,
        isActive: isActive,
        onTap: onTap,
        onSkip: onSkip,
      ),
    ),
  );
}

/// Build a figure block span using FigureBlockWidget.
WidgetSpan _buildFigureBlockSpan({
  required AudioTrack item,
  required int index,
  required bool isActive,
  required bool isDarkMode,
  required VoidCallback onTap,
  GlobalKey? segmentKey,
}) {
  // Extract caption from [Figure: caption] marker
  final captionMatch = RegExp(r'\[Figure:\s*(.*?)\]', caseSensitive: false).firstMatch(item.text);
  final caption = captionMatch?.group(1)?.trim() ?? item.metadata?['caption'] as String? ?? '';
  
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: SizedBox(
      key: segmentKey,
      width: double.infinity,
      child: FigureBlockWidget(
        caption: caption,
        isDarkMode: isDarkMode,
        isActive: isActive,
        onTap: onTap,
      ),
    ),
  );
}
