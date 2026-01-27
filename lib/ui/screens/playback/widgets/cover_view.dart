import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:core_domain/core_domain.dart';

import '../../../theme/app_colors.dart';

/// Cover view widget showing the book cover, title, and author.
/// Used in the playback screen when the user toggles to cover mode.
class CoverView extends StatelessWidget {
  const CoverView({
    super.key,
    required this.book,
  });

  final Book book;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Book cover
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 240,
                  maxHeight: 360,
                ),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: book.coverImagePath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              io.File(book.coverImagePath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _CoverPlaceholder(book: book),
                            ),
                          )
                        : _CoverPlaceholder(book: book),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                book.title,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: colors.text),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'By ${book.author}',
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder widget when no cover image is available.
class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary.withValues(alpha: 0.3), colors.primary.withValues(alpha: 0.1)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.book, size: 64, color: colors.primary),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                book.title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.text),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
