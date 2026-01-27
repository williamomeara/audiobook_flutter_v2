import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/chapter_synthesis_provider.dart';
import '../../app/database/database.dart';
import '../../app/library_controller.dart';
import '../../app/playback_providers.dart';
import '../../app/settings_controller.dart';
import '../theme/app_colors.dart';

/// Book progress state for determining UI presentation.
enum BookProgressState {
  /// Book has no listening progress (0%)
  notStarted,
  /// Book has some progress (1-99%)
  inProgress,
  /// Book is fully listened to (100%)
  complete,
}

/// Derive book progress state from chapter progress data.
BookProgressState deriveBookProgressState(
  Map<int, ChapterProgress?> chapterProgress,
  int totalChapters,
) {
  if (totalChapters == 0) return BookProgressState.notStarted;
  
  // Check if any chapter has been started
  final anyStarted = chapterProgress.values.any((p) => p?.hasStarted ?? false);
  if (!anyStarted) return BookProgressState.notStarted;
  
  // Check if all chapters are complete
  int completeCount = 0;
  for (int i = 0; i < totalChapters; i++) {
    if (chapterProgress[i]?.isComplete ?? false) {
      completeCount++;
    }
  }
  
  if (completeCount == totalChapters) return BookProgressState.complete;
  
  return BookProgressState.inProgress;
}

class BookDetailsScreen extends ConsumerStatefulWidget {
  const BookDetailsScreen({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends ConsumerState<BookDetailsScreen> {
  bool _showAllChapters = false;
  String _chapterSearchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  
  // Track which chapters we've already notified about
  final Set<int> _notifiedChapters = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final libraryAsync = ref.watch(libraryProvider);
    
    // Listen for synthesis completion events
    final allSynthState = ref.watch(chapterSynthesisProvider);
    _checkForCompletedSynthesis(allSynthState, context);

    return Scaffold(
      backgroundColor: colors.background,
      body: libraryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Text('Error loading book', style: TextStyle(color: colors.danger)),
        ),
        data: (library) {
          final book = library.books.where((b) => b.id == widget.bookId).firstOrNull;
          if (book == null) {
            return Center(
              child: Text('Book not found', style: TextStyle(color: colors.textSecondary)),
            );
          }

          // Watch per-segment listening progress for all chapters
          final chapterProgressAsync = ref.watch(bookChapterProgressProvider(book.id));
          final chapterProgressMap = chapterProgressAsync.when(
            data: (data) => data,
            loading: () => <int, ChapterProgress?>{},
            error: (_, __) => <int, ChapterProgress?>{},
          );

          final coverPath = book.coverImagePath;
          final chapters = book.chapters;
          
          // Derive book progress state from chapter progress data
          final bookProgressState = deriveBookProgressState(chapterProgressMap, chapters.length);
          final hasProgress = bookProgressState != BookProgressState.notStarted;
          
          // Calculate chapter-based progress based on COMPLETED chapters (not just current position)
          // This ensures marking future chapters as listened updates the progress bar
          int completedChaptersCount = 0;
          for (int i = 0; i < chapters.length; i++) {
            if (chapterProgressMap[i]?.isComplete ?? false) {
              completedChaptersCount++;
            }
          }
          final chapterProgress = chapters.isNotEmpty 
              ? completedChaptersCount / chapters.length 
              : 0.0;
          final chapterProgressPercent = (chapterProgress * 100).round();
          
          // Filter chapters by search query (for books with 10+ chapters)
          final hasSearch = chapters.length >= 10;
          List<dynamic> filteredChapters;
          if (hasSearch && _chapterSearchQuery.isNotEmpty) {
            final query = _chapterSearchQuery.toLowerCase();
            filteredChapters = chapters.where((ch) => 
              ch.title.toLowerCase().contains(query)
            ).toList();
          } else {
            filteredChapters = chapters;
          }
          
          // Apply show all/collapse logic (only when not actively searching)
          final displayedChapters = (_chapterSearchQuery.isNotEmpty || _showAllChapters) 
              ? filteredChapters 
              : filteredChapters.take(6).toList();

          return SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      _CircleButton(
                        icon: Icons.arrow_back,
                        onTap: () => context.pop(),
                      ),
                      const Spacer(),
                      Text(
                        'Book Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: colors.text,
                        ),
                      ),
                      const Spacer(),
                      _CircleButton(
                        icon: book.isFavorite ? Icons.favorite : Icons.favorite_border,
                        iconColor: book.isFavorite ? colors.primary : null,
                        onTap: () => ref.read(libraryProvider.notifier).toggleFavorite(book.id),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),

                        // Book info section
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Cover with progress badge and shadow
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 16,
                                        offset: const Offset(0, 8),
                                        spreadRadius: 0,
                                      ),
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: coverPath != null && File(coverPath).existsSync()
                                        ? Image.file(
                                            File(coverPath),
                                            width: 140,
                                            height: 200,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            width: 140,
                                            height: 200,
                                            color: colors.border,
                                            child: Icon(Icons.book, size: 48, color: colors.textTertiary),
                                          ),
                                  ),
                                ),
                                // Progress ring badge
                                if (hasProgress)
                                  Positioned(
                                    bottom: -12,
                                    right: -12,
                                    child: Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: colors.card,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.12),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          SizedBox(
                                            width: 40,
                                            height: 40,
                                            child: CircularProgressIndicator(
                                              value: chapterProgress,
                                              strokeWidth: 3,
                                              backgroundColor: colors.primary.withOpacity(0.15),
                                              color: colors.primary,
                                            ),
                                          ),
                                          // Show different icon/text based on completion state
                                          if (bookProgressState == BookProgressState.complete)
                                            Icon(Icons.check, size: 18, color: colors.primary)
                                          else
                                            Text(
                                              '$chapterProgressPercent%',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: colors.primary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 20),

