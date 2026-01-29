import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';

/// Previous segment button.
///
/// Used for navigating to the previous audio segment within a chapter.
class PreviousSegmentButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;
  final bool isVertical;

  const PreviousSegmentButton({
    super.key,
    required this.enabled,
    required this.onTap,
    this.isVertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    return Semantics(
      enabled: enabled,
      button: true,
      onTap: enabled ? onTap : null,
      label: 'Previous segment',
      tooltip: enabled ? 'Go to previous segment' : 'No previous segment',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(isVertical ? 16 : 24),
          child: Padding(
            padding: EdgeInsets.all(isVertical ? 6 : 8),
            child: Icon(
              isVertical ? Icons.keyboard_arrow_up : Icons.fast_rewind,
              size: 28,
              color: enabled ? colors.text : colors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Next segment button.
///
/// Used for navigating to the next audio segment within a chapter.
class NextSegmentButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;
  final bool isVertical;

  const NextSegmentButton({
    super.key,
    required this.enabled,
    required this.onTap,
    this.isVertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    return Semantics(
      enabled: enabled,
      button: true,
      onTap: enabled ? onTap : null,
      label: 'Next segment',
      tooltip: enabled ? 'Go to next segment' : 'No next segment',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(isVertical ? 16 : 24),
          child: Padding(
            padding: EdgeInsets.all(isVertical ? 6 : 8),
            child: Icon(
              isVertical ? Icons.keyboard_arrow_down : Icons.fast_forward,
              size: 28,
              color: enabled ? colors.text : colors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
