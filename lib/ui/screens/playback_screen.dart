import 'dart:async';
import 'dart:io' as java;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playback/playback.dart';

import '../../app/library_controller.dart';
import '../../app/playback_providers.dart';
import '../../app/settings_controller.dart';
import '../../utils/app_logger.dart';
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
  
  // Scroll controller for text view
  final ScrollController _scrollController = ScrollController();
  bool _autoScrollEnabled = true;
  bool _isProgrammaticScroll = false; // Prevents disabling auto-scroll during programmatic scroll
  int _lastAutoScrolledIndex = -1;
  
  // GlobalKey for the currently active segment (for precise scrolling)
  GlobalKey? _activeSegmentKey;
  
  // View mode: true = cover view, false = text view
  bool _showCover = false;
  
  // Sleep timer state
  int? _sleepTimerMinutes; // null = off
  int? _sleepTimeRemainingSeconds;
  Timer? _sleepTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePlayback();
      _setupPlaybackListener();
    });
  }
  
  void _setupPlaybackListener() {
    // Listen to playback state changes for auto-scrolling
    ref.listenManual(playbackStateProvider, (previous, next) {
      if (!mounted) return;
      if (!_autoScrollEnabled) return;
      if (_showCover) return; // Don't scroll when showing cover
      
      final currentIndex = next.currentIndex;
      if (currentIndex >= 0 && currentIndex != _lastAutoScrolledIndex) {
        _lastAutoScrolledIndex = currentIndex;
        // Schedule scroll after the frame is built (so the new key is available)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToActiveSegment();
        });
      }
    });
  }
  
  void _scrollToActiveSegment() {
    if (_activeSegmentKey?.currentContext == null) return;
    
    _isProgrammaticScroll = true;
    
    Scrollable.ensureVisible(
      _activeSegmentKey!.currentContext!,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: 0.15, // Position at 15% from top
    ).then((_) {
      _isProgrammaticScroll = false;
    });
  }
  
  @override
  void dispose() {
    _sleepTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializePlayback() async {
    if (_initialized) {
      PlaybackLogger.debug('[PlaybackScreen] Already initialized, skipping');
      return;
    }

    PlaybackLogger.info('[PlaybackScreen] Initializing playback for book ${widget.bookId}...');

    // Wait for library to be available
    final libraryAsync = ref.read(libraryProvider);
    LibraryState? library;
    
    if (libraryAsync.hasValue) {
      PlaybackLogger.debug('[PlaybackScreen] Library already loaded');
      library = libraryAsync.value;
    } else if (libraryAsync.isLoading) {
      PlaybackLogger.debug('[PlaybackScreen] Waiting for library to load...');
      // Wait for library to load
      library = await ref.read(libraryProvider.future);
      PlaybackLogger.debug('[PlaybackScreen] Library loaded');
    }
    
    if (library == null) {
      PlaybackLogger.error('[PlaybackScreen] ERROR: Library is null');
      return;
    }
    
    _initialized = true;

    final book = library.books.where((b) => b.id == widget.bookId).firstOrNull;
    if (book == null) {
      PlaybackLogger.error('[PlaybackScreen] ERROR: Book ${widget.bookId} not found in library');
      return;
    }

    PlaybackLogger.info('[PlaybackScreen] Book found: "${book.title}" by ${book.author}');
    PlaybackLogger.info('[PlaybackScreen] Book has ${book.chapters.length} chapters');

    final chapterIndex = book.progress.chapterIndex.clamp(0, book.chapters.length - 1);
    final segmentIndex = book.progress.segmentIndex;

    PlaybackLogger.debug('[PlaybackScreen] Saved progress: chapter $chapterIndex, segment $segmentIndex');

    _currentChapterIndex = chapterIndex;

    // Check if current engine needs optimization (first-run prompt)
    final voiceId = ref.read(settingsProvider).selectedVoice;
    if (mounted) {
      await OptimizationPromptDialog.promptIfNeeded(context, ref, voiceId);
    }

    // CRITICAL: Wait for playback controller to be ready before calling loadChapter
    PlaybackLogger.info('[PlaybackScreen] Waiting for playback controller to initialize...');
    try {
      await ref.read(playbackControllerProvider.future);
      PlaybackLogger.info('[PlaybackScreen] Playback controller is ready');
    } catch (e, st) {
      PlaybackLogger.error('[PlaybackScreen] ERROR: Failed to initialize playback controller: $e');
      PlaybackLogger.error('[PlaybackScreen] Stack trace: $st');
      return;
    }

    final notifier = ref.read(playbackControllerProvider.notifier);
    PlaybackLogger.debug('[PlaybackScreen] Calling loadChapter...');
    
    try {
      await notifier.loadChapter(
        book: book,
        chapterIndex: chapterIndex,
        startSegmentIndex: segmentIndex,
        autoPlay: false,
      );
      PlaybackLogger.info('[PlaybackScreen] loadChapter completed successfully');
    } catch (e, st) {
      PlaybackLogger.error('[PlaybackScreen] ERROR in loadChapter: $e');
      PlaybackLogger.error('[PlaybackScreen] Stack trace: $st');
    }
  }

  Future<void> _togglePlay() async {
    final notifier = ref.read(playbackControllerProvider.notifier);
    final state = ref.read(playbackStateProvider);

    if (state.isPlaying) {
      await notifier.pause();
    } else {
      // Check if a voice is selected
      final voiceId = ref.read(settingsProvider).selectedVoice;
      if (voiceId == VoiceIds.none) {
        if (mounted) {
          _showNoVoiceDialog();
        }
        return;
      }
      await notifier.play();
    }
  }
  
  void _showNoVoiceDialog() {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.card,
        title: Text(
          'No Voice Selected',
          style: TextStyle(color: colors.text),
        ),
        content: Text(
          'Please download a voice from the settings menu before playing audiobooks.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/settings/downloads');
            },
            child: const Text('Download Voices'),
          ),
        ],
      ),
    );
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
  
  void _increaseSpeed() {
    final currentRate = ref.read(playbackStateProvider).playbackRate;
    final newRate = (currentRate + 0.25).clamp(0.5, 2.0);
    _setPlaybackRate(newRate);
  }
  
  void _decreaseSpeed() {
    final currentRate = ref.read(playbackStateProvider).playbackRate;
    final newRate = (currentRate - 0.25).clamp(0.5, 2.0);
    _setPlaybackRate(newRate);
  }
  
  void _setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    
    if (minutes == null) {
      setState(() {
        _sleepTimerMinutes = null;
        _sleepTimeRemainingSeconds = null;
      });
      return;
    }
    
    setState(() {
      _sleepTimerMinutes = minutes;
      _sleepTimeRemainingSeconds = minutes * 60;
    });
    
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        if (_sleepTimeRemainingSeconds != null && _sleepTimeRemainingSeconds! > 0) {
          _sleepTimeRemainingSeconds = _sleepTimeRemainingSeconds! - 1;
        } else {
          // Timer expired - pause playback
          ref.read(playbackControllerProvider.notifier).pause();
          _sleepTimerMinutes = null;
          _sleepTimeRemainingSeconds = null;
          timer.cancel();
        }
      });
    });
  }
  
  String _formatSleepTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  void _showSleepTimerPicker(BuildContext context, AppThemeColors colors) {
    final options = <int?>[null, 5, 10, 15, 30, 60];
    final labels = ['Off', '5 min', '10 min', '15 min', '30 min', '1 hour'];
    
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
                  'Sleep Timer',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
              ),
              ...List.generate(options.length, (i) {
                final value = options[i];
                final isSelected = _sleepTimerMinutes == value;
                return InkWell(
                  onTap: () {
                    _setSleepTimer(value);
                    Navigator.pop(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            labels[i],
                            style: TextStyle(
                              fontSize: 16,
                              color: isSelected ? colors.primary : colors.text,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle, color: colors.primary, size: 20),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              colors.backgroundSecondary,
              colors.background,
            ],
          ),
        ),
        child: libraryAsync.when(
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
                    Expanded(
                      child: _showCover
                          ? _buildCoverView(colors, book)
                          : _buildTextDisplay(colors, queue, currentTrack, currentIndex, book),
                    ),
                    _buildPlaybackControls(colors, playbackState, currentIndex, queueLength, chapterIdx, book.chapters.length),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(AppThemeColors colors, Book book, Chapter chapter) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _saveProgressAndPop,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.chevron_left, color: colors.text),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: colors.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  chapter.title,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Toggle view button
          InkWell(
            onTap: () => setState(() => _showCover = !_showCover),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                _showCover ? Icons.menu_book : Icons.image,
                color: colors.text,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(AppThemeColors colors, String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: colors.danger.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(error, style: TextStyle(color: colors.danger, fontSize: 12))),
        ],
      ),
    );
  }
  
  Widget _buildCoverView(AppThemeColors colors, Book book) {
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
                              java.File(book.coverImagePath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildCoverPlaceholder(colors, book),
                            ),
                          )
                        : _buildCoverPlaceholder(colors, book),
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
  
  Widget _buildCoverPlaceholder(AppThemeColors colors, Book book) {
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

  Widget _buildTextDisplay(AppThemeColors colors, List<AudioTrack> queue, AudioTrack? currentTrack, int currentIndex, Book book) {
    if (queue.isEmpty) {
      return Center(
        child: Text('No content', style: TextStyle(color: colors.textTertiary)),
      );
    }
    
    // Get setting for book cover background
    final settings = ref.watch(settingsProvider);
    final showCoverBackground = settings.showBookCoverBackground && book.coverImagePath != null;
    
    // Watch segment readiness stream for opacity-based visualization
    final readinessKey = '${widget.bookId}:$_currentChapterIndex';
    final segmentReadinessAsync = ref.watch(segmentReadinessStreamProvider(readinessKey));
    final segmentReadiness = segmentReadinessAsync.value ?? {};
    
    // Build text spans for continuous text flow
    final List<InlineSpan> spans = [];
    for (int index = 0; index < queue.length; index++) {
      final item = queue[index];
      final isActive = index == currentIndex;
      final isPast = index < currentIndex;
      
      // Get segment readiness (1.0 = ready, lower = not ready)
      final readiness = segmentReadiness[index];
      final isReady = readiness?.opacity == 1.0;
      
      // Text styling based on state (matching Figma design)
      Color textColor;
      if (isActive) {
        textColor = colors.textHighlight; // amber-400 for current
      } else if (isPast) {
        textColor = colors.textPast; // slate-500 for past
      } else if (isReady) {
        textColor = colors.textSecondary; // slate-300 for ready future
      } else {
        textColor = colors.textTertiary.withValues(alpha: 0.5); // slate-700 for not downloaded
      }
      
      final segmentIndex = index; // Capture for closure
      final textStyle = TextStyle(
        fontSize: 17,
        height: 1.7,
        color: textColor,
        fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
      );
      
      // Use WidgetSpan for active segment to enable precise scrolling
      if (isActive) {
        _activeSegmentKey = GlobalKey();
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            key: _activeSegmentKey,
            onTap: () => _seekToSegment(segmentIndex),
            child: Text('${item.text} ', style: textStyle),
          ),
        ));
      } else {
        // Use regular TextSpan for non-active segments
        spans.add(TextSpan(
          text: '${item.text} ',
          style: textStyle,
          recognizer: TapGestureRecognizer()..onTap = () => _seekToSegment(segmentIndex),
        ));
      }
      
      // Add synthesizing indicator if not ready
      if (!isReady && !isPast && !isActive) {
        spans.add(TextSpan(
          text: '(synthesizing...) ',
          style: TextStyle(
            fontSize: 11,
            color: colors.textTertiary.withValues(alpha: 0.7),
            fontStyle: FontStyle.italic,
          ),
        ));
      }
    }
    
    return Stack(
      children: [
        // Faded book cover background
        if (showCoverBackground)
          Positioned.fill(
            child: Opacity(
              opacity: 0.04, // Very subtle, barely visible
              child: Image.file(
                java.File(book.coverImagePath!),
                fit: BoxFit.cover,
                colorBlendMode: BlendMode.saturation,
                color: Colors.grey, // Desaturate the image
              ),
            ),
          ),
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            // Disable auto-scroll when user finishes scrolling manually (not programmatic)
            if (notification is ScrollEndNotification && _autoScrollEnabled && !_isProgrammaticScroll) {
              setState(() => _autoScrollEnabled = false);
            }
            return false;
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
            child: RichText(
              text: TextSpan(children: spans),
            ),
          ),
        ),
        
        // Jump to current button (bottom right) - shown when auto-scroll is disabled
        if (!_autoScrollEnabled)
          Positioned(
            bottom: 16,
            right: 16,
            child: Material(
              color: colors.primary,
              borderRadius: BorderRadius.circular(24),
              elevation: 4,
              child: InkWell(
                onTap: _jumpToCurrent,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.my_location, size: 18, color: colors.primaryForeground),
                      const SizedBox(width: 8),
                      Text(
                        'Resume auto-scroll',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colors.primaryForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
  
  void _jumpToCurrent() {
    final playbackState = ref.read(playbackStateProvider);
    if (playbackState.queue.isEmpty) return;
    
    final currentIndex = playbackState.currentIndex;
    
    // Re-enable auto-scroll first (button will disappear)
    setState(() {
      _autoScrollEnabled = true;
      _lastAutoScrolledIndex = currentIndex;
    });
    
    // Use Scrollable.ensureVisible for precise scrolling
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActiveSegment();
    });
  }
  
  Future<void> _seekToSegment(int index) async {
    final notifier = ref.read(playbackControllerProvider.notifier);
    final playbackState = ref.read(playbackStateProvider);
    
    if (index >= 0 && index < playbackState.queue.length) {
      await notifier.seekToTrack(index, play: true);
      setState(() => _autoScrollEnabled = true);
    }
  }

  Widget _buildPlaybackControls(AppThemeColors colors, PlaybackState playbackState, int currentIndex, int queueLength, int chapterIdx, int chapterCount) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border, width: 1)),
        color: colors.background.withValues(alpha: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Text(
                  '${currentIndex + 1}',
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: queueLength > 0 ? (currentIndex + 1) / queueLength : 0,
                      backgroundColor: colors.controlBackground,
                      color: colors.primary,
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$queueLength',
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          
          // Speed and Sleep Timer controls
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Speed control
                Row(
                  children: [
                    Icon(Icons.speed, size: 16, color: colors.textSecondary),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _decreaseSpeed,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.chevron_left, size: 18, color: colors.textSecondary),
                      ),
                    ),
                    Container(
                      width: 48,
                      alignment: Alignment.center,
                      child: Text(
                        '${playbackState.playbackRate}x',
                        style: TextStyle(fontSize: 13, color: colors.text, fontWeight: FontWeight.w500),
                      ),
                    ),
                    InkWell(
                      onTap: _increaseSpeed,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.chevron_right, size: 18, color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
                
                // Sleep timer
                Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 16, color: colors.textSecondary),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showSleepTimerPicker(context, colors),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: colors.controlBackground,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _sleepTimerMinutes == null 
                                    ? 'Off' 
                                    : _sleepTimerMinutes == 60 
                                        ? '1 hour'
                                        : '$_sleepTimerMinutes min',
                                style: TextStyle(fontSize: 13, color: colors.text),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down, size: 16, color: colors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_sleepTimeRemainingSeconds != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        _formatSleepTime(_sleepTimeRemainingSeconds!),
                        style: TextStyle(fontSize: 12, color: colors.textHighlight, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          
          // Main controls
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Previous chapter
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: chapterIdx > 0 ? _previousChapter : null,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.skip_previous,
                        size: 24,
                        color: chapterIdx > 0 ? colors.text : colors.textTertiary,
                      ),
                    ),
                  ),
                ),
                
                // Previous segment
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: currentIndex > 0 ? _previousSegment : null,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.fast_rewind,
                        size: 28,
                        color: currentIndex > 0 ? colors.text : colors.textTertiary,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Play/Pause button
                Material(
                  color: colors.primary,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    onTap: _togglePlay,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      child: playbackState.isBuffering
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.primaryForeground,
                              ),
                            )
                          : Icon(
                              playbackState.isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 32,
                              color: colors.primaryForeground,
                            ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Next segment
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: currentIndex < queueLength - 1 ? _nextSegment : null,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.fast_forward,
                        size: 28,
                        color: currentIndex < queueLength - 1 ? colors.text : colors.textTertiary,
                      ),
                    ),
                  ),
                ),
                
                // Next chapter
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _nextChapter,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.skip_next,
                        size: 24,
                        color: colors.text,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
