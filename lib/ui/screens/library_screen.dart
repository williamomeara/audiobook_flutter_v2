import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/library_controller.dart';
import '../theme/app_colors.dart';
import 'package:core_domain/core_domain.dart';

enum LibraryTab { all, favorites }
enum SortOption { recent, title, progress }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  bool _isImporting = false;
  LibraryTab _activeTab = LibraryTab.all;
  SortOption _sortBy = SortOption.recent;
  bool _showFilters = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final path = file.path;
    if (path == null || path.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access selected file.')),
        );
      }
      return;
    }

    setState(() => _isImporting = true);

    try {
      final bookId = await ref.read(libraryProvider.notifier).importBookFromPath(
            sourcePath: path,
            fileName: file.name,
          );
      final imported = ref.read(libraryProvider.notifier).getBook(bookId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "${imported?.title ?? file.name}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  List<Book> _filterAndSortBooks(List<Book> books) {
    final query = _searchController.text.trim().toLowerCase();
    
    var filtered = books.where((book) {
      final matchesSearch = query.isEmpty ||
          book.title.toLowerCase().contains(query) ||
          book.author.toLowerCase().contains(query);
      final matchesTab = _activeTab == LibraryTab.all || 
          (_activeTab == LibraryTab.favorites && book.isFavorite);
      return matchesSearch && matchesTab;
    }).toList();

    switch (_sortBy) {
      case SortOption.recent:
        filtered.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        break;
      case SortOption.title:
        filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case SortOption.progress:
        filtered.sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
        break;
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final libraryAsync = ref.watch(libraryProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: libraryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(
            child: Text('Failed to load library', style: TextStyle(color: colors.danger)),
          ),
          data: (library) {
            final books = _filterAndSortBooks(library.books);

            return Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // Settings button
                          _CircleButton(
                            icon: Icons.settings_outlined,
                            onTap: () => context.push('/settings'),
                          ),
                          const SizedBox(width: 16),
                          // App branding and screen title
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Éist',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textSecondary,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Text(
                                'Library',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w500,
                                  color: colors.text,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Filter button
                          _PillButton(
                            icon: Icons.tune,
                            label: 'Filter',
                            isActive: _showFilters,
                            onTap: () => setState(() => _showFilters = !_showFilters),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Tabs and action buttons row
                      Row(
                        children: [
                          // Tabs
                          _TabButton(
                            label: 'All',
                            isActive: _activeTab == LibraryTab.all,
                            onTap: () => setState(() => _activeTab = LibraryTab.all),
                          ),
                          const SizedBox(width: 16),
                          _TabButton(
                            label: 'Favorites',
                            isActive: _activeTab == LibraryTab.favorites,
                            onTap: () => setState(() => _activeTab = LibraryTab.favorites),
                          ),
                          const Spacer(),
                          // Action buttons
                          _ActionButton(
                            label: 'Free Books',
                            onTap: () => context.push('/free-books'),
                          ),
                          const SizedBox(width: 8),
                          _ActionButton(
                            label: 'Import',
                            isLoading: _isImporting,
                            onTap: _isImporting ? null : _handleImport,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Search bar
                      Container(
                        decoration: BoxDecoration(
                          color: colors.card,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.search, size: 20, color: colors.textTertiary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: 'Search library...',
                                  hintStyle: TextStyle(color: colors.textTertiary),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                style: TextStyle(color: colors.text, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Sort options (collapsible)
                      if (_showFilters) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sort by',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.textTertiary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                children: SortOption.values.map((option) {
                                  final isSelected = _sortBy == option;
                                  return GestureDetector(
                                    onTap: () => setState(() => _sortBy = option),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected ? colors.primary : colors.background,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        option.name[0].toUpperCase() + option.name.substring(1),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isSelected ? colors.primaryForeground : colors.textTertiary,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),

                // Book list
                Expanded(
                  child: books.isEmpty
                      ? Center(
                          child: Opacity(
                            opacity: 0.5,
                            child: Text(
                              _searchController.text.isNotEmpty
                                  ? 'No books match your search.'
                                  : _activeTab == LibraryTab.favorites
                                      ? 'No favorite books yet.'
                                      : 'No books yet. Import one!',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: books.length,
                          itemBuilder: (context, index) {
                            final book = books[index];
                            return _BookCard(
                              book: book,
                              onTap: () => context.push('/book/${book.id}'),
                              onToggleFavorite: () => ref.read(libraryProvider.notifier).toggleFavorite(book.id),
                              onDelete: () => ref.read(libraryProvider.notifier).removeBook(book.id),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

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
        child: Icon(icon, size: 20, color: colors.text),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? colors.primary : colors.card,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? colors.primaryForeground : colors.text,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isActive ? colors.primaryForeground : colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: isActive ? colors.primary : colors.textTertiary,
          fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(8),
        ),
        child: isLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textTertiary,
                ),
              ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  final Book book;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final coverPath = book.coverImagePath;
    final progress = book.progressPercent;
    final hasProgress = progress > 0;

    return GestureDetector(
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Container(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.textTertiary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Book Options',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                    ),
                    // Favorite option
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        onToggleFavorite();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        child: Row(
                          children: [
                            Icon(
                              book.isFavorite ? Icons.favorite : Icons.favorite_border,
                              color: book.isFavorite ? colors.primary : colors.text,
                              size: 22,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                book.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: colors.text,
                                ),
                              ),
                            ),
                            if (book.isFavorite)
                              Icon(Icons.check_circle, color: colors.primary, size: 20),
                          ],
                        ),
                      ),
                    ),
                    // Delete option
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        onDelete();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              color: colors.danger,
                              size: 22,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                'Remove from Library',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: colors.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              // Cover with progress bar
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: coverPath != null && File(coverPath).existsSync()
                        ? Image.file(
                            File(coverPath),
                            width: 80,
                            height: 112,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 80,
                            height: 112,
                            color: colors.border,
                            child: Icon(Icons.book, color: colors.textTertiary),
                          ),
                  ),
                  // Progress bar at bottom of cover
                  if (hasProgress)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress / 100,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(8),
                                bottomRight: Radius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),

              // Book info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and favorite icon
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            book.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: colors.text,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (book.isFavorite) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.favorite,
                            size: 16,
                            color: colors.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.author,
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Chapter count and progress
                    Row(
                      children: [
                        Text(
                          '${book.chapters.length} Chapters',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textTertiary,
                          ),
                        ),
                        if (hasProgress) ...[
                          Text(
                            ' • ',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textTertiary,
                            ),
                          ),
                          Text(
                            '$progress% Complete',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Continue listening indicator
                    if (hasProgress) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Continue Listening • Chapter ${book.progress.chapterIndex + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Chevron
              Icon(Icons.chevron_right, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
