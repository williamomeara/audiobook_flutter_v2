import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/library_controller.dart';
import '../theme/app_colors.dart';

class BookDetailsScreen extends ConsumerWidget {
  const BookDetailsScreen({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          final book = library.books.where((b) => b.id == bookId).firstOrNull;
          if (book == null) {
            return Center(
              child: Text('Book not found', style: TextStyle(color: colors.textSecondary)),
            );
          }

          final coverPath = book.coverImagePath;

          return SafeArea(
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.headerBackground,
                    border: Border(bottom: BorderSide(color: colors.border, width: 1)),
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => context.pop(),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(Icons.chevron_left, color: colors.text),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Book Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cover and title
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: coverPath != null && File(coverPath).existsSync()
                                  ? Image.file(
                                      File(coverPath),
                                      width: 120,
                                      height: 180,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      width: 120,
                                      height: 180,
                                      color: colors.border,
                                      child: Icon(Icons.book, size: 48, color: colors.textTertiary),
                                    ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    book.title,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: colors.text,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    book.author,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${book.chapters.length} Chapters',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Play button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => context.push('/playback/$bookId'),
                            icon: const Icon(Icons.play_arrow),
                            label: Text(
                              book.progress.chapterIndex > 0 || book.progress.segmentIndex > 0
                                  ? 'Continue Reading'
                                  : 'Start Reading',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: colors.primaryForeground,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Chapters
                        Text(
                          'Chapters',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: colors.text,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...book.chapters.asMap().entries.map((entry) {
                          final index = entry.key;
                          final chapter = entry.value;
                          final isCurrentChapter = index == book.progress.chapterIndex;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isCurrentChapter ? colors.chapterItemBg : colors.card,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isCurrentChapter ? colors.primary : colors.border,
                                width: 1,
                              ),
                            ),
                            child: ListTile(
                              title: Text(
                                chapter.title,
                                style: TextStyle(
                                  color: colors.text,
                                  fontWeight: isCurrentChapter ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                              trailing: isCurrentChapter
                                  ? Icon(Icons.play_circle, color: colors.primary)
                                  : null,
                              onTap: () {
                                ref.read(libraryProvider.notifier).updateProgress(
                                  bookId,
                                  index,
                                  0,
                                );
                                context.push('/playback/$bookId');
                              },
                            ),
                          );
                        }),
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
}
