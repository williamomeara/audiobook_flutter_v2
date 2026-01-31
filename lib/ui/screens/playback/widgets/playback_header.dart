import 'package:flutter/material.dart';
import 'package:core_domain/core_domain.dart';

import '../../../../app/playback/state/playback_view_state.dart';
import '../../../theme/app_colors.dart';
import 'voice_selection_button.dart';

/// Header widget for the playback screen showing book title, chapter title,
/// voice selection button, and navigation controls.
class PlaybackHeader extends StatelessWidget {
  const PlaybackHeader({
    super.key,
    required this.book,
    required this.chapter,
    required this.showCover,
    required this.onBack,
    required this.onToggleView,
    required this.warmupStatus,
    required this.onVoiceTap,
  });

  final Book book;
  final Chapter chapter;
  final bool showCover;
  final VoidCallback onBack;
  final VoidCallback onToggleView;
  final EngineWarmupStatus warmupStatus;
  final VoidCallback onVoiceTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.chevron_left, color: colors.text),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: colors.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  chapter.title,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Voice selection button
          VoiceSelectionButton(
            warmupStatus: warmupStatus,
            onTap: onVoiceTap,
          ),
          const SizedBox(width: 4),
          // Toggle view button
          InkWell(
            onTap: onToggleView,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                showCover ? Icons.menu_book : Icons.image,
                color: colors.text,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
