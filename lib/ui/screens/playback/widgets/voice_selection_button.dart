import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core_domain/core_domain.dart';

import '../../../../app/playback/state/playback_view_state.dart';
import '../../../../app/settings_controller.dart';
import '../../../theme/app_colors.dart';

/// Voice selection button for the playback screen.
/// 
/// Shows the currently selected voice and warmup status.
/// Tapping opens a voice picker sheet.
/// 
/// States:
/// - Ready: Shows voice icon + voice name + dropdown arrow
/// - Warming: Shows animated spinner + "Preparing..." (disabled)
/// - Error: Shows warning icon + "Voice unavailable" + dropdown arrow
/// - No Voice: Shows voice icon + "Select voice" + dropdown arrow
class VoiceSelectionButton extends ConsumerWidget {
  const VoiceSelectionButton({
    super.key,
    required this.warmupStatus,
    required this.onTap,
  });

  /// Current engine warmup status.
  final EngineWarmupStatus warmupStatus;
  
  /// Called when the button is tapped (to open voice picker).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final settings = ref.watch(settingsProvider);
    final voiceId = settings.selectedVoice;
    
    final isWarming = warmupStatus == EngineWarmupStatus.warming;
    final hasNoVoice = voiceId == VoiceIds.none;

    return Semantics(
      label: _semanticsLabel(voiceId, warmupStatus),
      button: true,
      enabled: !isWarming,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _backgroundColor(colors, warmupStatus, hasNoVoice),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _borderColor(colors, warmupStatus),
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isWarming ? null : onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildIcon(colors, warmupStatus),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _buttonText(voiceId, warmupStatus),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _textColor(colors, warmupStatus, isWarming),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isWarming) ...[
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: _iconColor(colors, warmupStatus),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(AppThemeColors colors, EngineWarmupStatus status) {
    switch (status) {
      case EngineWarmupStatus.warming:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(colors.primary),
          ),
        );
      case EngineWarmupStatus.failed:
        return Icon(
          Icons.warning_amber_rounded,
          size: 14,
          color: colors.danger,
        );
      case EngineWarmupStatus.ready:
      case EngineWarmupStatus.notStarted:
        return Icon(
          Icons.mic,
          size: 14,
          color: colors.primary,
        );
    }
  }

  String _buttonText(String voiceId, EngineWarmupStatus status) {
    if (status == EngineWarmupStatus.warming) {
      return 'Preparing...';
    }
    if (status == EngineWarmupStatus.failed) {
      return 'Voice error';
    }
    if (voiceId == VoiceIds.none) {
      return 'Select voice';
    }
    return _shortDisplayName(voiceId);
  }
  
  /// Get a short display name suitable for the compact button.
  /// 
  /// Examples:
  /// - "kokoro_bf_emma" → "Emma"
  /// - "piper:en_US-lessac-medium" → "Lessac"
  /// - "supertonic_m1" → "M1"
  String _shortDisplayName(String voiceId) {
    // Kokoro voices: extract just the name
    if (voiceId.startsWith('kokoro_')) {
      final parts = voiceId.substring(7).split('_');
      if (parts.length >= 2) {
        return parts[1][0].toUpperCase() + parts[1].substring(1);
      }
    }
    
    // Piper voices: extract the voice name
    if (voiceId.startsWith('piper:')) {
      final modelKey = voiceId.substring(6);
      final parts = modelKey.split('-');
      if (parts.length >= 2) {
        return parts[1][0].toUpperCase() + parts[1].substring(1);
      }
    }
    
    // Supertonic: show suffix like M1, F2
    if (voiceId.startsWith('supertonic_')) {
      return voiceId.substring(11).toUpperCase();
    }
    
    if (voiceId == VoiceIds.device) {
      return 'Device';
    }
    
    // Fallback to full display name
    return VoiceIds.getDisplayName(voiceId);
  }

  String _semanticsLabel(String voiceId, EngineWarmupStatus status) {
    if (status == EngineWarmupStatus.warming) {
      return 'Voice is loading, please wait';
    }
    if (status == EngineWarmupStatus.failed) {
      return 'Voice error, tap to select a different voice';
    }
    if (voiceId == VoiceIds.none) {
      return 'No voice selected, tap to select a voice';
    }
    return 'Voice: ${VoiceIds.getDisplayName(voiceId)}, tap to change';
  }

  Color _backgroundColor(AppThemeColors colors, EngineWarmupStatus status, bool hasNoVoice) {
    if (status == EngineWarmupStatus.failed) {
      return colors.danger.withValues(alpha: 0.1);
    }
    if (status == EngineWarmupStatus.warming) {
      return colors.primary.withValues(alpha: 0.05);
    }
    if (hasNoVoice) {
      return colors.warning.withValues(alpha: 0.1);
    }
    return colors.primary.withValues(alpha: 0.1);
  }

  Color _borderColor(AppThemeColors colors, EngineWarmupStatus status) {
    if (status == EngineWarmupStatus.failed) {
      return colors.danger.withValues(alpha: 0.3);
    }
    if (status == EngineWarmupStatus.warming) {
      return colors.primary.withValues(alpha: 0.2);
    }
    return colors.primary.withValues(alpha: 0.2);
  }

  Color _textColor(AppThemeColors colors, EngineWarmupStatus status, bool isWarming) {
    if (status == EngineWarmupStatus.failed) {
      return colors.danger;
    }
    if (isWarming) {
      return colors.textSecondary;
    }
    return colors.text;
  }

  Color _iconColor(AppThemeColors colors, EngineWarmupStatus status) {
    if (status == EngineWarmupStatus.failed) {
      return colors.danger;
    }
    return colors.textSecondary;
  }
}
