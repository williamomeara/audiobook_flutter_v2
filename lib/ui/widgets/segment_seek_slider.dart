import 'package:flutter/material.dart';
import 'package:playback/playback.dart';
import '../../utils/app_haptics.dart';
import '../theme/app_colors.dart';

/// A draggable slider for seeking between segments.
/// 
/// Replaces the static LinearProgressIndicator with an interactive slider
/// that allows users to drag to different segments with haptic feedback.
/// 
/// Also shows synthesis status for each segment:
/// - Ready segments: filled with primary color
/// - Synthesizing segments: pulsing animation
/// - Queued/not-queued segments: dimmed background
class SegmentSeekSlider extends StatefulWidget {
  const SegmentSeekSlider({
    super.key,
    required this.currentIndex,
    required this.totalSegments,
    required this.onSeek,
    required this.colors,
    this.height = 4.0,
    this.showPreview = true,
    this.segmentPreviewBuilder,
    this.segmentReadiness,
  });

  /// Current segment index (0-based)
  final int currentIndex;
  
  /// Total number of segments
  final int totalSegments;
  
  /// Callback when user completes seeking
  final void Function(int segmentIndex) onSeek;
  
  /// Theme colors
  final AppThemeColors colors;
  
  /// Height of the slider track
  final double height;
  
  /// Whether to show segment preview while dragging
  final bool showPreview;
  
  /// Optional builder for segment preview text
  /// Returns a preview string for the given segment index
  final String Function(int segmentIndex)? segmentPreviewBuilder;

  /// Optional map of segment index to readiness state
  /// Used to show synthesis progress on the seek bar
  final Map<int, SegmentReadiness>? segmentReadiness;

  @override
  State<SegmentSeekSlider> createState() => _SegmentSeekSliderState();
}

class _SegmentSeekSliderState extends State<SegmentSeekSlider> with SingleTickerProviderStateMixin {
  // Preview segment index while dragging (-1 = not dragging)
  int _previewIndex = -1;
  
  // Last segment index where we triggered haptic
  int _lastHapticIndex = -1;

  // Animation controller for synthesizing pulse effect
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Guard against edge cases that would cause Slider assertion failures
    if (widget.totalSegments <= 1) {
      // With 0 or 1 segments, slider doesn't make sense
      return const SizedBox.shrink();
    }

    final isDragging = _previewIndex >= 0;
    // Clamp displayIndex to valid range
    final rawIndex = isDragging ? _previewIndex : widget.currentIndex;
    final displayIndex = rawIndex.clamp(0, widget.totalSegments - 1);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Segment preview tooltip while dragging
        if (widget.showPreview && isDragging)
          _buildPreviewTooltip(displayIndex),
        
