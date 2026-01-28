import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';

/// Sleep timer control widget for setting a sleep timer.
/// 
/// Shows current timer setting and remaining time (if active).
/// Can be displayed in compact mode for landscape.
class SleepTimerControl extends StatelessWidget {
  final int? timerMinutes;
  final int? remainingSeconds;
  final VoidCallback onTap;
  final bool isCompact;
  
  const SleepTimerControl({
    super.key,
    required this.timerMinutes,
    required this.remainingSeconds,
    required this.onTap,
    this.isCompact = false,
  });
  
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    
    if (isCompact) {
      return _buildCompact(colors);
    }
    return _buildNormal(colors);
  }
  
  Widget _buildNormal(AppThemeColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 16, color: colors.textSecondary),
        const SizedBox(width: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.controlBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTimerLabel(timerMinutes),
                    style: TextStyle(fontSize: 13, color: colors.text),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 16, color: colors.textSecondary),
                ],
              ),
            ),
          ),
        ),
        if (remainingSeconds != null) ...[
          const SizedBox(width: 8),
          Text(
            _formatRemainingTime(remainingSeconds!),
            style: TextStyle(fontSize: 12, color: colors.textHighlight, fontWeight: FontWeight.w500),
          ),
        ],
      ],
    );
  }
  
  Widget _buildCompact(AppThemeColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: colors.controlBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: colors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    _formatTimerLabelCompact(timerMinutes),
                    style: TextStyle(fontSize: 11, color: colors.text),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (remainingSeconds != null) ...[
          const SizedBox(height: 4),
          Text(
            _formatRemainingTime(remainingSeconds!),
            style: TextStyle(fontSize: 10, color: colors.textHighlight, fontWeight: FontWeight.w500),
          ),
        ],
      ],
    );
  }
  
  String _formatTimerLabel(int? minutes) {
    if (minutes == null) return 'Off';
    if (minutes == 60) return '1 hour';
    return '$minutes min';
  }
  
  String _formatTimerLabelCompact(int? minutes) {
    if (minutes == null) return 'Off';
    if (minutes == 60) return '1hr';
    return '${minutes}m';
  }
  
  String _formatRemainingTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0) {
      return '$minutes:${secs.toString().padLeft(2, '0')}';
    }
    return '0:${secs.toString().padLeft(2, '0')}';
  }
}
