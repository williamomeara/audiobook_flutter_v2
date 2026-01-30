import 'package:flutter/material.dart';
import 'package:core_domain/core_domain.dart';
import 'package:playback/playback.dart';

import '../../../theme/app_colors.dart';
import '../widgets/widgets.dart';

/// Portrait layout for the playback screen.
/// 
/// Shows:
/// - Header with book title and chapter
/// - Error banner (if any)
/// - Loading indicator or content (cover/text display)
/// - Playback controls at bottom
class PortraitLayout extends StatelessWidget {
  const PortraitLayout({
    super.key,
    required this.book,
    required this.chapter,
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
    required this.isPreviewMode,
    required this.onBack,
    required this.onToggleView,
    required this.onSegmentTap,
    required this.onAutoScrollDisabled,
    required this.onJumpToCurrent,
    required this.playbackControlsBuilder,
    required this.errorBannerBuilder,
  });
  
  final Book book;
  final Chapter chapter;
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
  final bool isPreviewMode;
  
  // Callbacks
  final VoidCallback onBack;
  final VoidCallback onToggleView;
  final void Function(int) onSegmentTap;
  final VoidCallback onAutoScrollDisabled;
  final VoidCallback onJumpToCurrent;
  
  // Builders for complex widgets that need parent state
  final Widget Function() playbackControlsBuilder;
  final Widget Function(String error) errorBannerBuilder;
  
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    
    return SafeArea(
      child: Column(
        children: [
          PlaybackHeader(
            book: book,
            chapter: chapter,
            showCover: showCover,
            onBack: onBack,
            onToggleView: onToggleView,
          ),
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
                    Text('Loading chapter...', style: TextStyle(color: colors.textSecondary)),
                  ],
                ),
              ),
            )
          else ...[
            Expanded(
              child: showCover
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
                      isPreviewMode: isPreviewMode,
                    ),
            ),
            playbackControlsBuilder(),
          ],
        ],
      ),
    );
  }
}
