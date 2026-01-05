import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playback/playback.dart';

import '../../app/library_controller.dart';
import '../../app/playback_providers.dart';
import '../theme/app_colors.dart';
import 'package:core_domain/core_domain.dart';

class PlaybackScreen extends ConsumerStatefulWidget {
  const PlaybackScreen({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends ConsumerState<PlaybackScreen> {
  bool _initialized = false;
  int _currentChapterIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePlayback();
    });
  }

  Future<void> _initializePlayback() async {
    if (_initialized) return;

    // Wait for library to be available
    final libraryAsync = ref.read(libraryProvider);
    LibraryState? library;
    
    if (libraryAsync.hasValue) {
      library = libraryAsync.value;
    } else if (libraryAsync.isLoading) {
      // Wait for library to load
      library = await ref.read(libraryProvider.future);
    }
    
    if (library == null) return;
    
    _initialized = true;

    final book = library.books.where((b) => b.id == widget.bookId).firstOrNull;
    if (book == null) return;

    final chapterIndex = book.progress.chapterIndex.clamp(0, book.chapters.length - 1);
    final segmentIndex = book.progress.segmentIndex;

    _currentChapterIndex = chapterIndex;

    final notifier = ref.read(playbackControllerProvider.notifier);
    await notifier.loadChapter(
      book: book,
      chapterIndex: chapterIndex,
      startSegmentIndex: segmentIndex,
      autoPlay: false,
    );
  }

  Future<void> _togglePlay() async {
    final notifier = ref.read(playbackControllerProvider.notifier);
    final state = ref.read(playbackStateProvider);

    if (state.isPlaying) {
      await notifier.pause();
    } else {
      await notifier.play();
    }
  }

  Future<void> _nextSegment() async {
    await ref.read(playbackControllerProvider.notifier).nextTrack();
  }

  Future<void> _previousSegment() async {
    await ref.read(playbackControllerProvider.notifier).previousTrack();
  }

  Future<void> _nextChapter() async {
    final library = ref.read(libraryProvider).value;
    if (library == null) return;

    final book = library.books.where((b) => b.id == widget.bookId).firstOrNull;
    if (book == null) return;

    final currentChapterIndex = _currentChapterIndex;
    if (currentChapterIndex >= book.chapters.length - 1) return;

    final newChapterIndex = currentChapterIndex + 1;
    setState(() => _currentChapterIndex = newChapterIndex);

    await ref.read(playbackControllerProvider.notifier).loadChapter(
      book: book,
      chapterIndex: newChapterIndex,
      startSegmentIndex: 0,
      autoPlay: ref.read(playbackStateProvider).isPlaying,
    );
  }

  Future<void> _previousChapter() async {
    final library = ref.read(libraryProvider).value;
    if (library == null) return;

    final book = library.books.where((b) => b.id == widget.bookId).firstOrNull;
    if (book == null) return;

    final currentChapterIndex = _currentChapterIndex;
    if (currentChapterIndex <= 0) return;

    final newChapterIndex = currentChapterIndex - 1;
    setState(() => _currentChapterIndex = newChapterIndex);

    await ref.read(playbackControllerProvider.notifier).loadChapter(
      book: book,
      chapterIndex: newChapterIndex,
      startSegmentIndex: 0,
      autoPlay: ref.read(playbackStateProvider).isPlaying,
    );
  }

  Future<void> _setPlaybackRate(double rate) async {
    await ref.read(playbackControllerProvider.notifier).setPlaybackRate(rate);
  }

  void _saveProgressAndPop() {
    final playbackState = ref.read(playbackStateProvider);
    final currentChapterIndex = _currentChapterIndex;
    
    // Only save valid segment index (when queue is loaded)
    final queueLength = playbackState.queue.length;
    final segmentIndex = queueLength > 0 
        ? playbackState.currentIndex.clamp(0, queueLength - 1)
        : 0;

    ref.read(libraryProvider.notifier).updateProgress(
      widget.bookId,
      currentChapterIndex,
      segmentIndex,
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final libraryAsync = ref.watch(libraryProvider);
    final playbackState = ref.watch(playbackStateProvider);
    final currentChapterIndex = _currentChapterIndex;

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

          final chapterIdx = currentChapterIndex.clamp(0, book.chapters.length - 1);
          final chapter = book.chapters[chapterIdx];
          final currentTrack = playbackState.currentTrack;
          final currentText = currentTrack?.text ?? '';
          final queueLength = playbackState.queue.length;
          
          // Show loading state if queue hasn't been loaded yet
          final isLoading = queueLength == 0;
          
          final currentIndex = isLoading 
              ? 0 
              : playbackState.currentIndex.clamp(0, queueLength - 1);

          return SafeArea(
            child: Column(
              children: [
                _buildHeader(colors, book, chapter),
                if (playbackState.error != null) _buildErrorBanner(colors, playbackState.error!),
                if (isLoading)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: colors.primary),
                          const SizedBox(height: 16),
                          Text('Loading chapter...', style: TextStyle(color: colors.textSecondary)),
                        ],
                      ),
                    ),
                  )
                else ...[
                  _buildTextDisplay(colors, currentText, queueLength),
                  _buildProgress(colors, currentIndex, queueLength, chapterIdx, book.chapters.length),
                  const SizedBox(height: 16),
                  _buildRateSelector(colors, playbackState.playbackRate),
                  const SizedBox(height: 16),
                  _buildControls(colors, playbackState),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(AppThemeColors colors, Book book, Chapter chapter) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.headerBackground,
        border: Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _saveProgressAndPop,
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  chapter.title,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(AppThemeColors colors, String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: colors.danger.withOpacity(0.1),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(error, style: TextStyle(color: colors.danger, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildTextDisplay(AppThemeColors colors, String currentText, int queueLength) {
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (currentText.isNotEmpty)
              Text(currentText, style: TextStyle(fontSize: 20, height: 1.6, color: colors.text))
            else
              Text(
                queueLength == 0 ? 'Loading...' : 'No content',
                style: TextStyle(color: colors.textTertiary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(AppThemeColors colors, int currentIndex, int queueLength, int chapterIdx, int chapterCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: queueLength > 0 ? (currentIndex + 1) / queueLength : 0,
            backgroundColor: colors.border,
            color: colors.primary,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Segment ${currentIndex + 1} of $queueLength', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
              Text('Chapter ${chapterIdx + 1} of $chapterCount', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRateSelector(AppThemeColors colors, double currentRate) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final rate in [0.75, 1.0, 1.25, 1.5, 2.0])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => _setPlaybackRate(rate),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: currentRate == rate ? colors.primary : colors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    '${rate}x',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: currentRate == rate ? colors.primaryForeground : colors.text,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls(AppThemeColors colors, PlaybackState playbackState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(onPressed: _previousChapter, icon: Icon(Icons.skip_previous, size: 32, color: colors.text)),
          IconButton(onPressed: _previousSegment, icon: Icon(Icons.fast_rewind, size: 32, color: colors.text)),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
            child: IconButton(
              onPressed: _togglePlay,
              icon: playbackState.isBuffering
                  ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: colors.primaryForeground))
                  : Icon(playbackState.isPlaying ? Icons.pause : Icons.play_arrow, size: 32, color: colors.primaryForeground),
            ),
          ),
          IconButton(onPressed: _nextSegment, icon: Icon(Icons.fast_forward, size: 32, color: colors.text)),
          IconButton(onPressed: _nextChapter, icon: Icon(Icons.skip_next, size: 32, color: colors.text)),
        ],
      ),
    );
  }
}
