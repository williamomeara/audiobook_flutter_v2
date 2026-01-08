import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/library_controller.dart';
import '../theme/app_colors.dart';

class BookDetailsScreen extends ConsumerStatefulWidget {
  const BookDetailsScreen({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends ConsumerState<BookDetailsScreen> {
  bool _showAllChapters = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final libraryAsync = ref.watch(libraryProvider);

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
                                  const SizedBox(height: 12),

                                  // Genre tag
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: colors.card,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Fiction',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textTertiary,
                                      ),
                                    ),
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
                            Text(
                              'Chapters',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: colors.text,
                              ),
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
                          final isRead = index < book.progress.chapterIndex;
                          final chapterProgress = isCurrentChapter && book.progress.segmentIndex > 0
                              ? (book.progress.segmentIndex / 10 * 100).clamp(0, 99).round()
                              : null;

                          return GestureDetector(
                            onTap: () {
                              ref.read(libraryProvider.notifier).updateProgress(
                                widget.bookId,
                                index,
                                0,
                              );
                              context.push('/playback/${widget.bookId}');
                            },
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
                                          color: isRead || isCurrentChapter
                                              ? colors.primary
                                              : colors.background,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${index + 1}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: isRead || isCurrentChapter
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
                                      if (isRead)
                                        Text(
                                          '✓ Read',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.primary,
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
    return book.progress.chapterIndex;
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
