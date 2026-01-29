import 'package:downloads/downloads.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/granular_download_manager.dart';
import '../../../../app/settings_controller.dart';
import '../../../../app/voice_preview_service.dart';
import '../../../theme/app_colors.dart';

/// Dialog shown when user tries to play but no voice is selected/downloaded.
class NoVoiceDialog extends ConsumerWidget {
  const NoVoiceDialog({super.key});

  /// Shows the no voice dialog.
  /// Returns true if user chose to navigate (to downloads or settings), false otherwise.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const NoVoiceDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final downloadState = ref.watch(granularDownloadManagerProvider);
    
    // Check if any voices are downloaded
    final readyVoices = downloadState.maybeWhen(
      data: (state) => state.readyVoices,
      orElse: () => <VoiceDownloadState>[],
    );
    
    final hasDownloadedVoices = readyVoices.isNotEmpty;
    
    if (hasDownloadedVoices) {
      // Voices are downloaded but none selected - show voice picker
      return _buildVoicePickerDialog(context, ref, colors, readyVoices);
    } else {
      // No voices downloaded - prompt to download
      return _buildDownloadPromptDialog(context, colors);
    }
  }
  
  Widget _buildVoicePickerDialog(
    BuildContext context,
    WidgetRef ref,
    AppThemeColors colors,
    List<VoiceDownloadState> readyVoices,
  ) {
    return AlertDialog(
      backgroundColor: colors.card,
      title: Text(
        'Select a Voice',
        style: TextStyle(color: colors.text),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a voice to start playback:',
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: readyVoices.length,
                itemBuilder: (context, index) {
                  final voice = readyVoices[index];
                  return _VoiceOptionTile(
                    voiceId: voice.voiceId,
                    colors: colors,
                    onSelected: () {
                      ref.read(settingsProvider.notifier).setSelectedVoice(voice.voiceId);
                      Navigator.pop(context, true);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context, true);
            context.push('/settings/downloads');
          },
          child: Text('Download More', style: TextStyle(color: colors.primary)),
        ),
      ],
    );
  }
  
  Widget _buildDownloadPromptDialog(BuildContext context, AppThemeColors colors) {
    return AlertDialog(
      backgroundColor: colors.card,
      title: Text(
        'No Voices Downloaded',
        style: TextStyle(color: colors.text),
      ),
      content: Text(
        'Please download a voice before playing audiobooks.',
        style: TextStyle(color: colors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, true);
            context.push('/settings/downloads');
          },
          child: const Text('Download Voices'),
        ),
      ],
    );
  }
}

/// Simple voice option tile for the dialog
class _VoiceOptionTile extends ConsumerWidget {
  const _VoiceOptionTile({
    required this.voiceId,
    required this.colors,
    required this.onSelected,
  });

  final String voiceId;
  final AppThemeColors colors;
  final VoidCallback onSelected;
  
  String _displayName(String voiceId) {
    // Extract a friendly name from the voice ID
    // e.g., "piper_en_US_amy_medium" -> "Amy (Piper)"
    final parts = voiceId.split('_');
    if (parts.length >= 4) {
      final engine = parts[0];
      final name = parts[3];
      final capitalizedName = name[0].toUpperCase() + name.substring(1);
      final engineLabel = engine[0].toUpperCase() + engine.substring(1);
      return '$capitalizedName ($engineLabel)';
    }
    return voiceId;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final isSelected = settings.selectedVoice == voiceId;
    final currentlyPlaying = ref.watch(voicePreviewProvider);
    final isPlaying = currentlyPlaying == voiceId;

    return ListTile(
      leading: IconButton(
        icon: Icon(
          isPlaying ? Icons.stop_circle : Icons.play_circle_outline,
          color: isPlaying ? colors.primary : colors.textSecondary,
        ),
        onPressed: () async {
          final notifier = ref.read(voicePreviewProvider.notifier);
          if (isPlaying) {
            await notifier.stop();
          } else {
            await notifier.playPreview(voiceId);
          }
        },
      ),
      title: Text(
        _displayName(voiceId),
        style: TextStyle(color: colors.text),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: colors.primary)
          : null,
      onTap: onSelected,
    );
  }
}
