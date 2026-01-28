import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';

/// Speed control widget for adjusting playback rate.
/// 
/// Can be displayed horizontally (portrait) or vertically (landscape).
class SpeedControl extends StatelessWidget {
  final double playbackRate;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final bool isVertical;
  
  const SpeedControl({
    super.key,
    required this.playbackRate,
    required this.onDecrease,
    required this.onIncrease,
    this.isVertical = false,
  });
  
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    
    if (isVertical) {
      return _buildVertical(colors);
    }
    return _buildHorizontal(colors);
  }
  
  Widget _buildHorizontal(AppThemeColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.speed, size: 16, color: colors.textSecondary),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          onTap: onDecrease,
          label: 'Decrease speed',
          tooltip: 'Slow down playback',
          child: InkWell(
            onTap: onDecrease,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.chevron_left, size: 18, color: colors.textSecondary),
            ),
          ),
        ),
        Container(
          width: 48,
          alignment: Alignment.center,
          child: Text(
            '${playbackRate}x',
            style: TextStyle(fontSize: 13, color: colors.text, fontWeight: FontWeight.w500),
          ),
        ),
        Semantics(
          button: true,
          onTap: onIncrease,
          label: 'Increase speed',
          tooltip: 'Speed up playback',
          child: InkWell(
            onTap: onIncrease,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.chevron_right, size: 18, color: colors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildVertical(AppThemeColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.speed, size: 18, color: colors.textSecondary),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              onTap: onDecrease,
              label: 'Decrease speed',
              tooltip: 'Slow down playback',
              child: InkWell(
                onTap: onDecrease,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.remove, size: 18, color: colors.textSecondary),
                ),
              ),
            ),
            Text(
              '${playbackRate}x',
              style: TextStyle(fontSize: 13, color: colors.text, fontWeight: FontWeight.w500),
            ),
            Semantics(
              button: true,
              onTap: onIncrease,
              label: 'Increase speed',
              tooltip: 'Speed up playback',
              child: InkWell(
                onTap: onIncrease,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.add, size: 18, color: colors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