        // The slider with synthesis status track
        SizedBox(
          height: 24 + widget.height, // Slider needs some vertical space
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: widget.height,
              trackShape: _SynthesisTrackShape(
                segmentReadiness: widget.segmentReadiness ?? {},
                totalSegments: widget.totalSegments,
                currentIndex: widget.currentIndex,
                primaryColor: widget.colors.primary,
                backgroundColor: widget.colors.controlBackground,
                synthesizingAnimation: _pulseAnimation,
              ),
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: isDragging ? 8 : 6,
                pressedElevation: 4,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: widget.colors.primary,
              inactiveTrackColor: widget.colors.controlBackground,
              thumbColor: widget.colors.primary,
              overlayColor: widget.colors.primary.withValues(alpha: 0.2),
            ),
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) => Slider(
                value: displayIndex.toDouble(),
                min: 0,
                max: (widget.totalSegments - 1).toDouble(),
                // Use divisions for snapping if reasonable number of segments
                divisions: widget.totalSegments > 1 && widget.totalSegments <= 100
                    ? widget.totalSegments - 1
                    : null,
                onChangeStart: (value) {
                  setState(() {
                    _previewIndex = value.round();
                    _lastHapticIndex = _previewIndex;
                  });
                },
                onChanged: (value) {
                  final newIndex = value.round();
                  if (newIndex != _previewIndex) {
                    setState(() {
                      _previewIndex = newIndex;
                    });
                    
                    // Haptic feedback at segment boundaries
                    if (newIndex != _lastHapticIndex) {
                      _lastHapticIndex = newIndex;
                      
                      // Heavy haptic at chapter boundaries (first/last segment)
                      if (newIndex == 0 || newIndex == widget.totalSegments - 1) {
                        AppHaptics.medium();
                      } else {
                        AppHaptics.selection();
                      }
                    }
                  }
                },
                onChangeEnd: (value) {
                  final targetIndex = value.round();
                  setState(() {
                    _previewIndex = -1;
                    _lastHapticIndex = -1;
                  });
                  
                  // Trigger seek callback
                  if (targetIndex != widget.currentIndex) {
                    widget.onSeek(targetIndex);
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewTooltip(int segmentIndex) {
    final previewText = widget.segmentPreviewBuilder?.call(segmentIndex);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: widget.colors.card,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Segment ${segmentIndex + 1} of ${widget.totalSegments}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: widget.colors.text,
            ),
          ),
          if (previewText != null && previewText.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              previewText,
              style: TextStyle(
                fontSize: 11,
                color: widget.colors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Custom track shape that shows synthesis status for each segment.
/// 
/// - Ready segments (past current): filled with primary color
/// - Synthesizing segments: pulsing glow effect
/// - Queued/not-queued segments: dimmed background
class _SynthesisTrackShape extends SliderTrackShape {
  _SynthesisTrackShape({
    required this.segmentReadiness,
    required this.totalSegments,
    required this.currentIndex,
    required this.primaryColor,
    required this.backgroundColor,
    required this.synthesizingAnimation,
  });

  final Map<int, SegmentReadiness> segmentReadiness;
  final int totalSegments;
  final int currentIndex;
  final Color primaryColor;
  final Color backgroundColor;
  final Animation<double> synthesizingAnimation;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    if (totalSegments <= 0) return;

    final canvas = context.canvas;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );

    final trackHeight = trackRect.height;
    final segmentWidth = trackRect.width / totalSegments;
    final cornerRadius = trackHeight / 2;

    // Paint background track first
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, Radius.circular(cornerRadius)),
      backgroundPaint,
    );

    // Paint each segment based on its readiness state
    for (int i = 0; i < totalSegments; i++) {
      final readiness = segmentReadiness[i];
      final state = readiness?.state;
      
      final segmentLeft = trackRect.left + (i * segmentWidth);
      final segmentRect = Rect.fromLTWH(
        segmentLeft,
        trackRect.top,
        segmentWidth,
        trackHeight,
      );

      // Determine color based on segment state and position
      Color segmentColor;
      bool shouldPulse = false;
      
      if (i <= currentIndex) {
        // Played segments are always fully colored
        segmentColor = primaryColor;
      } else if (state == SegmentState.ready) {
        // Ready future segments: lighter primary
        segmentColor = primaryColor.withValues(alpha: 0.6);
      } else if (state == SegmentState.synthesizing) {
        // Synthesizing: animated pulse
        segmentColor = primaryColor.withValues(alpha: synthesizingAnimation.value);
        shouldPulse = true;
      } else if (state == SegmentState.queued) {
        // Queued: dimmed
        segmentColor = primaryColor.withValues(alpha: 0.25);
      } else {
        // Not queued or no state: most dimmed
        segmentColor = primaryColor.withValues(alpha: 0.1);
      }

      final segmentPaint = Paint()
        ..color = segmentColor
        ..style = PaintingStyle.fill;

      // Handle rounded corners at edges
      if (i == 0) {
        // First segment - round left corners
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            segmentRect,
            topLeft: Radius.circular(cornerRadius),
            bottomLeft: Radius.circular(cornerRadius),
          ),
          segmentPaint,
        );
      } else if (i == totalSegments - 1) {
        // Last segment - round right corners
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            segmentRect,
            topRight: Radius.circular(cornerRadius),
            bottomRight: Radius.circular(cornerRadius),
          ),
          segmentPaint,
        );
      } else {
        // Middle segments - no rounding
        canvas.drawRect(segmentRect, segmentPaint);
      }

      // Add glow effect for synthesizing segments
      if (shouldPulse) {
        final glowPaint = Paint()
          ..color = primaryColor.withValues(alpha: synthesizingAnimation.value * 0.3)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
        canvas.drawRect(segmentRect, glowPaint);
      }
    }
  }
}
