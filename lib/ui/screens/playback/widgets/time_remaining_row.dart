import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/playback_providers.dart';
import '../../../theme/app_colors.dart';

/// Displays time remaining in chapter and book.
/// 
/// Shows "Xh Ym left in chapter • Xh Ym left in book" below the progress slider.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

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
              return Text(
                '${_formatDuration(remaining)} left in chapter',
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
              return Text(
                '${_formatDuration(summary.remainingDuration)} left in book',
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
