import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playback/playback.dart' hide SegmentReadinessTracker;

import '../../app/library_controller.dart';
import '../../app/listening_actions_notifier.dart';
import '../../app/playback_providers.dart';
import '../../app/settings_controller.dart';
import '../../utils/app_haptics.dart';
import '../../utils/app_logger.dart';
import '../theme/app_colors.dart';
import '../widgets/segment_seek_slider.dart';
import 'package:core_domain/core_domain.dart';
import 'playback/dialogs/dialogs.dart';
import 'playback/layouts/layouts.dart';
import 'playback/widgets/widgets.dart';

class PlaybackScreen extends ConsumerStatefulWidget {
  const PlaybackScreen({
    super.key,
    required this.bookId,
    this.initialChapter,
    this.initialSegment,
    this.startPlayback = false,
  });

  final String bookId;

  /// Optional initial chapter to navigate to (from query params)
  final int? initialChapter;

  /// Optional initial segment to navigate to (from query params)
  final int? initialSegment;

  /// If true, start playback immediately (don't enter preview mode).
  /// Used when user explicitly clicks "Start Listening" / "Continue Listening".
  final bool startPlayback;

  @override
  ConsumerState<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends ConsumerState<PlaybackScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _initialized = false;
  int _currentChapterIndex = 0;

  // Preview mode: viewing a chapter different from what's playing
  // When true, we show the mini player instead of full controls
  bool _isPreviewMode = false;
  List<Segment>? _previewSegments; // Segments loaded for preview display
  int? _activePlaybackChapter; // Chapter that's actually playing (for preview mode reference)

  // Scroll controller for text view
  final ScrollController _scrollController = ScrollController();
  bool _autoScrollEnabled = true;
  int _lastAutoScrolledIndex = -1;

  // GlobalKey for the currently active segment (for precise scrolling)
  GlobalKey? _activeSegmentKey;

  // View mode: true = cover view, false = text view
  bool _showCover = false;

  // Sleep timer state
  int? _sleepTimerMinutes; // null = off
  int? _sleepTimeRemainingSeconds;
  Timer? _sleepTimer;

  // Orientation transition animation
  late AnimationController _orientationAnimController;
  late Animation<double> _fadeAnimation;
  bool _showOverlay = false; // Show overlay during orientation change
  Size? _lastWindowSize; // Track window size to detect orientation change early

  // Fullscreen mode for landscape
  bool _wasLandscape = false;

  // Cache verification: track segment count to verify every N segments
  int _segmentsPlayedSinceVerification = 0;
  static const _verificationInterval = 5; // Verify every 5 segments

  // Auto-save timer for progress persistence
  Timer? _autoSaveTimer;
  static const _autoSaveIntervalSeconds = 30;
  int _lastSavedSegmentIndex =
      -1; // Track last saved position to avoid redundant saves

  // Orientation detection
  bool _isLandscape(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > size.height;
  }

