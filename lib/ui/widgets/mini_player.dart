import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/playback/playback.dart';
import '../../app/playback_providers.dart';
import '../../app/library_controller.dart';
import '../theme/app_colors.dart';

/// A compact, persistent mini-player that appears at the bottom of screens.
///
/// Shows book cover, title, current segment, and play/pause button.
/// Tap to navigate to full playback screen.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(playbackViewProvider);
    final libraryAsync = ref.watch(libraryProvider);
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    // Don't show if no active playback
    if (!viewState.showMiniPlayerGlobally) {
      return const SizedBox.shrink();
    }

    // Get the playing book ID
    final bookId = viewState.playingBookId;
    if (bookId == null) {
      return const SizedBox.shrink();
    }

    return libraryAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (library) {
        final book = library.books.where((b) => b.id == bookId).firstOrNull;
        if (book == null) return const SizedBox.shrink();

        // Get current segment info from playback state
        final playbackState = ref.watch(playbackStateProvider);
        final currentIndex = playbackState.currentIndex;
        final queueLength = playbackState.queue.length;

        // Get bottom safe area padding for system navigation bar
        final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

        return GestureDetector(
          onTap: () => context.push('/playback/$bookId'),
          child: Container(
            padding: EdgeInsets.only(bottom: bottomPadding),
            decoration: BoxDecoration(
              color: colors.background,
              border: Border(
                top: BorderSide(color: colors.border, width: 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // Book cover thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: book.coverImagePath != null &&
                                File(book.coverImagePath!).existsSync()
                            ? Image.file(File(book.coverImagePath!),
                                fit: BoxFit.cover)
                            : Container(
                                color: colors.primary.withOpacity(0.1),
                                child: Icon(Icons.book, color: colors.primary),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Title and progress
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.text,
                              decoration: TextDecoration.none,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            queueLength > 0
                                ? 'Segment ${currentIndex + 1}/$queueLength'
                                : 'Loading...',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Play/Pause button
                    Semantics(
                      button: true,
                      enabled: true,
                      label: viewState.isPlaying ? 'Pause' : 'Play',
                      tooltip: viewState.isPlaying
                          ? 'Pause playback'
                          : 'Play audiobook',
                      onTap: () {
                        ref
                            .read(playbackViewProvider.notifier)
                            .togglePlayPause();
                      },
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            ref
                                .read(playbackViewProvider.notifier)
                                .togglePlayPause();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              viewState.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              size: 28,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
