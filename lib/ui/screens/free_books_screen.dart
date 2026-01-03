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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(Icons.chevron_left, color: colors.text),
                  ),
                  Text(
                    'Free books',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.border, width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 20, color: colors.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Search Project Gutenberg…',
                          hintStyle: TextStyle(color: colors.textTertiary),
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
                        icon: Icon(Icons.close, color: colors.textTertiary),
                        tooltip: 'Clear search',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (error != null && error.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(error, style: TextStyle(color: colors.danger)),
                ),
                const SizedBox(height: 8),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  showingSearch ? 'Search results' : 'Top 100 (popular)',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: colors.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: colors.border, width: 1),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: coverUrl == null || coverUrl.isEmpty
                                          ? Container(
                                              width: 64,
                                              height: 96,
                                              color: colors.border,
                                              child: Icon(Icons.book, color: colors.textTertiary),
                                            )
                                          : Image.network(
                                              coverUrl,
                                              width: 64,
                                              height: 96,
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) => Container(
                                                width: 64,
                                                height: 96,
                                                color: colors.border,
                                                child: Icon(Icons.book, color: colors.textTertiary),
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            book.title,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: colors.text,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            book.authorsDisplay,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: colors.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Gutenberg #${book.id}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: colors.textTertiary,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              if (entry.phase == GutenbergImportPhase.downloading)
                                                Expanded(
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(999),
                                                    child: LinearProgressIndicator(
                                                      value: entry.progress,
                                                      minHeight: 6,
                                                      backgroundColor: colors.border,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<Color>(colors.primary),
                                                    ),
                                                  ),
                                                )
                                              else
                                                const Expanded(child: SizedBox.shrink()),
                                              const SizedBox(width: 12),
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
                                                        if (result.ok && result.bookId != null) {
                                                          context.push('/book/${result.bookId}');
                                                        }
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
                                            ],
                                          ),
                                          if (entry.phase == GutenbergImportPhase.failed &&
                                              entry.message != null &&
                                              entry.message!.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              entry.message!,
                                              style: TextStyle(
                                                color: colors.danger,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
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
      ),
    );
  }
}
