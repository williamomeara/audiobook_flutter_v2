import 'package:flutter/material.dart';
import 'package:playback/playback.dart';

import '../theme/app_colors.dart';

/// Displays buffer status during playback.
///
/// Shows:
/// - Buffer level as text ("Buffer: 23s ahead")
/// - Synthesis activity indicator
/// - Warning colors when buffer is low
///
/// This is purely informational - it never blocks playback.
class BufferIndicator extends StatelessWidget {
  const BufferIndicator({
    super.key,
    required this.status,
    required this.colors,
    this.compact = false,
  });

  /// Current buffer status.
  final BufferStatus status;

  /// Theme colors.
  final AppThemeColors colors;

  /// Whether to use compact display (icon only).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompact();
    }
    return _buildFull();
  }

  Widget _buildCompact() {
    final warningLevel = status.warningLevel;
    final color = _colorForWarning(warningLevel);
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status.isSynthesizing) ...[
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Icon(
          _iconForWarning(warningLevel),
          size: 16,
          color: color,
        ),
      ],
    );
  }

  Widget _buildFull() {
    final warningLevel = status.warningLevel;
    final color = _colorForWarning(warningLevel);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.isSynthesizing) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(width: 6),
          ] else ...[
            Icon(
              _iconForWarning(warningLevel),
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            status.displayText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForWarning(BufferWarningLevel level) {
    switch (level) {
      case BufferWarningLevel.none:
        return colors.textSecondary;
      case BufferWarningLevel.info:
        return colors.primary;
      case BufferWarningLevel.warning:
        return Colors.orange;
      case BufferWarningLevel.critical:
        return Colors.red;
    }
  }

  IconData _iconForWarning(BufferWarningLevel level) {
    switch (level) {
      case BufferWarningLevel.none:
        return Icons.check_circle_outline;
      case BufferWarningLevel.info:
        return Icons.info_outline;
      case BufferWarningLevel.warning:
        return Icons.warning_amber;
      case BufferWarningLevel.critical:
        return Icons.error_outline;
    }
  }
}

/// A dismissible snackbar for low buffer warnings.
///
/// Shows when buffer drops below threshold, but can be dismissed.
/// Doesn't block playback - just informs the user.
class LowBufferWarning extends StatelessWidget {
  const LowBufferWarning({
    super.key,
    required this.status,
    required this.onDismiss,
    this.onWaitForBuffer,
  });

  /// Current buffer status.
  final BufferStatus status;

  /// Called when user dismisses the warning.
  final VoidCallback onDismiss;

  /// Called when user taps "Wait for buffer".
  /// If null, the option is not shown.
  final VoidCallback? onWaitForBuffer;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final textSecondaryColor = isDark ? Colors.white70 : Colors.black54;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber,
            color: Colors.orange,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Low buffer',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                Text(
                  'Brief pause possible',
                  style: TextStyle(
                    fontSize: 13,
                    color: textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
          if (onWaitForBuffer != null)
            TextButton(
              onPressed: onWaitForBuffer,
              child: const Text('Wait'),
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