  @override
  void didChangeMetrics() {
    // Called when screen metrics change (before build)
    final window = WidgetsBinding.instance.platformDispatcher.views.first;
    final newSize = window.physicalSize;

    if (_lastWindowSize != null) {
      // Check if orientation changed (width/height swapped)
      final wasLandscape = _lastWindowSize!.width > _lastWindowSize!.height;
      final isNowLandscape = newSize.width > newSize.height;

      if (wasLandscape != isNowLandscape && mounted) {
        // Orientation is changing - show overlay immediately
        setState(() {
          _showOverlay = true;
        });
        // Start fade-out animation
        _orientationAnimController.forward(from: 0.0).then((_) {
          if (mounted) {
            setState(() {
              _showOverlay = false;
            });
          }
        });
      }
    }
    _lastWindowSize = newSize;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save position when app goes to background or screen locks.
    // This prevents position loss if the app is killed while in background.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _savePositionOnBackground();
    }
  }

  /// Save the current position when app goes to background.
  /// Only saves in active mode (not preview mode) to avoid
  /// accidentally updating position while just browsing.
  void _savePositionOnBackground() {
    if (_isPreviewMode) return;

    final playbackState = ref.read(playbackStateProvider);
    final currentChapterIndex = _currentChapterIndex;

    final queueLength = playbackState.queue.length;
    if (queueLength == 0) return;

    final segmentIndex = playbackState.currentIndex.clamp(0, queueLength - 1);

    developer.log(
      '[PlaybackScreen] Saving position on background: chapter $currentChapterIndex, segment $segmentIndex',
    );

    // Save to both tables for consistency
    ref
        .read(libraryProvider.notifier)
        .updateProgress(widget.bookId, currentChapterIndex, segmentIndex);

    ref
        .read(listeningActionsProvider.notifier)
        .saveChapterPosition(
          bookId: widget.bookId,
          chapterIndex: currentChapterIndex,
          segmentIndex: segmentIndex,
        );
  }

  void _updateSystemUI(bool isLandscape) {
    if (isLandscape && !_wasLandscape) {
      // Entering landscape - enable immersive mode
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
      _wasLandscape = true;
    } else if (!isLandscape && _wasLandscape) {
      // Returning to portrait - restore normal UI
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
      _wasLandscape = false;
    }
  }

  void _restoreSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  }

  @override
  void initState() {
    super.initState();
    // Register for metrics changes to detect orientation early
    WidgetsBinding.instance.addObserver(this);

    // Initialize window size tracking
    final window = WidgetsBinding.instance.platformDispatcher.views.first;
    _lastWindowSize = window.physicalSize;

    // Setup orientation transition animation
    _orientationAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _orientationAnimController,
        curve: Curves.easeOut,
      ),
    );
    _orientationAnimController.value = 1.0; // Start fully visible

    // Allow all orientations on playback screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePlayback();
      _setupPlaybackListener();
      _setupHapticListener();
      _startAutoSaveTimer();
    });
  }

  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(
      const Duration(seconds: _autoSaveIntervalSeconds),
      (_) => _autoSaveProgress(),
    );
  }

  /// Auto-save progress to SQLite periodically.
  /// Prevents progress loss on crash or unexpected termination.
  /// Saves both book-level progress (reading_progress) and per-chapter position
  /// (chapter_positions) so users can resume from where they left off in each chapter.
  void _autoSaveProgress() {
    // Don't save in preview mode - we're just browsing
    if (_isPreviewMode) return;

    final playbackState = ref.read(playbackStateProvider);
    final currentChapterIndex = _currentChapterIndex;

    // Only save if we have a valid queue
    final queueLength = playbackState.queue.length;
    if (queueLength == 0) return;

    final segmentIndex = playbackState.currentIndex.clamp(0, queueLength - 1);

    // Skip if position hasn't changed since last save
    if (segmentIndex == _lastSavedSegmentIndex &&
        currentChapterIndex == _currentChapterIndex) {
      return;
    }

    _lastSavedSegmentIndex = segmentIndex;

    // Save book-level progress (reading_progress table)
    ref
        .read(libraryProvider.notifier)
        .updateProgress(widget.bookId, currentChapterIndex, segmentIndex);

    // Also save per-chapter position so returning to this chapter resumes here.
    // Uses saveChapterPosition which preserves the primary flag - this way the
    // "Continue Listening" button continues to work correctly while also
    // remembering where the user was in each chapter.
    ref
        .read(listeningActionsProvider.notifier)
        .saveChapterPosition(
          bookId: widget.bookId,
          chapterIndex: currentChapterIndex,
          segmentIndex: segmentIndex,
        );

    developer.log(
      '[PlaybackScreen] Auto-saved progress: chapter $currentChapterIndex, segment $segmentIndex',
    );
  }

  void _setupHapticListener() {
    // Sync haptic enabled state with settings
    ref.listenManual(settingsProvider.select((s) => s.hapticFeedbackEnabled), (
      _,
      enabled,
    ) {
      AppHaptics.setEnabled(enabled);
    });
    // Initialize with current setting
    AppHaptics.setEnabled(ref.read(settingsProvider).hapticFeedbackEnabled);
  }

  void _setupPlaybackListener() {
    // Listen to playback state changes for auto-scrolling and auto-advance
    ref.listenManual(playbackStateProvider, (previous, next) {
      if (!mounted) return;

      // Auto-advance to next chapter when current chapter ends
      _handleAutoAdvanceChapter(previous, next);

      // Periodic cache verification for segment color accuracy
      final previousIndex = previous?.currentIndex ?? -1;
      final currentIndex = next.currentIndex;
      if (currentIndex >= 0 && currentIndex != previousIndex) {
        _segmentsPlayedSinceVerification++;
        if (_segmentsPlayedSinceVerification >= _verificationInterval) {
          _segmentsPlayedSinceVerification = 0;
          _verifyCacheReadiness(next);
        }
      }

      if (!_autoScrollEnabled) return;
      if (_showCover) return; // Don't scroll when showing cover
      if (_isPreviewMode) return; // Don't auto-scroll in preview mode

      if (currentIndex >= 0 && currentIndex != _lastAutoScrolledIndex) {
        _lastAutoScrolledIndex = currentIndex;
        // Schedule scroll after the frame is built (so the new key is available)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToActiveSegment();
        });
      }
    });
  }

  /// Verify that segments marked as "ready" are actually in cache.
  /// This catches cache evictions that weren't notified to the tracker.
  Future<void> _verifyCacheReadiness(PlaybackState state) async {
    if (state.bookId == null || state.queue.isEmpty) return;

    final chapterIndex = state.queue.first.chapterIndex;
    final key = '${state.bookId}:$chapterIndex';
    final currentSegment = state.currentIndex;

    try {
      final cache = await ref.read(audioCacheProvider.future);
      final settings = ref.read(settingsProvider);
      final voiceId = settings.selectedVoice;

      final evicted = await SegmentReadinessTracker.instance.verifyAgainstCache(
        key: key,
        startIndex: currentSegment,
        windowSize: 10, // Check 10 segments ahead
        isSegmentCached: (index) async {
          if (index >= state.queue.length) return true; // No segment to check
          final segment = state.queue[index];
          final cacheKey = CacheKeyGenerator.generate(
            voiceId: voiceId,
            text: segment.text,
            playbackRate: CacheKeyGenerator.getSynthesisRate(1.0),
          );
          return cache.isReady(cacheKey);
        },
      );

      if (evicted.isNotEmpty) {
        developer.log(
          '[PlaybackScreen] Cache verification found ${evicted.length} evicted segments: $evicted',
        );
      }
    } catch (e) {
      developer.log('[PlaybackScreen] Cache verification error: $e');
    }
  }

  /// Handle auto-advance to next chapter when current chapter ends.
  /// Does NOT reset sleep timer (auto-advance is not a user action).
  void _handleAutoAdvanceChapter(PlaybackState? previous, PlaybackState next) {
    // Skip if auto-advance is disabled
    final settings = ref.read(settingsProvider);
    if (!settings.autoAdvanceChapters) return;

    // Detect end of chapter: was playing, now not playing, at last track
    if (previous == null) return;
    if (!previous.isPlaying) return; // Was not playing
    if (next.isPlaying) return; // Still playing
    if (next.isBuffering) return; // Just buffering, not ended
    if (next.queue.isEmpty) return; // No queue

    // Check if we're at the last track (chapter ended)
    final isAtLastTrack = next.currentIndex == next.queue.length - 1;
    if (!isAtLastTrack) return;

    // Get book and check if there's a next chapter
    final library = ref.read(libraryProvider).value;
    if (library == null) return;

    final book = library.books.where((b) => b.id == widget.bookId).firstOrNull;
    if (book == null) return;

    final currentChapterIndex = _currentChapterIndex;

    // Mark the current chapter as complete (works for all chapters including last)
    ref
        .read(libraryProvider.notifier)
        .markChapterComplete(widget.bookId, currentChapterIndex);

    // Only auto-advance if there's another chapter
    if (currentChapterIndex >= book.chapters.length - 1) return;

    // Auto-advance to next chapter
    _autoAdvanceToNextChapter(book, currentChapterIndex, currentChapterIndex + 1);
  }

  /// Automatically advance to next chapter (does NOT reset sleep timer).
  ///
  /// This saves the completed chapter's position at the end (for returning later)
  /// and updates the primary position to the new chapter (for "Continue Listening").
  Future<void> _autoAdvanceToNextChapter(
    Book book,
    int completedChapterIndex,
    int newChapterIndex,
  ) async {
    final playbackState = ref.read(playbackStateProvider);
    final completedSegmentIndex =
        playbackState.queue.isNotEmpty
            ? playbackState.queue.length - 1  // End of chapter
            : 0;

    // Save completed chapter position at the end (for when user returns to it)
    await ref.read(listeningActionsProvider.notifier).saveChapterPosition(
          bookId: widget.bookId,
          chapterIndex: completedChapterIndex,
          segmentIndex: completedSegmentIndex,
        );

    setState(() => _currentChapterIndex = newChapterIndex);

    await ref
        .read(playbackControllerProvider.notifier)
        .loadChapter(
          book: book,
          chapterIndex: newChapterIndex,
          startSegmentIndex: 0,
          autoPlay: true, // Continue playing
        );

    // Update primary position to the new chapter (for "Continue Listening")
    await ref.read(listeningActionsProvider.notifier).saveCurrentPosition(
          bookId: widget.bookId,
          chapterIndex: newChapterIndex,
          segmentIndex: 0,
        );
  }

  void _scrollToActiveSegment() {
    if (_activeSegmentKey?.currentContext == null) return;

    Scrollable.ensureVisible(
      _activeSegmentKey!.currentContext!,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: 0.15, // Position at 15% from top
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orientationAnimController.dispose();
    _restoreSystemUI();
    // Restore portrait-only orientation when leaving playback screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _sleepTimer?.cancel();
    _autoSaveTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializePlayback() async {
    if (_initialized) {
      PlaybackLogger.debug('[PlaybackScreen] Already initialized, skipping');
      return;
    }

    PlaybackLogger.info(
      '[PlaybackScreen] Initializing playback for book ${widget.bookId}...',
    );

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
      PlaybackLogger.error(
        '[PlaybackScreen] ERROR: Book ${widget.bookId} not found in library',
      );
      return;
    }

    PlaybackLogger.info(
      '[PlaybackScreen] Book found: "${book.title}" by ${book.author}',
    );
    PlaybackLogger.info(
      '[PlaybackScreen] Book has ${book.chapters.length} chapters',
    );

    // Use initial params if provided (from deep link / book details navigation),
    // otherwise fall back to saved book progress
    final chapterIndex = (widget.initialChapter ?? book.progress.chapterIndex)
        .clamp(0, book.chapters.length - 1);
    final segmentIndex = widget.initialSegment ?? book.progress.segmentIndex;

    if (widget.initialChapter != null) {
      PlaybackLogger.debug(
        '[PlaybackScreen] Using initial params: chapter ${widget.initialChapter}, segment ${widget.initialSegment}',
      );
    }
    PlaybackLogger.debug(
      '[PlaybackScreen] Starting at: chapter $chapterIndex, segment $segmentIndex',
    );

    _currentChapterIndex = chapterIndex;

    // CRITICAL: Wait for playback controller to be ready before calling loadChapter
    PlaybackLogger.info(
      '[PlaybackScreen] Waiting for playback controller to initialize...',
    );
    try {
      await ref.read(playbackControllerProvider.future);
      PlaybackLogger.info('[PlaybackScreen] Playback controller is ready');
    } catch (e, st) {
      PlaybackLogger.error(
        '[PlaybackScreen] ERROR: Failed to initialize playback controller: $e',
      );
      PlaybackLogger.error('[PlaybackScreen] Stack trace: $st');
      return;
    }

    // Check if audio is already playing
    final currentState = ref.read(playbackStateProvider);
    final hasActivePlayback = currentState.queue.isNotEmpty;
    final isPlayingSameBook = hasActivePlayback && currentState.bookId == widget.bookId;
    final isPlayingDifferentBook = hasActivePlayback && currentState.bookId != widget.bookId;

    final activeChapter = isPlayingSameBook
        ? currentState.queue.first.chapterIndex
        : null;

    if (isPlayingSameBook && activeChapter != chapterIndex) {
      // PREVIEW MODE (same book): User is viewing a different chapter than what's playing
      PlaybackLogger.debug(
        '[PlaybackScreen] Entering preview mode (same book): viewing chapter $chapterIndex, playing chapter $activeChapter',
      );
      _activePlaybackChapter = activeChapter;
      await _enterPreviewMode(book, chapterIndex);
    } else if (isPlayingSameBook && activeChapter == chapterIndex) {
      // Same chapter is already loaded
      PlaybackLogger.debug(
        '[PlaybackScreen] Chapter $chapterIndex already loaded, skipping reload',
      );
      // Just seek to the correct segment if needed
      if (segmentIndex != currentState.currentIndex &&
          segmentIndex < currentState.queue.length) {
        await ref.read(playbackControllerProvider.notifier).seekToTrack(
          segmentIndex,
          play: currentState.isPlaying,
        );
      }
    } else if (isPlayingDifferentBook && !widget.startPlayback) {
      // PREVIEW MODE (different book): Audio is playing a different book
      // Show this book's content in preview mode with mini player showing what's playing
      // BUT: if startPlayback is true, user explicitly wants to switch books
      PlaybackLogger.debug(
        '[PlaybackScreen] Entering preview mode (different book): viewing ${widget.bookId}, playing ${currentState.bookId}',
      );
      // Store the playing book info for mini player reference
      if (currentState.queue.isNotEmpty) {
        _activePlaybackChapter = currentState.queue.first.chapterIndex;
      }
      await _enterPreviewMode(book, chapterIndex);
    } else if (isPlayingDifferentBook && widget.startPlayback) {
      // User explicitly requested to start playback of this book (from "Start Listening" button)
      // Stop the other book and load this one
      PlaybackLogger.debug(
        '[PlaybackScreen] Switching books: user requested playback of ${widget.bookId}, stopping ${currentState.bookId}',
      );
      // Pause current playback first to ensure clean state transition
      await ref.read(playbackControllerProvider.notifier).pause();
      await _loadChapterWithRetry(
        book: book,
        chapterIndex: chapterIndex,
        segmentIndex: segmentIndex,
      );
    } else {
      // No active playback - normal load
      await _loadChapterWithRetry(
        book: book,
        chapterIndex: chapterIndex,
        segmentIndex: segmentIndex,
      );
    }

    // If user navigated to a specific chapter (via deep link / book details / segment tap),
    // save it as the primary position (only in active mode, not preview mode).
    if (widget.initialChapter != null && !_isPreviewMode) {
      await ref
          .read(listeningActionsProvider.notifier)
          .saveCurrentPosition(
            bookId: widget.bookId,
            chapterIndex: chapterIndex,
            segmentIndex: segmentIndex,
          );
      PlaybackLogger.debug(
        '[PlaybackScreen] Set primary position to chapter $chapterIndex, segment $segmentIndex',
      );

      // If a specific segment was provided, scroll to it
      // (auto-scroll listener only triggers on state changes, not initial load)
      if (widget.initialSegment != null && segmentIndex >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollToActiveSegment();
          }
        });
        PlaybackLogger.debug(
          '[PlaybackScreen] Scrolling to initial segment $segmentIndex',
        );
      }
    }
  }

  /// Enter preview mode - load segments for display but don't switch audio
  Future<void> _enterPreviewMode(Book book, int chapterIndex) async {
    final segments = await ref
        .read(libraryProvider.notifier)
        .getSegmentsForChapter(book.id, chapterIndex);

    if (mounted) {
      setState(() {
        _isPreviewMode = true;
        _previewSegments = segments;
      });
    }
  }

  /// Exit preview mode and switch audio to this chapter
  Future<void> _exitPreviewModeAndPlay(int segmentIndex) async {
    final library = ref.read(libraryProvider).value;
    if (library == null) return;

    final book = library.books.where((b) => b.id == widget.bookId).firstOrNull;
    if (book == null) return;

    // Save as primary position
    await ref.read(listeningActionsProvider.notifier).saveCurrentPosition(
          bookId: widget.bookId,
          chapterIndex: _currentChapterIndex,
          segmentIndex: segmentIndex,
        );

    // Load and start playing the chapter
    await ref
        .read(playbackControllerProvider.notifier)
        .loadChapter(
          book: book,
          chapterIndex: _currentChapterIndex,
          startSegmentIndex: segmentIndex,
          autoPlay: true,
        );

    if (mounted) {
      setState(() {
        _isPreviewMode = false;
        _previewSegments = null;
        _activePlaybackChapter = null;
      });
    }
  }

  /// Load chapter with retry logic to handle race conditions.
  ///
  /// On first app launch, there can be a race condition where:
  /// 1. loadChapter is called and updates state
  /// 2. playbackControllerProvider gets invalidated (e.g., by download manager init)
  /// 3. New provider builds with empty state, discarding the loaded chapter
  ///
  /// This method detects when the queue is empty after loading and retries once.
  Future<void> _loadChapterWithRetry({
    required Book book,
    required int chapterIndex,
    required int segmentIndex,
    int retryCount = 0,
  }) async {
    const maxRetries = 1;

    final notifier = ref.read(playbackControllerProvider.notifier);
    PlaybackLogger.debug('[PlaybackScreen] Calling loadChapter (attempt ${retryCount + 1})...');

    try {
      await notifier.loadChapter(
        book: book,
        chapterIndex: chapterIndex,
        startSegmentIndex: segmentIndex,
        autoPlay: false,
      );

      // Verify the queue was actually populated
      // Give a small delay for state to propagate
      await Future.delayed(const Duration(milliseconds: 50));

      final state = ref.read(playbackStateProvider);
      if (state.queue.isEmpty && retryCount < maxRetries) {
        PlaybackLogger.warning(
          '[PlaybackScreen] Queue is empty after loadChapter - likely due to provider invalidation. Retrying...',
        );

        // Wait a bit longer for provider to stabilize
        await Future.delayed(const Duration(milliseconds: 200));

        // Ensure controller is ready again
        await ref.read(playbackControllerProvider.future);

        return _loadChapterWithRetry(
          book: book,
          chapterIndex: chapterIndex,
          segmentIndex: segmentIndex,
          retryCount: retryCount + 1,
        );
      }

      PlaybackLogger.info(
        '[PlaybackScreen] loadChapter completed successfully (queue has ${state.queue.length} tracks)',
      );
    } catch (e, st) {
      PlaybackLogger.error('[PlaybackScreen] ERROR in loadChapter: $e');
      PlaybackLogger.error('[PlaybackScreen] Stack trace: $st');
    }
  }

  Future<void> _togglePlay() async {
    _resetSleepTimer(); // Reset sleep timer on user action
    final notifier = ref.read(playbackControllerProvider.notifier);
    final state = ref.read(playbackStateProvider);

    if (state.isPlaying) {
      AppHaptics.medium(); // Pausing feels "heavier"
      await notifier.pause();
    } else {
      // Check if a voice is selected
      final voiceId = ref.read(settingsProvider).selectedVoice;
      if (voiceId == VoiceIds.none) {
        if (mounted) {
          NoVoiceDialog.show(context);
        }
        return;
      }
      AppHaptics.light(); // Playing feels "lighter"
      await notifier.play();
    }
  }

  Future<void> _nextSegment() async {
    _resetSleepTimer(); // Reset sleep timer on user action
    await ref.read(playbackControllerProvider.notifier).nextTrack();
  }

  Future<void> _previousSegment() async {
    _resetSleepTimer(); // Reset sleep timer on user action
    await ref.read(playbackControllerProvider.notifier).previousTrack();
  }

  Future<void> _nextChapter() async {
    _resetSleepTimer(); // Reset sleep timer on user action
    final library = ref.read(libraryProvider).value;
    if (library == null) return;

    final book = library.books.where((b) => b.id == widget.bookId).firstOrNull;
    if (book == null) return;

    final currentChapterIndex = _currentChapterIndex;
    final playbackState = ref.read(playbackStateProvider);
    final currentSegmentIndex =
        playbackState.queue.isNotEmpty
            ? playbackState.currentIndex.clamp(
              0,
              playbackState.queue.length - 1,
            )
            : 0;

    // Mark the current chapter as complete when advancing to next
    await ref
        .read(libraryProvider.notifier)
        .markChapterComplete(widget.bookId, currentChapterIndex);

    // If at last chapter, can't advance further
    if (currentChapterIndex >= book.chapters.length - 1) {
      AppHaptics.heavy(); // Boundary feedback
      return;
    }

    AppHaptics.medium(); // Chapter change feedback
    final newChapterIndex = currentChapterIndex + 1;

    // Save current chapter position before jumping
    await ref.read(listeningActionsProvider.notifier).saveChapterPosition(
          bookId: widget.bookId,
          chapterIndex: currentChapterIndex,
          segmentIndex: currentSegmentIndex,
        );

    // Get resume position for target chapter
    final targetSegment = await ref
        .read(listeningActionsProvider.notifier)
        .getResumePosition(widget.bookId, newChapterIndex);

    setState(() => _currentChapterIndex = newChapterIndex);

    await ref
        .read(playbackControllerProvider.notifier)
        .loadChapter(
          book: book,
          chapterIndex: newChapterIndex,
          startSegmentIndex: targetSegment,
          autoPlay: playbackState.isPlaying,
        );

    // Next/previous is sequential navigation - update primary to new chapter
    await ref.read(listeningActionsProvider.notifier).saveCurrentPosition(
          bookId: widget.bookId,
          chapterIndex: newChapterIndex,
          segmentIndex: targetSegment,
        );
  }

  Future<void> _previousChapter() async {
    _resetSleepTimer(); // Reset sleep timer on user action
    final library = ref.read(libraryProvider).value;
    if (library == null) return;

    final book = library.books.where((b) => b.id == widget.bookId).firstOrNull;
    if (book == null) return;

    final currentChapterIndex = _currentChapterIndex;
    final playbackState = ref.read(playbackStateProvider);
    final currentSegmentIndex =
        playbackState.queue.isNotEmpty
            ? playbackState.currentIndex.clamp(
              0,
              playbackState.queue.length - 1,
            )
            : 0;

    if (currentChapterIndex <= 0) {
      AppHaptics.heavy(); // Boundary feedback
      return;
    }

    AppHaptics.medium(); // Chapter change feedback
    final newChapterIndex = currentChapterIndex - 1;

    // Save current chapter position before jumping
    await ref.read(listeningActionsProvider.notifier).saveChapterPosition(
          bookId: widget.bookId,
          chapterIndex: currentChapterIndex,
          segmentIndex: currentSegmentIndex,
        );

    // Get resume position for target chapter
    final targetSegment = await ref
        .read(listeningActionsProvider.notifier)
        .getResumePosition(widget.bookId, newChapterIndex);

    setState(() => _currentChapterIndex = newChapterIndex);

    await ref
        .read(playbackControllerProvider.notifier)
        .loadChapter(
          book: book,
          chapterIndex: newChapterIndex,
          startSegmentIndex: targetSegment,
          autoPlay: playbackState.isPlaying,
        );

    // Next/previous is sequential navigation - update primary to new chapter
    await ref.read(listeningActionsProvider.notifier).saveCurrentPosition(
          bookId: widget.bookId,
          chapterIndex: newChapterIndex,
          segmentIndex: targetSegment,
        );
  }

  Future<void> _setPlaybackRate(double rate) async {
    await ref.read(playbackControllerProvider.notifier).setPlaybackRate(rate);
  }

  void _increaseSpeed() {
    _resetSleepTimer(); // Reset sleep timer on user action
    final currentRate = ref.read(playbackStateProvider).playbackRate;
    final newRate = (currentRate + 0.25).clamp(0.5, 3.0);
    if (newRate == currentRate) {
      AppHaptics.heavy(); // At max speed limit
    } else {
      AppHaptics.selection(); // Speed step change
    }
    _setPlaybackRate(newRate);
  }

  void _decreaseSpeed() {
    _resetSleepTimer(); // Reset sleep timer on user action
    final currentRate = ref.read(playbackStateProvider).playbackRate;
    final newRate = (currentRate - 0.25).clamp(0.5, 3.0);
    if (newRate == currentRate) {
      AppHaptics.heavy(); // At min speed limit
    } else {
      AppHaptics.selection(); // Speed step change
    }
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

      // Only decrement when audio is actually playing
      final playbackState = ref.read(playbackStateProvider);
      if (!playbackState.isPlaying) {
        return; // Skip this tick, don't decrement
      }

      setState(() {
        if (_sleepTimeRemainingSeconds != null &&
            _sleepTimeRemainingSeconds! > 0) {
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

  /// Resets the sleep timer to its original duration when user takes an action.
  /// Only resets if a timer is currently active.
  void _resetSleepTimer() {
    if (_sleepTimerMinutes != null) {
      setState(() {
        _sleepTimeRemainingSeconds = _sleepTimerMinutes! * 60;
      });
    }
  }

  Future<void> _showSleepTimerPicker(
    BuildContext context,
    AppThemeColors colors,
  ) async {
    final selected = await SleepTimerPicker.show(
      context,
      currentMinutes: _sleepTimerMinutes,
    );
    // Only update if user made a selection (not dismissed)
    if (selected != _sleepTimerMinutes) {
      _setSleepTimer(selected);
    }
  }

  void _saveProgressAndPop() {
    // Don't save progress in preview mode
    if (!_isPreviewMode) {
      final playbackState = ref.read(playbackStateProvider);
      final currentChapterIndex = _currentChapterIndex;

      // Only save valid segment index (when queue is loaded)
      final queueLength = playbackState.queue.length;
      final segmentIndex =
          queueLength > 0
              ? playbackState.currentIndex.clamp(0, queueLength - 1)
              : 0;

      // Save to both tables for consistency
      ref
          .read(libraryProvider.notifier)
          .updateProgress(widget.bookId, currentChapterIndex, segmentIndex);

      ref
          .read(listeningActionsProvider.notifier)
          .saveChapterPosition(
            bookId: widget.bookId,
            chapterIndex: currentChapterIndex,
            segmentIndex: segmentIndex,
          );
    }
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
            colors: [colors.backgroundSecondary, colors.background],
          ),
        ),
        child: libraryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (e, st) => Center(
                child: Text(
                  'Error loading book',
                  style: TextStyle(color: colors.danger),
                ),
              ),
          data: (library) {
            final book =
                library.books.where((b) => b.id == widget.bookId).firstOrNull;
            if (book == null) {
              return Center(
                child: Text(
                  'Book not found',
                  style: TextStyle(color: colors.textSecondary),
                ),
              );
            }

            final chapterIdx = currentChapterIndex.clamp(
              0,
              book.chapters.length - 1,
            );
            final chapter = book.chapters[chapterIdx];
            final queue = playbackState.queue;
            final queueLength = queue.length;

            // Show loading state if queue hasn't been loaded yet (and not in preview mode)
            final isLoading = queueLength == 0 && !_isPreviewMode;

            final currentIndex =
                isLoading
                    ? 0
                    : playbackState.currentIndex.clamp(0, queueLength - 1);

            final isLandscape = _isLandscape(context);

            // Update system UI based on orientation
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateSystemUI(isLandscape);
            });

            final layout =
                isLandscape
                    ? LandscapeLayout(
                      book: book,
                      playbackState: playbackState,
                      queue: queue,
                      currentIndex: currentIndex,
                      queueLength: queueLength,
                      chapterIdx: chapterIdx,
                      isLoading: isLoading,
                      showCover: _showCover,
                      bookId: widget.bookId,
                      chapterIndex: _currentChapterIndex,
                      autoScrollEnabled: _autoScrollEnabled,
                      scrollController: _scrollController,
                      activeSegmentKey: _activeSegmentKey ??= GlobalKey(),
                      isPreviewMode: _isPreviewMode,
                      sleepTimerMinutes: _sleepTimerMinutes,
                      sleepTimeRemainingSeconds: _sleepTimeRemainingSeconds,
                      onBack: _saveProgressAndPop,
                      onSegmentTap: _isPreviewMode
                          ? _exitPreviewModeAndPlay
                          : _seekToSegment,
                      onAutoScrollDisabled:
                          () => setState(() => _autoScrollEnabled = false),
                      onJumpToCurrent: _jumpToCurrent,
                      onDecreaseSpeed: _decreaseSpeed,
                      onIncreaseSpeed: _increaseSpeed,
                      onPreviousSegment: _previousSegment,
                      onNextSegment: _nextSegment,
                      onTogglePlay: _togglePlay,
                      onShowSleepTimerPicker:
                          () => _showSleepTimerPicker(context, colors),
                      onPreviousChapter: _previousChapter,
                      onNextChapter: _nextChapter,
                      onSnapBack: () {},
                      errorBannerBuilder:
                          (error) => _buildErrorBanner(colors, error),
                    )
                    : PortraitLayout(
                      book: book,
                      chapter: chapter,
                      playbackState: playbackState,
                      queue: _isPreviewMode
                          ? _buildPreviewQueue()
                          : queue,
                      currentIndex: _isPreviewMode ? -1 : currentIndex,
                      queueLength: _isPreviewMode
                          ? (_previewSegments?.length ?? 0)
                          : queueLength,
                      chapterIdx: chapterIdx,
                      isLoading: isLoading,
                      showCover: _showCover,
                      bookId: widget.bookId,
                      chapterIndex: _currentChapterIndex,
                      autoScrollEnabled: _autoScrollEnabled,
                      scrollController: _scrollController,
                      activeSegmentKey: _activeSegmentKey ??= GlobalKey(),
                      isPreviewMode: _isPreviewMode,
                      onBack: _saveProgressAndPop,
                      onToggleView:
                          () => setState(() => _showCover = !_showCover),
                      onSegmentTap: _isPreviewMode
                          ? _exitPreviewModeAndPlay
                          : _seekToSegment,
                      onAutoScrollDisabled:
                          () => setState(() => _autoScrollEnabled = false),
                      onJumpToCurrent: _jumpToCurrent,
                      playbackControlsBuilder: () => _isPreviewMode
                          ? _buildPreviewModeControls(colors, book)
                          : _buildPlaybackControls(
                              colors,
                              playbackState,
                              currentIndex,
                              queueLength,
                              chapterIdx,
                              book.chapters.length,
                            ),
                      errorBannerBuilder:
                          (error) => _buildErrorBanner(colors, error),
                    );

            // Use overlay that fades out after orientation change
            if (!_showOverlay) {
              return layout;
            }

            return Stack(
              children: [
                layout,
                // Overlay that fades out after orientation change
                AnimatedBuilder(
                  animation: _orientationAnimController,
                  builder: (context, child) {
                    // Invert the animation: start opaque, fade to transparent
                    final overlayOpacity = 1.0 - _fadeAnimation.value;
                    return Container(
                      color: colors.background.withValues(
                        alpha: overlayOpacity.clamp(0.0, 1.0),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Build a queue from preview segments for display purposes
  List<AudioTrack> _buildPreviewQueue() {
    final segments = _previewSegments;
    if (segments == null) return [];

    return segments
        .map((s) {
          return AudioTrack(
              id: 'preview_${s.index}',
              text: s.text,
              chapterIndex: _currentChapterIndex,
              segmentIndex: s.index,
              estimatedDuration: s.estimatedDuration,
              segmentType: s.type,
              metadata: s.metadata,
            );
        })
        .toList();
  }

  /// Build controls for preview mode - shows mini player instead of full controls
  Widget _buildPreviewModeControls(AppThemeColors colors, Book book) {
    final playbackState = ref.watch(playbackStateProvider);
    final library = ref.watch(libraryProvider).value;

    // Get the currently playing book (might be different from previewed book)
    Book? playingBook = book; // Default to current book
    if (playbackState.bookId != null && playbackState.bookId != widget.bookId && library != null) {
      // Audio is playing a DIFFERENT book - get that book's info
      playingBook = library.books.where((b) => b.id == playbackState.bookId).firstOrNull;
    }

    // Find the chapter from the PLAYING book, not the previewed book
    final playingChapterIndex = _activePlaybackChapter ?? 0;
    final playingChapter = playingBook != null && playingChapterIndex < playingBook.chapters.length
        ? playingBook.chapters[playingChapterIndex]
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "Tap to play" hint
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border, width: 1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Tap any paragraph to start playing from there',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        // Mini player showing what's currently playing
        GestureDetector(
          onTap: () {
            final playbackState = ref.watch(playbackStateProvider);

            // Check if playing a different book
            if (playbackState.bookId != null && playbackState.bookId != widget.bookId) {
              // Navigate to the currently playing book's playback screen
              if (context.mounted) {
                context.go('/playback/${playbackState.bookId}');
              }
            } else if (_activePlaybackChapter != null) {
              // Same book - just exit preview mode
              setState(() {
                _currentChapterIndex = _activePlaybackChapter!;
                _isPreviewMode = false;
                _previewSegments = null;
                _activePlaybackChapter = null;
              });
            }
          },
          child: Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewPadding.bottom,
            ),
            decoration: BoxDecoration(
              color: colors.card,
              border: Border(
                top: BorderSide(color: colors.border, width: 1),
              ),
            ),
            child: SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // Book cover thumbnail (from PLAYING book, not previewed book)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: playingBook != null &&
                                playingBook.coverImagePath != null &&
                                File(playingBook.coverImagePath!).existsSync()
                            ? Image.file(
                                File(playingBook.coverImagePath!),
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: colors.primary.withValues(alpha: 0.1),
                                child: Icon(Icons.book, color: colors.primary),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Now playing info
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                playbackState.isPlaying
                                    ? Icons.equalizer
                                    : Icons.pause_circle_outline,
                                size: 14,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Now Playing',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            playingChapter?.title ?? 'Chapter ${playingChapterIndex + 1}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Play/Pause button
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _togglePlay,
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            playbackState.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            size: 28,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ),

                    // Go to playing chapter
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          if (_activePlaybackChapter != null) {
                            setState(() {
                              _currentChapterIndex = _activePlaybackChapter!;
                              _isPreviewMode = false;
                              _previewSegments = null;
                              _activePlaybackChapter = null;
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.chevron_right,
                            size: 24,
                            color: colors.textSecondary,
                          ),
                        ),
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

  Widget _buildErrorBanner(AppThemeColors colors, String error) {
    // Check if this is a voice unavailable error
    final isVoiceError =
        error.toLowerCase().contains('voice not available') ||
        error.toLowerCase().contains('voicenotavailable') ||
        error.toLowerCase().contains('no engine available');

    final errorWidget = Container(
      padding: const EdgeInsets.all(12),
      color: colors.danger.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(
            isVoiceError
                ? Icons.record_voice_over_outlined
                : Icons.error_outline,
            color: colors.danger,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isVoiceError ? 'Voice unavailable. Tap to fix.' : error,
              style: TextStyle(color: colors.danger, fontSize: 12),
            ),
          ),
          if (isVoiceError)
            Icon(Icons.chevron_right, color: colors.danger, size: 20),
        ],
      ),
    );

    if (isVoiceError) {
      return GestureDetector(
        onTap: () => _handleVoiceUnavailableError(error),
        child: errorWidget,
      );
    }

    return errorWidget;
  }

  Future<void> _handleVoiceUnavailableError(String error) async {
    // Extract voice ID from error if possible
    // Error format: "VoiceNotAvailableException: message (voice: voice_id)"
    String voiceId = 'unknown';
    final voiceMatch = RegExp(r'\(voice:\s*([^\)]+)\)').firstMatch(error);
    if (voiceMatch != null) {
      voiceId = voiceMatch.group(1) ?? 'unknown';
    } else {
      // Fallback to selected voice from settings
      voiceId = ref.read(settingsProvider).selectedVoice;
    }

    final action = await VoiceUnavailableDialog.show(
      context,
      voiceId: voiceId,
      errorMessage: error,
    );

    if (!mounted) return;

    switch (action) {
      case VoiceUnavailableAction.download:
        // Dialog already navigates to downloads
        break;
      case VoiceUnavailableAction.selectDifferent:
        // Navigate to settings to select a different voice
        context.push('/settings');
        break;
      case VoiceUnavailableAction.cancel:
        // Do nothing
        break;
    }
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
    _resetSleepTimer(); // Reset sleep timer on user action
    final notifier = ref.read(playbackControllerProvider.notifier);
    final playbackState = ref.read(playbackStateProvider);

    if (index >= 0 && index < playbackState.queue.length) {
      await notifier.seekToTrack(index, play: true);
      setState(() => _autoScrollEnabled = true);
    }
  }

  Widget _buildPlaybackControls(
    AppThemeColors colors,
    PlaybackState playbackState,
    int currentIndex,
    int queueLength,
    int chapterIdx,
    int chapterCount,
  ) {
    final queue = playbackState.queue;

    // Get segment readiness for synthesis status display
    final readinessKey = '${widget.bookId}:$_currentChapterIndex';
    final segmentReadinessAsync = ref.watch(
      segmentReadinessStreamProvider(readinessKey),
    );
    final segmentReadiness = segmentReadinessAsync.value ?? {};

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border, width: 1)),
            color: colors.background.withValues(alpha: 0.8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Segment seek slider
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    Text(
                      '${currentIndex + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SegmentSeekSlider(
                        // Key forces rebuild when readiness state changes
                        key: ValueKey('slider_${segmentReadiness.hashCode}'),
                        currentIndex: currentIndex,
                        totalSegments: queueLength,
                        colors: colors,
                        height: 4,
                        showPreview: true,
                        segmentReadiness: segmentReadiness,
                        segmentPreviewBuilder: (index) {
                          if (index >= 0 && index < queue.length) {
                            final text = queue[index].text;
                            // Return first ~50 characters
                            if (text.length > 50) {
                              return '${text.substring(0, 50)}...';
                            }
                            return text;
                          }
                          return '';
                        },
                        onSeek: _seekToSegment,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$queueLength',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Time remaining info
              TimeRemainingRow(
                bookId: widget.bookId,
                chapterIndex: _currentChapterIndex,
              ),

              // Speed and Sleep Timer controls
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Speed control
                    SpeedControl(
                      playbackRate: playbackState.playbackRate,
                      onDecrease: _decreaseSpeed,
                      onIncrease: _increaseSpeed,
                    ),

                    // Sleep timer
                    SleepTimerControl(
                      timerMinutes: _sleepTimerMinutes,
                      remainingSeconds: _sleepTimeRemainingSeconds,
                      onTap: () => _showSleepTimerPicker(context, colors),
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
                    PreviousChapterButton(
                      enabled: chapterIdx > 0,
                      onTap: _previousChapter,
                    ),

                    // Previous segment
                    PreviousSegmentButton(
                      enabled: currentIndex > 0,
                      onTap: _previousSegment,
                    ),

                    const SizedBox(width: 12),

                    // Play/Pause button
                    PlayButton(
                      isPlaying: playbackState.isPlaying,
                      isBuffering: playbackState.isBuffering,
                      onToggle: _togglePlay,
                    ),

                    const SizedBox(width: 12),

                    // Next segment
                    NextSegmentButton(
                      enabled: currentIndex < queueLength - 1,
                      onTap: _nextSegment,
                    ),

                    // Next chapter
                    NextChapterButton(
                      enabled: chapterIdx < chapterCount - 1,
                      onTap: _nextChapter,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
