import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core_domain/core_domain.dart';
import 'package:playback/playback.dart';

import '../../../../../app/playback_providers.dart';
import '../../../../../app/settings_controller.dart';
import '../../../../theme/app_colors.dart';
import 'segment_tile.dart';

/// Text display view showing all segments as a continuous flowing text.
/// 
/// Features:
/// - Continuous text flow with tappable segments
/// - Visual distinction for past, current, and future segments
/// - Synthesis status indicators
/// - Optional book cover background
/// - Auto-scroll with "Jump to Audio" button when disabled
class TextDisplayView extends ConsumerStatefulWidget {
  const TextDisplayView({
    super.key,
    required this.bookId,
    required this.chapterIndex,
    required this.queue,
    required this.currentIndex,
    required this.book,
    required this.onSegmentTap,
    required this.scrollController,
    required this.autoScrollEnabled,
    required this.onAutoScrollDisabled,
    required this.onJumpToCurrent,
    required this.activeSegmentKey,
  });
  
  final String bookId;
  final int chapterIndex;
  final List<AudioTrack> queue;
  final int currentIndex;
  final Book book;
  final void Function(int) onSegmentTap;
  final ScrollController scrollController;
  final bool autoScrollEnabled;
  final VoidCallback onAutoScrollDisabled;
  final VoidCallback onJumpToCurrent;
  final GlobalKey activeSegmentKey;

  @override
  ConsumerState<TextDisplayView> createState() => _TextDisplayViewState();
}

class _TextDisplayViewState extends ConsumerState<TextDisplayView> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    
    if (widget.queue.isEmpty) {
      return Center(
        child: Text('No content', style: TextStyle(color: colors.textTertiary)),
      );
    }
    
    // Get setting for book cover background
    final settings = ref.watch(settingsProvider);
    final showCoverBackground = settings.showBookCoverBackground && widget.book.coverImagePath != null;
    
    // Determine dark mode from theme
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Watch segment readiness stream for opacity-based visualization
    final readinessKey = '${widget.bookId}:${widget.chapterIndex}';
    final segmentReadinessAsync = ref.watch(segmentReadinessStreamProvider(readinessKey));
    final segmentReadiness = segmentReadinessAsync.value ?? {};
    
    // Build text spans for continuous text flow
    final spans = buildSegmentSpans(
      queue: widget.queue,
      currentIndex: widget.currentIndex,
      segmentReadiness: segmentReadiness,
      colors: colors,
      activeSegmentKey: widget.activeSegmentKey,
      onSegmentTap: widget.onSegmentTap,
      isDarkMode: isDarkMode,
      // onSkipSegment: (index) => _handleSkipSegment(index),  // TODO: implement skip
    );
    
    return Stack(
      children: [
        // Faded book cover background
        if (showCoverBackground)
          Positioned.fill(
            child: Opacity(
              opacity: 0.04, // Very subtle, barely visible
              child: Image.file(
                io.File(widget.book.coverImagePath!),
                fit: BoxFit.cover,
                colorBlendMode: BlendMode.saturation,
                color: Colors.grey, // Desaturate the image
              ),
            ),
          ),
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            // Disable auto-scroll when user scrolls manually
            // UserScrollNotification is only sent for user-initiated scrolls, not programmatic ones
            if (notification is UserScrollNotification && widget.autoScrollEnabled) {
              widget.onAutoScrollDisabled();
            }
            return false;
          },
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
            child: RichText(
              // Key forces rebuild when readiness state changes
              key: ValueKey('richtext_${segmentReadiness.hashCode}_${widget.currentIndex}'),
              text: TextSpan(children: spans),
            ),
          ),
        ),
        
        // Jump to current button (bottom right) - shown when auto-scroll is disabled
        if (!widget.autoScrollEnabled)
          Positioned(
            bottom: 16,
            right: 16,
            child: _JumpToCurrentButton(
              onTap: widget.onJumpToCurrent,
            ),
          ),
      ],
    );
  }
}

/// Button to jump to current audio position.
class _JumpToCurrentButton extends StatelessWidget {
  const _JumpToCurrentButton({
    required this.onTap,
  });
  
  final VoidCallback onTap;
  
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    
    return Material(
      color: colors.primary,
      borderRadius: BorderRadius.circular(24),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.my_location, size: 18, color: colors.primaryForeground),
              const SizedBox(width: 8),
              Text(
                'Jump to Audio',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.primaryForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
