import 'package:flutter/material.dart';
import 'package:playback/playback.dart';

import '../theme/app_colors.dart';

/// Displays voice compatibility status in voice picker.
///
/// Shows an indicator based on VoiceCompatibility level:
/// - Excellent: Green checkmark, works great
/// - Good: Blue info, works well
/// - Marginal: Orange warning, may struggle at high speeds
/// - TooSlow: Red warning, brief pauses may occur
/// - Unknown: Gray question mark, no data yet
class VoiceCompatibilityIndicator extends StatelessWidget {
  const VoiceCompatibilityIndicator({
    super.key,
    required this.compatibility,
    required this.colors,
    this.showLabel = true,
    this.compact = false,
  });

  /// Voice compatibility level.
  final VoiceCompatibility compatibility;

  /// Theme colors.
  final AppThemeColors colors;

  /// Whether to show text label.
  final bool showLabel;

  /// Whether to use compact display.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final icon = _iconFor(compatibility);
    final color = _colorFor(compatibility);
    final label = _labelFor(compatibility);

    if (compact) {
      return Icon(icon, size: 16, color: color);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        if (showLabel) ...[
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  IconData _iconFor(VoiceCompatibility compat) {
    switch (compat) {
      case VoiceCompatibility.excellent:
        return Icons.check_circle;
      case VoiceCompatibility.good:
        return Icons.check_circle_outline;
      case VoiceCompatibility.marginal:
        return Icons.warning_amber;
      case VoiceCompatibility.tooSlow:
        return Icons.error_outline;
      case VoiceCompatibility.unknown:
        return Icons.help_outline;
    }
  }

  Color _colorFor(VoiceCompatibility compat) {
    switch (compat) {
      case VoiceCompatibility.excellent:
        return Colors.green;
      case VoiceCompatibility.good:
        return colors.primary;
      case VoiceCompatibility.marginal:
        return Colors.orange;
      case VoiceCompatibility.tooSlow:
        return Colors.red;
      case VoiceCompatibility.unknown:
        return colors.textTertiary;
    }
  }

  String _labelFor(VoiceCompatibility compat) {
    switch (compat) {
      case VoiceCompatibility.excellent:
        return 'Excellent';
      case VoiceCompatibility.good:
        return 'Good';
      case VoiceCompatibility.marginal:
        return 'May struggle';
      case VoiceCompatibility.tooSlow:
        return 'Too slow';
      case VoiceCompatibility.unknown:
        return 'Unknown';
    }
  }
}

/// A badge showing compatibility for a voice option.
class VoiceCompatibilityBadge extends StatelessWidget {
  const VoiceCompatibilityBadge({
    super.key,
    required this.compatibility,
    required this.colors,
  });

  final VoiceCompatibility compatibility;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(compatibility);
    final text = _textFor(compatibility);

    if (compatibility == VoiceCompatibility.unknown) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Color _colorFor(VoiceCompatibility compat) {
    switch (compat) {
      case VoiceCompatibility.excellent:
        return Colors.green;
      case VoiceCompatibility.good:
        return colors.primary;
      case VoiceCompatibility.marginal:
        return Colors.orange;
      case VoiceCompatibility.tooSlow:
        return Colors.red;
      case VoiceCompatibility.unknown:
        return colors.textTertiary;
    }
  }

  String _textFor(VoiceCompatibility compat) {
    switch (compat) {
      case VoiceCompatibility.excellent:
        return 'FAST';
      case VoiceCompatibility.good:
        return 'OK';
      case VoiceCompatibility.marginal:
        return 'SLOW';
      case VoiceCompatibility.tooSlow:
        return 'TOO SLOW';
      case VoiceCompatibility.unknown:
        return '';
    }
  }
}

/// Tooltip content explaining voice compatibility.
class VoiceCompatibilityTooltip extends StatelessWidget {
  const VoiceCompatibilityTooltip({
    super.key,
    required this.compatibility,
    this.maxSpeed,
  });

  final VoiceCompatibility compatibility;
  final double? maxSpeed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _titleFor(compatibility),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _descriptionFor(compatibility),
            style: const TextStyle(fontSize: 13),
          ),
          if (maxSpeed != null && maxSpeed! < 3.0) ...[
            const SizedBox(height: 4),
            Text(
              'Max recommended: ${maxSpeed!.toStringAsFixed(1)}x',
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _titleFor(VoiceCompatibility compat) {
    switch (compat) {
      case VoiceCompatibility.excellent:
        return 'Works great!';
      case VoiceCompatibility.good:
        return 'Works well';
      case VoiceCompatibility.marginal:
        return 'May struggle';
      case VoiceCompatibility.tooSlow:
        return 'Too slow for this device';
      case VoiceCompatibility.unknown:
        return 'Not tested yet';
    }
  }

  String _descriptionFor(VoiceCompatibility compat) {
    switch (compat) {
      case VoiceCompatibility.excellent:
        return 'This voice runs fast on your device, even at high playback speeds.';
      case VoiceCompatibility.good:
        return 'This voice works well on your device at normal playback speeds.';
      case VoiceCompatibility.marginal:
        return 'This voice may struggle at higher playback speeds. Consider using a faster voice for 2x+ playback.';
      case VoiceCompatibility.tooSlow:
        return 'This voice cannot keep up with playback on your device. Brief pauses may occur. Consider a faster voice.';
      case VoiceCompatibility.unknown:
        return 'Performance will be measured once you start using this voice.';
    }
  }
}
