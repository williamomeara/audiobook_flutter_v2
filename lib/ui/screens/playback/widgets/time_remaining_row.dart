import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/playback_providers.dart';
import '../../../theme/app_colors.dart';

/// Displays time remaining in chapter and book.
/// 
/// Shows "Xh Ym left in chapter • Xh Ym left in book" below the progress slider.
/// Time is adjusted for current playback speed (e.g., at 1.5x, shows 1/1.5 of actual time).
class TimeRemainingRow extends ConsumerWidget {
  const TimeRemainingRow({
    super.key,
    required this.bookId,
    required this.chapterIndex,
  });

  final String bookId;
  final int chapterIndex;

  /// Format duration as "Xh Ym" or "Xm" for shorter durations.
  String _formatDuration(Duration duration) {
    final totalMinutes = duration.inMinutes;
    if (totalMinutes < 60) {
      return '${totalMinutes}m';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  /// Adjust duration for playback speed.
  /// At 1.5x speed, a 30 minute segment will play in 20 minutes.
  Duration _adjustForSpeed(Duration duration, double playbackRate) {
    if (playbackRate <= 0) return duration;
    final adjustedMs = (duration.inMilliseconds / playbackRate).round();
    return Duration(milliseconds: adjustedMs);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    // Get current playback rate from player state (not settings default)
    final playbackRate = ref.watch(
      playbackStateProvider.select((s) => s.playbackRate),
    );

    // Get chapter progress for current chapter
    final chapterKey = '$bookId:$chapterIndex';
    final chapterProgressAsync = ref.watch(chapterProgressProvider(chapterKey));
    
    // Get book progress summary
    final bookProgressAsync = ref.watch(bookProgressSummaryProvider(bookId));
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Chapter remaining
          chapterProgressAsync.when(
            data: (chapterProgress) {
              if (chapterProgress == null || chapterProgress.durationMs == 0) {
                return const SizedBox.shrink();
              }
              final totalMs = chapterProgress.durationMs;
              final listenedMs = (chapterProgress.percentComplete * totalMs).round();
              final remainingMs = (totalMs - listenedMs).clamp(0, totalMs);
              final remaining = Duration(milliseconds: remainingMs);
              final adjustedRemaining = _adjustForSpeed(remaining, playbackRate);
              return Text(
                '${_formatDuration(adjustedRemaining)} left in chapter',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          
          // Divider
          bookProgressAsync.maybeWhen(
            data: (summary) => summary.totalDurationMs > 0 ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '•',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textTertiary,
                ),
              ),
            ) : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          
          // Book remaining
          bookProgressAsync.when(
            data: (summary) {
              if (summary.totalDurationMs == 0) {
                return const SizedBox.shrink();
              }
              final adjustedRemaining = _adjustForSpeed(summary.remainingDuration, playbackRate);
              return Text(
                '${_formatDuration(adjustedRemaining)} left in book',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textTertiary,
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
