import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core_domain/core_domain.dart';
import 'package:playback/playback.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/segment_seek_slider.dart';
import '../../../../app/playback_providers.dart';
import '../widgets/widgets.dart';

/// Layout constants for landscape mode.
class LandscapeLayoutConstants {
  static const double controlsWidth = 100.0;
  static const double bottomBarHeight = 52.0;
}

/// Landscape layout for the playback screen.
///
/// Shows:
/// - Main content area (left, with right padding for controls)
/// - Vertical controls on right side
/// - Bottom bar with chapter navigation and progress
class LandscapeLayout extends ConsumerWidget {
  const LandscapeLayout({
    super.key,
    required this.book,
    required this.playbackState,
    required this.queue,
    required this.currentIndex,
    required this.queueLength,
    required this.chapterIdx,
    required this.isLoading,
    required this.showCover,
    required this.bookId,
    required this.chapterIndex,
    required this.autoScrollEnabled,
    required this.scrollController,
    required this.activeSegmentKey,
    required this.sleepTimerMinutes,
    required this.sleepTimeRemainingSeconds,
    required this.onBack,
    required this.onSegmentTap,
    required this.onAutoScrollDisabled,
    required this.onJumpToCurrent,
    required this.onDecreaseSpeed,
    required this.onIncreaseSpeed,
    required this.onPreviousSegment,
    required this.onNextSegment,
    required this.onTogglePlay,
    required this.onShowSleepTimerPicker,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onSnapBack,
    required this.errorBannerBuilder,
  });

  final Book book;
  final PlaybackState playbackState;
  final List<AudioTrack> queue;
  final int currentIndex;
  final int queueLength;
  final int chapterIdx;
  final bool isLoading;
  final bool showCover;
  final String bookId;
  final int chapterIndex;
  final bool autoScrollEnabled;
  final ScrollController scrollController;
  final GlobalKey activeSegmentKey;
  final int? sleepTimerMinutes;
  final int? sleepTimeRemainingSeconds;

  // Callbacks
  final VoidCallback onBack;
  final void Function(int) onSegmentTap;
  final VoidCallback onAutoScrollDisabled;
  final VoidCallback onJumpToCurrent;
  final VoidCallback onDecreaseSpeed;
  final VoidCallback onIncreaseSpeed;
  final VoidCallback onPreviousSegment;
  final VoidCallback onNextSegment;
  final VoidCallback onTogglePlay;
  final VoidCallback onShowSleepTimerPicker;
  final VoidCallback onPreviousChapter;
  final VoidCallback onNextChapter;
  final VoidCallback onSnapBack;

  // Builder for error banner
  final Widget Function(String error) errorBannerBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    return SafeArea(
      child: Stack(
        children: [
          // Main content area (padded for controls)
          Positioned.fill(
            right: LandscapeLayoutConstants.controlsWidth,
            bottom: LandscapeLayoutConstants.bottomBarHeight,
            child: Column(
              children: [
                if (playbackState.error != null)
                  errorBannerBuilder(playbackState.error!),
                if (isLoading)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: colors.primary),
                          const SizedBox(height: 16),
                          Text(
                            'Loading chapter...',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child:
                        showCover
                            ? CoverView(book: book)
                            : TextDisplayView(
                              bookId: bookId,
                              chapterIndex: chapterIndex,
                              queue: queue,
                              currentIndex: currentIndex,
                              book: book,
                              onSegmentTap: onSegmentTap,
                              scrollController: scrollController,
                              autoScrollEnabled: autoScrollEnabled,
                              onAutoScrollDisabled: onAutoScrollDisabled,
                              onJumpToCurrent: onJumpToCurrent,
                              activeSegmentKey: activeSegmentKey,
                            ),
                  ),
              ],
            ),
          ),
          // Back button (top left corner)
          Positioned(
            left: 8,
            top: 8,
            child: Material(
              color: colors.controlBackground.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.arrow_back, size: 20, color: colors.text),
                ),
              ),
            ),
          ),
          // Right side vertical controls (full height)
          if (!isLoading)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _LandscapeControls(
                playbackState: playbackState,
                currentIndex: currentIndex,
                queueLength: queueLength,
                sleepTimerMinutes: sleepTimerMinutes,
                sleepTimeRemainingSeconds: sleepTimeRemainingSeconds,
                onDecreaseSpeed: onDecreaseSpeed,
                onIncreaseSpeed: onIncreaseSpeed,
                onPreviousSegment: onPreviousSegment,
                onNextSegment: onNextSegment,
                onTogglePlay: onTogglePlay,
                onShowSleepTimerPicker: onShowSleepTimerPicker,
              ),
            ),
          // Bottom bar with chapter controls + progress
          if (!isLoading)
            Positioned(
              left: 0,
              right: LandscapeLayoutConstants.controlsWidth,
              bottom: 0,
              child: _LandscapeBottomBar(
                bookId: bookId,
                chapterIndex: chapterIndex,
                currentIndex: currentIndex,
                queueLength: queueLength,
                chapterIdx: chapterIdx,
                chapterCount: book.chapters.length,
                onSegmentTap: onSegmentTap,
                onPreviousChapter: onPreviousChapter,
                onNextChapter: onNextChapter,
                onSnapBack: onSnapBack,
              ),
            ),
        ],
      ),
    );
  }
}