                            // Book info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    book.title,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: colors.text,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    book.author,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: colors.textTertiary,
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Stats - Chapters count only (listening stats shown in Chapters section)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.menu_book, size: 16, color: colors.primary),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${book.chapters.length} Chapters',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: colors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Note: Listening progress stats moved to Chapters section header

                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Progress bar with chapter markers
                        if (hasProgress) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                bookProgressState == BookProgressState.complete 
                                    ? 'Complete' 
                                    : 'Reading Progress',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.textTertiary,
                                ),
                              ),
                              Text(
                                bookProgressState == BookProgressState.complete
                                    ? 'All ${book.chapters.length} chapters'
                                    : '$completedChaptersCount of ${book.chapters.length} chapters listened',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildProgressBarWithChapterMarkers(
                            // Use pre-calculated chapter-based progress
                            progress: chapterProgress,
                            chapterCount: book.chapters.length,
                            currentChapter: book.progress.chapterIndex,
                            chapterProgressMap: chapterProgressMap,
                            colors: colors,
                          ),
                          const SizedBox(height: 24),
                        ],

                        // About section in a card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'About',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _getBookDescription(book),
                                style: TextStyle(
                                  fontSize: 15,
                                  color: colors.text,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Action button with shadow
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: colors.primary.withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => context.push('/playback/${widget.bookId}'),
                              // Button icon and text based on book progress state
                              icon: Icon(switch (bookProgressState) {
                                BookProgressState.notStarted => Icons.play_circle_outline,
                                BookProgressState.inProgress => Icons.play_circle_fill,
                                BookProgressState.complete => Icons.replay,
                              }),
                              label: Text(
                                switch (bookProgressState) {
                                  BookProgressState.notStarted => 'Start Listening',
                                  BookProgressState.inProgress => 'Continue Listening',
                                  BookProgressState.complete => 'Listen Again',
                                },
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colors.primary,
                                foregroundColor: colors.primaryForeground,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ),
                        // Last played timestamp
                        _buildLastPlayedTimestamp(book.id, colors),
                        const SizedBox(height: 32),

                        // Chapters section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Chapters',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: colors.text,
                                  ),
                                ),
                                // Show synthesis status if any chapters are being prepared
                                if (_hasActiveSynthesis(allSynthState, book.id)) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colors.primary.withAlpha(25),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 10,
                                          height: 10,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: colors.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Preparing',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Row(
                              children: [
                                Icon(Icons.headphones, size: 16, color: colors.textTertiary),
                                const SizedBox(width: 4),
                                Text(
                                  '${_countListenedChapters(chapterProgressMap)}/${book.chapters.length} listened',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        
                        // Chapter search (for books with 10+ chapters)
                        if (hasSearch) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchController,
                            onChanged: (value) => setState(() => _chapterSearchQuery = value),
                            decoration: InputDecoration(
                              hintText: 'Search chapters...',
                              hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
                              prefixIcon: Icon(Icons.search, color: colors.textTertiary, size: 20),
                              suffixIcon: _chapterSearchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.clear, color: colors.textTertiary, size: 20),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _chapterSearchQuery = '');
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: colors.card,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              isDense: true,
                            ),
                            style: TextStyle(color: colors.text, fontSize: 14),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Chapter list
                        ...displayedChapters.map((chapter) {
                          // Get the original index from the full chapters list
                          final index = chapters.indexOf(chapter);
                          final isCurrentChapter = index == book.progress.chapterIndex;
                          
                          // Get per-segment listening progress for this chapter
                          // This is the single source of truth for chapter completion
                          final segmentProgress = chapterProgressMap[index];
                          final listenedPercent = segmentProgress?.percentComplete ?? 0.0;
                          final hasListeningProgress = segmentProgress?.hasStarted ?? false;
                          final isListeningComplete = segmentProgress?.isComplete ?? false;

                          // Watch synthesis state for this chapter
                          final synthKey = (bookId: book.id, chapterIndex: index);
                          final synthState = ref.watch(chapterSynthesisStateProvider(synthKey));
                          final isSynthesizing = synthState?.status == ChapterSynthesisStatus.synthesizing;
                          final isSynthComplete = synthState?.status == ChapterSynthesisStatus.complete;

                          return GestureDetector(
                            onTap: () {
                              // Only update progress if changing chapters
                              // If clicking the current chapter, preserve segment position
                              if (!isCurrentChapter) {
                                ref.read(libraryProvider.notifier).updateProgress(
                                  widget.bookId,
                                  index,
                                  0,
                                );
                              }
                              context.push('/playback/${widget.bookId}');
                            },
                            onLongPress: () => _showChapterMenu(
                              context,
                              book,
                              index,
                              chapter,
                              synthState,
                              segmentProgress,
                            ),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isCurrentChapter 
                                    ? colors.primary.withAlpha(15)
                                    : colors.card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isCurrentChapter 
                                      ? colors.primary.withAlpha(100)
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // "CONTINUE HERE" chip for current chapter
                                  if (isCurrentChapter && !isListeningComplete) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: colors.primary,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'CONTINUE HERE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: colors.primaryForeground,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                  Row(
                                    children: [
                                      // Chapter number badge - simplified styling
                                      // Priority: current chapter shows play, then completed shows check, else number
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: (isListeningComplete || isCurrentChapter)
                                              ? colors.primary
                                              : Colors.transparent,
                                          border: !(isListeningComplete || isCurrentChapter)
                                              ? Border.all(color: colors.border, width: 1.5)
                                              : null,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          // Current chapter always shows play icon
                                          child: isCurrentChapter
                                              ? Icon(Icons.play_arrow, size: 16, color: colors.primaryForeground)
                                              : isListeningComplete
                                                  ? Icon(Icons.check, size: 16, color: colors.primaryForeground)
                                                  : Text(
                                                      '${index + 1}',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w600,
                                                        color: colors.textSecondary,
                                                      ),
                                                    ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          chapter.title,
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: colors.text,
                                            fontWeight: isCurrentChapter ? FontWeight.w600 : FontWeight.normal,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      // Status indicators with duration
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Chapter duration (when available)
                                          if (segmentProgress != null && segmentProgress.durationMs > 0)
                                            Text(
                                              _formatChapterDuration(segmentProgress.duration),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: colors.textTertiary,
                                              ),
                                            ),
                                          if (segmentProgress != null && segmentProgress.durationMs > 0)
                                            const SizedBox(width: 8),
                                          // Status icon
                                          if (isSynthesizing)
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    value: synthState?.progress,
                                                    color: colors.primary,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '${synthState?.progressPercent ?? 0}%',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: colors.textTertiary,
                                                  ),
                                                ),
                                              ],
                                            )
                                          // Show cached indicator with completion checkmark if both
                                          else if (isSynthComplete)
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isListeningComplete) ...[
                                                  Icon(Icons.check_circle, size: 14, color: colors.primary),
                                                  const SizedBox(width: 4),
                                                ],
                                                Icon(Icons.cloud_done, size: 16, color: colors.accent),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Ready',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: colors.accent,
                                                  ),
                                                ),
                                              ],
                                            )
                                          else if (isListeningComplete)
                                            Icon(Icons.check_circle, size: 18, color: colors.primary)
                                          else if (hasListeningProgress)
                                            Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    value: listenedPercent,
                                                    backgroundColor: colors.border,
                                                    color: colors.primary,
                                                  ),
                                                ),
                                              ],
                                            )
                                          else
                                            Icon(Icons.circle_outlined, size: 18, color: colors.textTertiary),
                                        ],
                                      ),
                                    ],
                                  ),
                                  // Listening progress bar (per-segment)
                                  if (hasListeningProgress && !isListeningComplete) ...[
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 44),
                                      child: Container(
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: colors.background,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                        child: FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: listenedPercent,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: colors.primary,
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  // Synthesis progress bar
                                  if (isSynthesizing) ...[
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 44),
                                      child: Container(
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: colors.background,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                        child: FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: synthState?.progress ?? 0,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [colors.primary, colors.accent],
                                              ),
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),

                        // Show more/less button (hide when searching)
                        if (chapters.length > 6 && _chapterSearchQuery.isEmpty)
                          Center(
                            child: TextButton(
                              onPressed: () => setState(() => _showAllChapters = !_showAllChapters),
                              child: Text(
                                _showAllChapters
                                    ? 'Show Less'
                                    : 'Show All ${chapters.length} Chapters',
                                style: TextStyle(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        // Show "no results" when searching with no matches
                        if (_chapterSearchQuery.isNotEmpty && displayedChapters.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'No chapters matching "$_chapterSearchQuery"',
                                style: TextStyle(
                                  color: colors.textTertiary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Format chapter duration more compactly for the chapter list.
  String _formatChapterDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    
    if (hours > 0) {
      return '${hours}h${minutes > 0 ? ' ${minutes}m' : ''}';
    } else if (minutes > 0) {
      return '${minutes}m';
    } else {
      return '<1m';
    }
  }

  /// Build the "Last played X ago" widget.
  Widget _buildLastPlayedTimestamp(String bookId, AppThemeColors colors) {
    final lastPlayedAsync = ref.watch(lastPlayedAtProvider(bookId));
    
    return lastPlayedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (lastPlayed) {
        if (lastPlayed == null) return const SizedBox.shrink();
        
        final relativeTime = _formatRelativeTime(lastPlayed);
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 14, color: colors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  'Last played $relativeTime',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Format a DateTime as a relative time string.
  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    
    if (diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inMinutes < 60) {
      final mins = diff.inMinutes;
      return '$mins ${mins == 1 ? 'minute' : 'minutes'} ago';
    } else if (diff.inHours < 24) {
      final hours = diff.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (diff.inDays < 7) {
      final days = diff.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    } else if (diff.inDays < 30) {
      final weeks = diff.inDays ~/ 7;
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else if (diff.inDays < 365) {
      final months = diff.inDays ~/ 30;
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else {
      final years = diff.inDays ~/ 365;
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    }
  }

  /// Build progress bar with chapter tick marks.
  /// Shows individual segments for each completed chapter, allowing non-contiguous
  /// completion (e.g., chapters 1, 2, and 5 are complete but 3, 4 are not).
  Widget _buildProgressBarWithChapterMarkers({
    required double progress, // Not used for fill anymore, kept for API compatibility
    required int chapterCount,
    required int currentChapter,
    required Map<int, ChapterProgress?> chapterProgressMap,
    required AppThemeColors colors,
  }) {
    // Don't show markers for very few chapters or too many (would be cluttered)
    final showMarkers = chapterCount >= 3 && chapterCount <= 50;
    
    return SizedBox(
      height: 16, // Extra height for markers
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final chapterWidth = width / chapterCount;
          
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Background track
              Positioned(
                top: 4,
                left: 0,
                right: 0,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              // Per-chapter fill segments (allows non-contiguous completion)
              ...List.generate(chapterCount, (index) {
                final isComplete = chapterProgressMap[index]?.isComplete ?? false;
                if (!isComplete) return const SizedBox.shrink();
                
                final segmentStart = index * chapterWidth;
                // First segment needs left rounded corner, last needs right
                final isFirst = index == 0;
                final isLast = index == chapterCount - 1;
                // Check if adjacent segments are also complete for corner radius
                final prevComplete = index > 0 && (chapterProgressMap[index - 1]?.isComplete ?? false);
                final nextComplete = index < chapterCount - 1 && (chapterProgressMap[index + 1]?.isComplete ?? false);
                
                return Positioned(
                  top: 4,
                  left: segmentStart,
                  child: Container(
                    width: chapterWidth,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.horizontal(
                        left: (isFirst || !prevComplete) ? const Radius.circular(4) : Radius.zero,
                        right: (isLast || !nextComplete) ? const Radius.circular(4) : Radius.zero,
                      ),
                    ),
                  ),
                );
              }),
              // Chapter markers (evenly spaced dividers between chapters)
              if (showMarkers)
                ...List.generate(chapterCount - 1, (index) {
                  final markerPosition = (index + 1) / chapterCount;
                  // Marker is "complete" if the chapter to its LEFT is complete
                  final isChapterComplete = chapterProgressMap[index]?.isComplete ?? false;
                  return Positioned(
                    top: 2,
                    left: (width * markerPosition) - 1,
                    child: Container(
                      width: 2,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isChapterComplete 
                            ? colors.primaryForeground.withAlpha(150)
                            : colors.border,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  String _getBookDescription(book) {
    // Generate a brief description from the first chapter content
    if (book.chapters.isNotEmpty) {
      final content = book.chapters.first.content;
      if (content.length > 150) {
        return '${content.substring(0, 150).trim()}...';
      }
      return content;
    }
    return 'No description available.';
  }

  int _countListenedChapters(Map<int, ChapterProgress?> progressMap) {
    return progressMap.values.where((p) => p?.isComplete ?? false).length;
  }

  /// Check if any chapters for this book are currently being synthesized.
  bool _hasActiveSynthesis(AllChapterSynthesisState allSynthState, String bookId) {
    return allSynthState.jobs.entries.any((e) =>
        e.key.bookId == bookId && e.value.status == ChapterSynthesisStatus.synthesizing);
  }

  /// Check for newly completed synthesis jobs and show notification.
  void _checkForCompletedSynthesis(AllChapterSynthesisState allSynthState, BuildContext context) {
    // Only check jobs for the current book
    for (final entry in allSynthState.jobs.entries) {
      final key = entry.key;
      final state = entry.value;
      
      if (key.bookId != widget.bookId) continue;
      
      // Check if this chapter just completed and we haven't notified yet
      if (state.status == ChapterSynthesisStatus.complete && 
          !_notifiedChapters.contains(key.chapterIndex)) {
        _notifiedChapters.add(key.chapterIndex);
        
        // Show notification using post-frame callback to avoid build conflicts
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Chapter ${key.chapterIndex + 1} ready for offline playback'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Play',
                onPressed: () {
                  ref.read(libraryProvider.notifier).updateProgress(
                    widget.bookId,
                    key.chapterIndex,
                    0,
                  );
                  context.push('/playback/${widget.bookId}');
                },
              ),
            ),
          );
        });
      }
    }
  }

  void _showChapterMenu(
    BuildContext context,
    dynamic book,
    int chapterIndex,
    dynamic chapter,
    ChapterSynthesisState? synthState,
    ChapterProgress? chapterProgress,
  ) {
    final colors = context.appColors;
    final isSynthesizing = synthState?.status == ChapterSynthesisStatus.synthesizing;
    final isListeningComplete = chapterProgress?.isComplete ?? false;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withAlpha(77),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              
              // Chapter title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  chapter.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              
              // Prepare chapter option
              if (isSynthesizing)
                ListTile(
                  leading: Icon(Icons.stop_circle_outlined, color: colors.danger),
                  title: Text(
                    'Cancel Preparation',
                    style: TextStyle(color: colors.text),
                  ),
                  subtitle: Text(
                    '${synthState?.progressPercent ?? 0}% complete',
                    style: TextStyle(color: colors.textTertiary),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(chapterSynthesisProvider.notifier).cancelSynthesis(
                      book.id,
                      chapterIndex,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Cancelled preparation')),
                    );
                  },
                )
              else
                ListTile(
                  leading: Icon(Icons.cloud_download_outlined, color: colors.primary),
                  title: Text(
                    'Prepare Chapter',
                    style: TextStyle(color: colors.text),
                  ),
                  subtitle: Text(
                    'Pre-synthesize for smooth playback',
                    style: TextStyle(color: colors.textTertiary),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _startChapterSynthesis(book, chapterIndex, chapter);
                  },
                ),
              
              // Mark as listened/unlistened (uses per-segment progress tracking)
              ListTile(
                leading: Icon(
                  isListeningComplete
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: colors.primary,
                ),
                title: Text(
                  isListeningComplete
                      ? 'Mark as Unlistened'
                      : 'Mark as Listened',
                  style: TextStyle(color: colors.text),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final dao = await ref.read(segmentProgressDaoProvider.future);
                  if (isListeningComplete) {
                    // Clear progress
                    await dao.clearChapterProgress(widget.bookId, chapterIndex);
                  } else {
                    // Get total segments count for this chapter
                    final segments = await ref.read(libraryProvider.notifier)
                        .getSegmentsForChapter(widget.bookId, chapterIndex);
                    if (segments.isNotEmpty) {
                      await dao.markChapterListened(widget.bookId, chapterIndex, segments.length);
                    }
                  }
                  // Invalidate the provider to refresh UI
                  ref.invalidate(bookChapterProgressProvider(widget.bookId));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startChapterSynthesis(dynamic book, int chapterIndex, dynamic chapter) async {
    // Capture context and scaffold messenger before async gaps
    final ctx = context;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Get the voice ID from settings
    final settings = ref.read(settingsProvider);
    final voiceId = settings.selectedVoice.isNotEmpty
        ? settings.selectedVoice
        : 'supertonic_m5';

    // Load pre-segmented content from SQLite (no runtime segmentation)
    final tracks = await _loadChapterTracks(book.id, chapterIndex);
    
    if (tracks.isEmpty) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('No content to synthesize')),
      );
      return;
    }

    // Show confirmation with estimate
    final estimate = ref.read(chapterSynthesisProvider.notifier).getEstimate(
      tracks: tracks,
      voiceId: voiceId,
    );

    final confirmed = await showDialog<bool>(
      // ignore: use_build_context_synchronously
      context: ctx,
      builder: (dialogCtx) {
        final colors = dialogCtx.appColors;
        return AlertDialog(
          backgroundColor: colors.card,
          title: Text(
            'Prepare Chapter?',
            style: TextStyle(color: colors.text),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will synthesize all audio for this chapter in the background.',
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 18, color: colors.textTertiary),
                  const SizedBox(width: 8),
                  Text(
                    estimate?.timeDisplay ?? 'Unknown',
                    style: TextStyle(color: colors.text),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.storage_outlined, size: 18, color: colors.textTertiary),
                  const SizedBox(width: 8),
                  Text(
                    estimate?.storageDisplay ?? 'Unknown',
                    style: TextStyle(color: colors.text),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text('Cancel', style: TextStyle(color: colors.textTertiary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text('Prepare', style: TextStyle(color: colors.primary)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    // Start synthesis
    ref.read(chapterSynthesisProvider.notifier).startSynthesis(
      bookId: book.id,
      chapterIndex: chapterIndex,
      tracks: tracks,
      voiceId: voiceId,
    );

    if (!mounted) return;
    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text('Preparing chapter...')),
    );
  }

  /// Load pre-segmented content from SQLite and convert to AudioTracks.
  Future<List<AudioTrack>> _loadChapterTracks(String bookId, int chapterIndex) async {
    final libraryController = ref.read(libraryProvider.notifier);
    final segments = await libraryController.getSegmentsForChapter(bookId, chapterIndex);

    return segments.map((segment) => AudioTrack(
      id: IdGenerator.audioTrackId(bookId, chapterIndex, segment.index),
      text: segment.text,
      chapterIndex: chapterIndex,
      segmentIndex: segment.index,
      estimatedDuration: segment.estimatedDuration,
    )).toList();
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.card,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: iconColor ?? colors.text),
      ),
    );
  }
}
