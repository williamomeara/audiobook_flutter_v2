import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/gutenberg/free_books_controller.dart';
import '../../app/gutenberg/gutenberg_import_controller.dart';
import '../../app/library_controller.dart';
import '../theme/app_colors.dart';

class FreeBooksScreen extends ConsumerStatefulWidget {
  const FreeBooksScreen({super.key});

  @override
  ConsumerState<FreeBooksScreen> createState() => _FreeBooksScreenState();
}

class _FreeBooksScreenState extends ConsumerState<FreeBooksScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    final state = ref.read(freeBooksProvider);
    if (state.isSearching) return;
    if (state.isTopLoading) return;

    final next = state.topNext;
    if (next == null || next.isEmpty) return;

    final pos = _scrollController.position;
    const thresholdPx = 320.0;
    if (pos.maxScrollExtent - pos.pixels <= thresholdPx) {
      ref.read(freeBooksProvider.notifier).loadMoreTopBooks();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(freeBooksProvider.notifier).setSearchQuery(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final browseState = ref.watch(freeBooksProvider);
    final importState = ref.watch(gutenbergImportProvider);
    final library = ref.watch(libraryProvider).value;

    final showingSearch = browseState.isSearching;
    final items = showingSearch ? browseState.searchResults : browseState.topBooks;
    final isLoading = showingSearch ? browseState.isSearchLoading : browseState.isTopLoading;
    final error = showingSearch ? browseState.searchError : browseState.topError;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      _CircleButton(
                        icon: Icons.arrow_back,
                        onTap: () => context.pop(),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Free books',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          color: colors.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

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
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Search Project Gutenberg...',
                              hintStyle: TextStyle(color: colors.textTertiary),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            style: TextStyle(color: colors.text, fontSize: 16),
                          ),
                        ),
                        if (_searchController.text.trim().isNotEmpty)
                          IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                              setState(() {});
                            },
                            icon: Icon(Icons.close, color: colors.textTertiary, size: 20),
                            tooltip: 'Clear search',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (error != null && error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(error, style: TextStyle(color: colors.danger)),
                    ),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      showingSearch ? 'Search results' : 'Top 100 (popular)',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),

            // Books list
            Expanded(
              child: isLoading && items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? Center(
                          child: Opacity(
                            opacity: 0.6,
                            child: Text(
                              showingSearch ? 'No results.' : 'Loading free books…',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount:
                              items.length + (showingSearch && browseState.searchNext != null ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (showingSearch && index == items.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: TextButton(
                                    onPressed: browseState.isSearchLoading
                                        ? null
                                        : () => ref
                                            .read(freeBooksProvider.notifier)
                                            .loadMoreSearchResults(),
                                    child: Text(
                                      browseState.isSearchLoading ? 'Loading…' : 'Load more',
                                      style: TextStyle(
                                        color: colors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }

                            final book = items[index];
                            final entry = importState.entryFor(book.id);
                            String? importedBookId;
                            if (library != null) {
                              for (final b in library.books) {
                                if (b.gutenbergId == book.id) {
                                  importedBookId = b.id;
                                  break;
                                }
                              }
                            }
                            final isImported =
                                importedBookId != null || entry.phase == GutenbergImportPhase.done;

                            final coverUrl = book.coverImageUrl;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colors.card,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: coverUrl == null || coverUrl.isEmpty
                                        ? Container(
                                            width: 80,
                                            height: 112,
                                            color: colors.border,
                                            child: Icon(Icons.book, color: colors.textTertiary),
                                          )
                                        : Image.network(
                                            coverUrl,
                                            width: 80,
                                            height: 112,
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, e, s) => Container(
                                              width: 80,
                                              height: 112,
                                              color: colors.border,
                                              child: Icon(Icons.book, color: colors.textTertiary),
                                            ),
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
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: colors.text,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          book.authorsDisplay,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: colors.textTertiary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Gutenberg #${book.id}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 100,
                                    child: Column(
                                      children: [
                                        if (entry.phase == GutenbergImportPhase.downloading)
                                          SizedBox(
                                            width: 60,
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: entry.progress,
                                                minHeight: 4,
                                                backgroundColor: colors.border,
                                                valueColor:
                                                    AlwaysStoppedAnimation<Color>(colors.primary),
                                              ),
                                            ),
                                          )
                                        else
                                          TextButton(
                                            onPressed: entry.isBusy
                                                ? null
                                                : () async {
                                                    if (isImported && importedBookId != null) {
                                                      if (!context.mounted) return;
                                                      context.push('/book/$importedBookId');
                                                      return;
                                                    }

                                                    final result = await ref
                                                        .read(gutenbergImportProvider.notifier)
                                                        .importBook(book);
                                                    if (!context.mounted) return;
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(content: Text(result.message)),
                                                    );
                                                  },
                                            child: Text(
                                              entry.isBusy
                                                  ? (entry.phase == GutenbergImportPhase.importing
                                                      ? 'Importing…'
                                                      : 'Downloading…')
                                                  : (isImported ? 'Open' : 'Import'),
                                              style: TextStyle(
                                                color: entry.isBusy
                                                    ? colors.textTertiary
                                                    : colors.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        if (entry.phase == GutenbergImportPhase.failed &&
                                            entry.message != null &&
                                            entry.message!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              entry.message!,
                                              style: TextStyle(
                                                color: colors.danger,
                                                fontSize: 10,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
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
