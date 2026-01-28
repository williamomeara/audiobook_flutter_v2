import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/app_colors.dart';

/// Dialog shown when the selected voice is not available (e.g., model deleted or failed to load).
/// 
/// This dialog gives the user options to:
/// 1. Download the voice (navigate to downloads screen)
/// 2. Select a different voice (navigate to voice picker)
/// 3. Cancel and stay on current screen
class VoiceUnavailableDialog extends StatelessWidget {
  const VoiceUnavailableDialog({
    super.key,
    required this.voiceId,
    this.errorMessage,
  });

  /// The voice ID that is unavailable.
  final String voiceId;
  
  /// Optional error message to display.
  final String? errorMessage;

  /// Shows the voice unavailable dialog.
  /// 
  /// Returns a [VoiceUnavailableAction] indicating what the user chose:
  /// - [VoiceUnavailableAction.download] - User wants to download the voice
  /// - [VoiceUnavailableAction.selectDifferent] - User wants to select a different voice
  /// - [VoiceUnavailableAction.cancel] - User cancelled (or dismissed the dialog)
  static Future<VoiceUnavailableAction> show(
    BuildContext context, {
    required String voiceId,
    String? errorMessage,
  }) async {
    final result = await showDialog<VoiceUnavailableAction>(
      context: context,
      builder: (context) => VoiceUnavailableDialog(
        voiceId: voiceId,
        errorMessage: errorMessage,
      ),
    );
    return result ?? VoiceUnavailableAction.cancel;
  }

  /// Extracts a display name from a voice ID.
  /// Example: "supertonic_m5" -> "Supertonic M5"
  String _getVoiceDisplayName() {
    final parts = voiceId.split('_');
    if (parts.isEmpty) return voiceId;
    
    // Capitalize first letter of each part
    return parts.map((part) {
      if (part.isEmpty) return part;
      return part[0].toUpperCase() + part.substring(1);
    }).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final voiceName = _getVoiceDisplayName();

    return AlertDialog(
      backgroundColor: colors.card,
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.warning, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Voice Unavailable',
              style: TextStyle(color: colors.text),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The voice "$voiceName" is not available.',
            style: TextStyle(color: colors.textSecondary),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              errorMessage!,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'The voice model may need to be downloaded, or there was an error loading it.',
            style: TextStyle(color: colors.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, VoiceUnavailableAction.cancel),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context, VoiceUnavailableAction.selectDifferent);
            // Note: Caller should navigate to settings voice picker
          },
          child: Text('Select Voice', style: TextStyle(color: colors.accent)),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, VoiceUnavailableAction.download);
            context.push('/settings/downloads');
          },
          child: const Text('Download'),
        ),
      ],
    );
  }
}

/// Actions the user can take when a voice is unavailable.
enum VoiceUnavailableAction {
  /// User cancelled or dismissed the dialog.
  cancel,
  
  /// User wants to download the voice.
  download,
  
  /// User wants to select a different voice.
  selectDifferent,
}
