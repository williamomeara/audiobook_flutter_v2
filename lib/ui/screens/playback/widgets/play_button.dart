import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// Play/pause button widget with buffering state support.
class PlayButton extends StatelessWidget {
  const PlayButton({
    super.key,
    required this.isPlaying,
    required this.isBuffering,
    required this.onToggle,
    this.size = 56.0,
    this.iconSize = 28.0,
  });

  final bool isPlaying;
  final bool isBuffering;
  final VoidCallback onToggle;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    return Material(
      color: colors.primary,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onToggle,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: isBuffering
              ? SizedBox(
                  width: size * 0.4,
                  height: size * 0.4,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primaryForeground,
                  ),
                )
              : Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  size: iconSize,
                  color: colors.primaryForeground,
                ),
        ),
      ),
    );
  }
}
