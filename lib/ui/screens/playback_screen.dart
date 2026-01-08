import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playback/playback.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../app/library_controller.dart';
import '../../app/playback_providers.dart';
import '../../app/settings_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/optimization_prompt_dialog.dart';
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
  
  // Scroll controllers for segment list
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  bool _autoScrollEnabled = true;
  int _lastScrolledIndex = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePlayback();
      _setupAutoScrollListener();
    });
  }

  /// Set up listener for auto-scrolling based on playback state changes.
  /// Runs outside of build method to avoid performance issues.
  void _setupAutoScrollListener() {
    // Listen to playback state changes and scroll accordingly
    ref.listenManual(playbackStateProvider, (previous, next) {
      if (!_autoScrollEnabled) return;
      if (!mounted) return;
      
      final currentTrack = next.currentTrack;
      if (currentTrack == null) return;
      
      final queue = next.queue;
      final currentIndex = queue.indexWhere((t) => t.id == currentTrack.id);
      
      if (currentIndex >= 0 && currentIndex != _lastScrolledIndex) {
        _scrollToIndex(currentIndex);
      }
    });
  }

  /// Scroll to a specific index if not already visible.
  void _scrollToIndex(int index) {
    if (!_itemScrollController.isAttached) return;
    
    // Check if current segment is visible
    final positions = _itemPositionsListener.itemPositions.value;
    final isVisible = positions.any((pos) => 
        pos.index == index && 
        pos.itemLeadingEdge >= 0 && 
        pos.itemTrailingEdge <= 1);
    
    if (!isVisible) {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 300),
        alignment: 0.3,
      );
    }
    _lastScrolledIndex = index;
  }

  Future<void> _initializePlayback() async {
    if (_initialized) {
      print('[PlaybackScreen] Already initialized, skipping');
      return;
    }

    print('[PlaybackScreen] Initializing playback for book ${widget.bookId}...');

    // Wait for library to be available
    final libraryAsync = ref.read(libraryProvider);
    LibraryState? library;
    
    if (libraryAsync.hasValue) {
      print('[PlaybackScreen] Library already loaded');
      library = libraryAsync.value;
    } else if (libraryAsync.isLoading) {
      print('[PlaybackScreen] Waiting for library to load...');
      // Wait for library to load
      library = await ref.read(libraryProvider.future);
      print('[PlaybackScreen] Library loaded');
    }
    
    if (library == null) {
      print('[PlaybackScreen] ERROR: Library is null');
      return;
    }
    
    _initialized = true;

    final book = library.books.where((b) => b.id == widget.bookId).firstOrNull;
    if (book == null) {
      print('[PlaybackScreen] ERROR: Book ${widget.bookId} not found in library');
      return;
    }

    print('[PlaybackScreen] Book found: "${book.title}" by ${book.author}');
    print('[PlaybackScreen] Book has ${book.chapters.length} chapters');

    final chapterIndex = book.progress.chapterIndex.clamp(0, book.chapters.length - 1);
    final segmentIndex = book.progress.segmentIndex;

    print('[PlaybackScreen] Saved progress: chapter $chapterIndex, segment $segmentIndex');

    _currentChapterIndex = chapterIndex;

    // Check if current engine needs optimization (first-run prompt)
    final voiceId = ref.read(settingsProvider).selectedVoice;
    if (mounted) {
      await OptimizationPromptDialog.promptIfNeeded(context, ref, voiceId);
    }

    // CRITICAL: Wait for playback controller to be ready before calling loadChapter
    print('[PlaybackScreen] Waiting for playback controller to initialize...');
    try {
      await ref.read(playbackControllerProvider.future);
      print('[PlaybackScreen] Playback controller is ready');
    } catch (e, st) {
      print('[PlaybackScreen] ERROR: Failed to initialize playback controller: $e');
      print('[PlaybackScreen] Stack trace: $st');
      return;
    }

    final notifier = ref.read(playbackControllerProvider.notifier);
    print('[PlaybackScreen] Calling loadChapter...');
    
    try {
      await notifier.loadChapter(
        book: book,
        chapterIndex: chapterIndex,
        startSegmentIndex: segmentIndex,
        autoPlay: false,
      );
      print('[PlaybackScreen] loadChapter completed successfully');
    } catch (e, st) {
      print('[PlaybackScreen] ERROR in loadChapter: $e');
      print('[PlaybackScreen] Stack trace: $st');
    }
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
      floatingActionButton: !_autoScrollEnabled
          ? FloatingActionButton.small(
              onPressed: _jumpToCurrentSegment,
              backgroundColor: colors.primary,
              child: Icon(Icons.my_location, color: colors.primaryForeground),
            )
          : null,
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
          final queue = playbackState.queue;
          final queueLength = queue.length;
          
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
                  _buildTextDisplay(colors, queue, currentTrack),
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

  Widget _buildTextDisplay(AppThemeColors colors, List<AudioTrack> queue, AudioTrack? currentTrack) {
    if (queue.isEmpty) {
      return Expanded(
        child: Center(
          child: Text('No content', style: TextStyle(color: colors.textTertiary)),
        ),
      );
    }
    
    // Watch segment readiness stream for opacity-based visualization
    final readinessKey = '${widget.bookId}:$_currentChapterIndex';
    final segmentReadinessAsync = ref.watch(segmentReadinessStreamProvider(readinessKey));
    final segmentReadiness = segmentReadinessAsync.value ?? {};
    
    return Expanded(
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // Disable auto-scroll when user scrolls manually
          if (notification is UserScrollNotification) {
            setState(() => _autoScrollEnabled = false);
          }
          return false;
        },
        child: ScrollablePositionedList.builder(
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          itemCount: queue.length,
          itemBuilder: (context, index) {
            final item = queue[index];
            final isActive = currentTrack?.id == item.id;
            
            // Get segment readiness opacity (1.0 = ready, 0.4 = not queued)
            final readiness = segmentReadiness[index];
            final segmentOpacity = readiness?.opacity ?? 0.4;
            
            // Active segment is always fully visible
            final effectiveOpacity = isActive ? 1.0 : segmentOpacity;
            
            final textColor = isActive 
                ? colors.text 
                : colors.textSecondary.withOpacity(effectiveOpacity);
            final fontWeight = isActive ? FontWeight.w600 : FontWeight.normal;
            final backgroundColor = isActive 
                ? colors.primary.withValues(alpha: 0.14)
                : null;
            
            return AnimatedOpacity(
              opacity: effectiveOpacity,
              duration: const Duration(milliseconds: 300),
              child: InkWell(
                onTap: () => _seekToSegment(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  decoration: backgroundColor != null
                      ? BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(8),
                        )
                      : null,
                  child: Text(
                    item.text,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: textColor,
                      fontWeight: fontWeight,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
  
  Future<void> _seekToSegment(int index) async {
    final notifier = ref.read(playbackControllerProvider.notifier);
    final playbackState = ref.read(playbackStateProvider);
    
    if (index >= 0 && index < playbackState.queue.length) {
      await notifier.seekToTrack(index, play: playbackState.isPlaying);
      setState(() {
        _autoScrollEnabled = true;
        _lastScrolledIndex = index;
      });
    }
  }
  
  void _jumpToCurrentSegment() {
    final playbackState = ref.read(playbackStateProvider);
    final currentIndex = playbackState.currentIndex;
    
    if (currentIndex >= 0 && _itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: currentIndex,
        duration: const Duration(milliseconds: 300),
        alignment: 0.3,
      );
      setState(() {
        _autoScrollEnabled = true;
        _lastScrolledIndex = currentIndex;
      });
    }
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
