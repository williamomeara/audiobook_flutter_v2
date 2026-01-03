import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infra/gutendex/gutendex_models.dart';
import 'gutendex_providers.dart';

class FreeBooksState {
  const FreeBooksState({
    required this.topBooks,
    required this.isTopLoading,
    required this.topError,
    required this.topNext,
    required this.searchQuery,
    required this.searchResults,
    required this.isSearchLoading,
    required this.searchError,
    required this.searchNext,
  });

  final List<GutendexBook> topBooks;
  final bool isTopLoading;
  final String? topError;
  final String? topNext;

  final String searchQuery;
  final List<GutendexBook> searchResults;
  final bool isSearchLoading;
  final String? searchError;
  final String? searchNext;

  bool get isSearching => searchQuery.trim().isNotEmpty;

  FreeBooksState copyWith({
    List<GutendexBook>? topBooks,
    bool? isTopLoading,
    String? topError,
    String? topNext,
    String? searchQuery,
    List<GutendexBook>? searchResults,
    bool? isSearchLoading,
    String? searchError,
    String? searchNext,
  }) {
    return FreeBooksState(
      topBooks: topBooks ?? this.topBooks,
      isTopLoading: isTopLoading ?? this.isTopLoading,
      topError: topError,
      topNext: topNext,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
      isSearchLoading: isSearchLoading ?? this.isSearchLoading,
      searchError: searchError,
      searchNext: searchNext,
    );
  }

  static const initial = FreeBooksState(
    topBooks: <GutendexBook>[],
    isTopLoading: false,
    topError: null,
    topNext: null,
    searchQuery: '',
    searchResults: <GutendexBook>[],
    isSearchLoading: false,
    searchError: null,
    searchNext: null,
  );
}

class FreeBooksController extends Notifier<FreeBooksState> {
  int _searchRequestId = 0;
  int _topRequestId = 0;

  static const int _topTargetCount = 100;

  @override
  FreeBooksState build() {
    Future.microtask(loadInitialTop);
    return FreeBooksState.initial;
  }

  Future<void> loadInitialTop() async {
    if (state.isTopLoading) return;
    if (state.topBooks.isNotEmpty) return;

    final requestId = ++_topRequestId;
    state = state.copyWith(isTopLoading: true, topError: null, topNext: null);

    try {
      final client = ref.read(gutendexClientProvider);
      final page = await client.fetchTopEpubBooksPage(page: 1);
      if (requestId != _topRequestId) return;

      final results = page.results.where((b) => b.epubUrl != null).toList();
      final capped = results.length > _topTargetCount
          ? results.sublist(0, _topTargetCount)
          : results;
      final next = capped.length >= _topTargetCount ? null : page.next;

      state = state.copyWith(
        topBooks: List<GutendexBook>.unmodifiable(capped),
        isTopLoading: false,
        topError: null,
        topNext: next,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('FreeBooks: loadInitialTop failed: $e');
      state = state.copyWith(
        isTopLoading: false,
        topError: 'Failed to load free books',
        topNext: null,
      );
    }
  }

  Future<void> loadMoreTopBooks() async {
    if (state.isTopLoading) return;
    if (state.topBooks.length >= _topTargetCount) return;

    final nextUrl = state.topNext;
    if (nextUrl == null || nextUrl.isEmpty) return;

    final requestId = _topRequestId;
    state = state.copyWith(isTopLoading: true, topError: null);

    try {
      final client = ref.read(gutendexClientProvider);
      final page = await client.fetchByUrl(nextUrl);
      if (requestId != _topRequestId) return;

      final more = page.results.where((b) => b.epubUrl != null).toList();
      final combined = <GutendexBook>[...state.topBooks, ...more];
      final capped = combined.length > _topTargetCount
          ? combined.sublist(0, _topTargetCount)
          : combined;

      state = state.copyWith(
        topBooks: List<GutendexBook>.unmodifiable(capped),
        isTopLoading: false,
        topError: null,
        topNext: capped.length >= _topTargetCount ? null : page.next,
      );
    } catch (e) {
      if (requestId != _topRequestId) return;
      if (kDebugMode) debugPrint('FreeBooks: loadMoreTopBooks failed: $e');
      state = state.copyWith(
        isTopLoading: false,
        topError: 'Failed to load more free books',
      );
    }
  }

  Future<void> setSearchQuery(String query) async {
    final q = query.trim();

    if (q.isEmpty) {
      _searchRequestId += 1;
      state = state.copyWith(
        searchQuery: '',
        searchResults: const <GutendexBook>[],
        isSearchLoading: false,
        searchError: null,
        searchNext: null,
      );
      return;
    }

    final requestId = ++_searchRequestId;
    state = state.copyWith(
      searchQuery: q,
      searchResults: const <GutendexBook>[],
      isSearchLoading: true,
      searchError: null,
      searchNext: null,
    );

    try {
      final client = ref.read(gutendexClientProvider);
      final page = await client.searchEpubBooks(query: q);
      if (requestId != _searchRequestId) return;

      final results = page.results.where((b) => b.epubUrl != null).toList();
      state = state.copyWith(
        searchResults: List<GutendexBook>.unmodifiable(results),
        isSearchLoading: false,
        searchError: null,
        searchNext: page.next,
      );
    } catch (e) {
      if (requestId != _searchRequestId) return;
      if (kDebugMode) debugPrint('FreeBooks: search failed: $e');
      state = state.copyWith(
        isSearchLoading: false,
        searchError: 'Search failed',
        searchNext: null,
      );
    }
  }

  Future<void> loadMoreSearchResults() async {
    final next = state.searchNext;
    if (next == null || next.isEmpty) return;
    if (state.isSearchLoading) return;

    final requestId = _searchRequestId;
    state = state.copyWith(isSearchLoading: true, searchError: null);

    try {
      final client = ref.read(gutendexClientProvider);
      final page = await client.fetchByUrl(next);
      if (requestId != _searchRequestId) return;

      final more = page.results.where((b) => b.epubUrl != null).toList();
      state = state.copyWith(
        searchResults: List<GutendexBook>.unmodifiable(<GutendexBook>[
          ...state.searchResults,
          ...more,
        ]),
        isSearchLoading: false,
        searchError: null,
        searchNext: page.next,
      );
    } catch (e) {
      if (requestId != _searchRequestId) return;
      if (kDebugMode) debugPrint('FreeBooks: loadMoreSearchResults failed: $e');
      state = state.copyWith(
        isSearchLoading: false,
        searchError: 'Failed to load more results',
      );
    }
  }
}

final freeBooksProvider = NotifierProvider<FreeBooksController, FreeBooksState>(
  FreeBooksController.new,
);
