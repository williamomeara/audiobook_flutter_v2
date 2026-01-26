import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/chapter_synthesis_provider.dart';
import '../../app/library_controller.dart';
import '../../app/settings_controller.dart';
import '../theme/app_colors.dart';

class BookDetailsScreen extends ConsumerStatefulWidget {
  const BookDetailsScreen({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends ConsumerState<BookDetailsScreen> {
  bool _showAllChapters = false;
  
  // Track which chapters we've already notified about
  final Set<int> _notifiedChapters = {};

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

          final coverPath = book.coverImagePath;
          final progress = book.progressPercent;
          final hasProgress = progress > 0;
          final chapters = book.chapters;
          final displayedChapters = _showAllChapters ? chapters : chapters.take(6).toList();

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
                            // Cover with progress badge
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
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
                                // Progress badge
                                if (hasProgress)
                                  Positioned(
                                    bottom: -8,
                                    left: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: colors.card,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '$progress%',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: colors.primary,
                                        ),
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

                                  // Stats
                                  Row(
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
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.access_time, size: 16, color: colors.primary),
                                      const SizedBox(width: 6),
                                      Text(
                                        _estimateReadingTime(book.chapters),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: colors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),

                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Progress bar
                        if (hasProgress) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Reading Progress',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.textTertiary,
                                ),
                              ),
                              Text(
                                'Chapter ${book.progress.chapterIndex + 1} of ${book.chapters.length}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: colors.card,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress / 100,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [colors.primary, colors.accent],
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // About section
                        Text(
                          'About this book',
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getBookDescription(book),
                          style: TextStyle(
                            fontSize: 15,
                            color: colors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Action button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => context.push('/playback/${widget.bookId}'),
                            icon: const Icon(Icons.menu_book),
                            label: Text(
                              hasProgress ? 'Continue Listening' : 'Start Listening',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: colors.primaryForeground,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

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
                                Icon(Icons.visibility, size: 16, color: colors.textTertiary),
                                const SizedBox(width: 4),
                                Text(
                                  '${_countReadChapters(book)} read',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Chapter list
                        ...displayedChapters.asMap().entries.map((entry) {
                          final index = entry.key;
                          final chapter = entry.value;
                          final isCurrentChapter = index == book.progress.chapterIndex;
                          final isRead = book.completedChapters.contains(index);
                          final isInProgress = isCurrentChapter && book.progress.segmentIndex > 0;
                          final chapterProgress = isInProgress
                              ? (book.progress.segmentIndex / 10 * 100).clamp(0, 99).round()
                              : null;

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
                            ),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colors.card,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      // Chapter number badge
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: isRead
                                              ? colors.primary
                                              : isSynthComplete
                                                  ? colors.accent
                                                  : isInProgress
                                                      ? colors.primary.withAlpha(128)
                                                      : colors.background,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: isSynthComplete 
                                              ? Icon(Icons.check, size: 16, color: colors.primaryForeground)
                                              : Text(
                                                  '${index + 1}',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: isRead || isInProgress || isSynthComplete
                                                        ? colors.primaryForeground
                                                        : colors.textTertiary,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          chapter.title,
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: colors.text,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      // Status indicators
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
                                      else if (isSynthComplete)
                                        Text(
                                          'Ready',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.accent,
                                          ),
                                        )
                                      else if (isRead)
                                        Text(
                                          '✓ Read',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.primary,
                                          ),
                                        )
                                      else if (isInProgress)
                                        Text(
                                          'In Progress',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.textTertiary,
                                          ),
                                        ),
                                    ],
                                  ),
                                  // Progress bar for current chapter
                                  if (chapterProgress != null && chapterProgress > 0) ...[
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
                                          widthFactor: chapterProgress / 100,
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

                        // Show more/less button
                        if (chapters.length > 6)
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

  String _estimateReadingTime(List chapters) {
    // Rough estimate: 150 words per minute, average 200 words per minute for TTS
    final totalChars = chapters.fold<int>(0, (sum, ch) => sum + (ch.content.length as int));
    final totalMinutes = (totalChars / 5 / 150).round(); // 5 chars per word, 150 wpm
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
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

  int _countReadChapters(book) {
    return book.completedChapters.length;
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
  ) {
    final colors = context.appColors;
    final isSynthesizing = synthState?.status == ChapterSynthesisStatus.synthesizing;
    
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
              
              // Mark as read/unread
              ListTile(
                leading: Icon(
                  book.completedChapters.contains(chapterIndex)
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: colors.primary,
                ),
                title: Text(
                  book.completedChapters.contains(chapterIndex)
                      ? 'Mark as Unread'
                      : 'Mark as Read',
                  style: TextStyle(color: colors.text),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(libraryProvider.notifier).toggleChapterComplete(
                    widget.bookId,
                    chapterIndex,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startChapterSynthesis(dynamic book, int chapterIndex, dynamic chapter) async {
    // Get the voice ID from settings
    final settings = ref.read(settingsProvider);
    final voiceId = settings.selectedVoice.isNotEmpty 
        ? settings.selectedVoice 
        : 'supertonic_m5';
    
    // Parse chapter content to tracks
    final tracks = _parseChapterToTracks(book.id, chapterIndex, chapter.content);
    
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
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
      context: context,
      builder: (ctx) {
        final colors = context.appColors;
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
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: colors.textTertiary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Preparing chapter...')),
    );
  }

  List<AudioTrack> _parseChapterToTracks(String bookId, int chapterIndex, String content) {
    // Use the same segmentation as playback_providers.dart to ensure
    // cache keys match when synthesizing audio
    final segments = segmentText(content);
    
    return segments.asMap().entries.map((e) => AudioTrack(
      id: IdGenerator.audioTrackId(bookId, chapterIndex, e.key),
      text: e.value.text,
      chapterIndex: chapterIndex,
      segmentIndex: e.key,
      estimatedDuration: e.value.estimatedDuration,
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