/// Vertical controls for landscape mode (right side).
class _LandscapeControls extends StatelessWidget {
  const _LandscapeControls({
    required this.playbackState,
    required this.currentIndex,
    required this.queueLength,
    required this.sleepTimerMinutes,
    required this.sleepTimeRemainingSeconds,
    required this.onDecreaseSpeed,
    required this.onIncreaseSpeed,
    required this.onPreviousSegment,
    required this.onNextSegment,
    required this.onTogglePlay,
    required this.onShowSleepTimerPicker,
  });

  final PlaybackState playbackState;
  final int currentIndex;
  final int queueLength;
  final int? sleepTimerMinutes;
  final int? sleepTimeRemainingSeconds;
  final VoidCallback onDecreaseSpeed;
  final VoidCallback onIncreaseSpeed;
  final VoidCallback onPreviousSegment;
  final VoidCallback onNextSegment;
  final VoidCallback onTogglePlay;
  final VoidCallback onShowSleepTimerPicker;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    return Container(
      width: LandscapeLayoutConstants.controlsWidth,
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.95),
        border: Border(left: BorderSide(color: colors.border, width: 1)),
      ),
      child: Column(
        children: [
          // Top section (expandable) - Speed controls + up arrow
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Speed control
                SpeedControl(
                  playbackRate: playbackState.playbackRate,
                  onDecrease: onDecreaseSpeed,
                  onIncrease: onIncreaseSpeed,
                  isVertical: true,
                ),

                const SizedBox(height: 16),

                // Previous segment (up arrow)
                PreviousSegmentButton(
                  enabled: currentIndex > 0,
                  onTap: onPreviousSegment,
                  isVertical: true,
                ),

                const SizedBox(height: 6),
              ],
            ),
          ),

          // Center section (fixed) - Play button
          PlayButton(
            isPlaying: playbackState.isPlaying,
            isBuffering: playbackState.isBuffering,
            onToggle: onTogglePlay,
          ),

          // Bottom section (expandable) - down arrow + sleep timer
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 6),

                // Next segment (down arrow)
                NextSegmentButton(
                  enabled: currentIndex < queueLength - 1,
                  onTap: onNextSegment,
                  isVertical: true,
                ),

                const SizedBox(height: 16),

                // Sleep timer
                SleepTimerControl(
                  timerMinutes: sleepTimerMinutes,
                  remainingSeconds: sleepTimeRemainingSeconds,
                  onTap: onShowSleepTimerPicker,
                  isCompact: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom bar for landscape mode (chapter controls + progress bar).
class _LandscapeBottomBar extends ConsumerWidget {
  const _LandscapeBottomBar({
    required this.bookId,
    required this.chapterIndex,
    required this.currentIndex,
    required this.queueLength,
    required this.chapterIdx,
    required this.chapterCount,
    required this.onSegmentTap,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onSnapBack,
  });

  final String bookId;
  final int chapterIndex;
  final int currentIndex;
  final int queueLength;
  final int chapterIdx;
  final int chapterCount;
  final void Function(int) onSegmentTap;
  final VoidCallback onPreviousChapter;
  final VoidCallback onNextChapter;
  final VoidCallback onSnapBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    // Check for browsing mode
    final isBrowsing = ref.watch(isBrowsingProvider(bookId));
    final primaryAsync = ref.watch(primaryPositionProvider(bookId));

    // Get segment readiness for synthesis status display
    final readinessKey = '$bookId:$chapterIndex';
    final segmentReadinessAsync = ref.watch(
      segmentReadinessStreamProvider(readinessKey),
    );
    final segmentReadiness = segmentReadinessAsync.value ?? {};

    return Container(
      height:
          LandscapeLayoutConstants.bottomBarHeight +
          16, // Extra height for slider thumb
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: colors.border, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            // Previous chapter (left side)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: chapterIdx > 0 ? onPreviousChapter : null,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.skip_previous,
                    size: 24,
                    color: chapterIdx > 0 ? colors.text : colors.textTertiary,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Segment seek slider (center, expanded)
            Expanded(
              child: Row(
                children: [
                  Text(
                    '${currentIndex + 1}',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SegmentSeekSlider(
                      // Key forces rebuild when readiness state changes
                      key: ValueKey(
                        'slider_landscape_${segmentReadiness.hashCode}',
                      ),
                      currentIndex: currentIndex,
                      totalSegments: queueLength,
                      colors: colors,
                      height: 4,
                      showPreview:
                          false, // No preview in landscape (limited space)
                      segmentReadiness: segmentReadiness,
                      onSeek: onSegmentTap,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$queueLength',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Snap-back button (shown when browsing)
            if (isBrowsing &&
                primaryAsync.hasValue &&
                primaryAsync.value != null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onSnapBack,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.my_location,
                      size: 20,
                      color: colors.accent,
                    ),
                  ),
                ),
              ),

            // Next chapter (right side)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: chapterIdx < chapterCount - 1 ? onNextChapter : null,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.skip_next,
                    size: 24,
                    color:
                        chapterIdx < chapterCount - 1
                            ? colors.text
                            : colors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
