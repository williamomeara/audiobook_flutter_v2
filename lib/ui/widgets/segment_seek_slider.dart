import 'package:flutter/material.dart';
import '../../utils/app_haptics.dart';
import '../theme/app_colors.dart';

/// A draggable slider for seeking between segments.
/// 
/// Replaces the static LinearProgressIndicator with an interactive slider
/// that allows users to drag to different segments with haptic feedback.
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

  @override
  State<SegmentSeekSlider> createState() => _SegmentSeekSliderState();
}

class _SegmentSeekSliderState extends State<SegmentSeekSlider> {
  // Preview segment index while dragging (-1 = not dragging)
  int _previewIndex = -1;
  
  // Last segment index where we triggered haptic
  int _lastHapticIndex = -1;

  @override
  Widget build(BuildContext context) {
    if (widget.totalSegments <= 0) {
      return const SizedBox.shrink();
    }

    final isDragging = _previewIndex >= 0;
    final displayIndex = isDragging ? _previewIndex : widget.currentIndex;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Segment preview tooltip while dragging
        if (widget.showPreview && isDragging)
          _buildPreviewTooltip(displayIndex),
        
        // The slider
        SizedBox(
          height: 24 + widget.height, // Slider needs some vertical space
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: widget.height,
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
            child: Slider(
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
