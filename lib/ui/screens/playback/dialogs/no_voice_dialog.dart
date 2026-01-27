import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/app_colors.dart';

/// Dialog shown when user tries to play but no voice is selected/downloaded.
class NoVoiceDialog extends StatelessWidget {
  const NoVoiceDialog({super.key});

  /// Shows the no voice dialog.
  /// Returns true if user chose to navigate to downloads, false otherwise.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const NoVoiceDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    return AlertDialog(
      backgroundColor: colors.card,
      title: Text(
        'No Voice Selected',
        style: TextStyle(color: colors.text),
      ),
      content: Text(
        'Please download a voice from the settings menu before playing audiobooks.',
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
