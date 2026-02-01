import 'dart:async';

import 'package:audiobook_flutter_v2/app/library_controller.dart';
import 'package:audiobook_flutter_v2/app/listening_actions_notifier.dart';
import 'package:audiobook_flutter_v2/app/playback/state/playback_event.dart';
import 'package:audiobook_flutter_v2/app/playback/state/playback_side_effect.dart';
import 'package:audiobook_flutter_v2/app/playback/state/playback_state_machine.dart';
import 'package:audiobook_flutter_v2/app/playback/state/playback_view_state.dart';
import 'package:audiobook_flutter_v2/app/playback_providers.dart';
import 'package:audiobook_flutter_v2/app/settings_controller.dart';
import 'package:audiobook_flutter_v2/app/tts_providers.dart';
import 'package:core_domain/core_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for the playback view state machine
final playbackViewProvider =
    NotifierProvider<PlaybackViewNotifier, PlaybackViewState>(
  PlaybackViewNotifier.new,
);

/// Notifier that manages playback view state using the state machine.
///
/// This notifier:
/// 1. Holds the current [PlaybackViewState]
/// 2. Processes [PlaybackEvent]s through the pure transition function
/// 3. Executes [PlaybackSideEffect]s
class PlaybackViewNotifier extends Notifier<PlaybackViewState> {
  Timer? _autoSaveTimer;
  Timer? _sleepTimer;
  int? _sleepTimerMinutes;

  /// Mutex to ensure events are processed sequentially
  /// Prevents race conditions when multiple events arrive concurrently
  Completer<void>? _eventLock;

  /// Callback for scroll-to-segment requests from side effects
  void Function(int segmentIndex)? onScrollToSegment;

  /// Callback for navigation requests
  void Function()? onNavigateBack;

  StreamSubscription<void>? _chapterEndedSubscription;
  
  @override
  PlaybackViewState build() {
    // Listen for playback state changes from the audio controller
    ref.listen(playbackStateProvider, (previous, next) {
      // previous is null on first call, skip that case
      if (previous == null) return;

      // Handle playing state changes
      if (next.isPlaying != previous.isPlaying) {
        _handleEvent(PlaybackStateChanged(next.isPlaying));
      }

      // Handle segment index changes (natural playback progress)
      if (next.currentIndex != previous.currentIndex &&
          next.currentIndex >= 0) {
        _handleEvent(SegmentAdvanced(next.currentIndex));
      }
    });

    // Listen for ChapterEnded events from the global stream.
    // This breaks the circular dependency between playbackControllerProvider
    // and this notifier - the controller fires events via a stream,
    // and we listen here outside of Riverpod's dependency tracking.
    _chapterEndedSubscription?.cancel();
    _chapterEndedSubscription = chapterEndedStream.listen((_) {
      debugPrint('[PlaybackViewNotifier] Received ChapterEnded from stream');
      // Use Future.microtask to defer the state modification to avoid
      // modifying provider state during widget tree building
      Future.microtask(() => _handleEvent(const ChapterEnded()));
    });

    // Clean up timers and subscriptions on dispose
    ref.onDispose(() {
      _autoSaveTimer?.cancel();
      _sleepTimer?.cancel();
      _chapterEndedSubscription?.cancel();
    });

    return const IdleState();
  }

  /// Process an event through the state machine
  /// Events are queued and processed sequentially to prevent race conditions
  void handleEvent(PlaybackEvent event) {
    _handleEvent(event);
  }

  Future<void> _handleEvent(PlaybackEvent event) async {
    // Wait for any in-progress event to complete
    while (_eventLock != null) {
      await _eventLock!.future;
    }
    
    // Acquire the lock for this event
    _eventLock = Completer<void>();
    
    try {
      await _processEvent(event);
    } finally {
      // Release the lock
      final lock = _eventLock;
      _eventLock = null;
      lock?.complete();
    }
  }

  Future<void> _processEvent(PlaybackEvent event) async {
    final currentState = state;
    
    // Debug logging for ChapterEnded event
    // Debug logging for ChapterEnded event
    if (event is ChapterEnded) {
      debugPrint('[PlaybackViewNotifier] ChapterEnded received!');
      debugPrint('[PlaybackViewNotifier] Current state type: ${currentState.runtimeType}');
      if (currentState is ActiveState) {
        debugPrint('[PlaybackViewNotifier] Current chapterIndex: ${currentState.chapterIndex}');
        debugPrint('[PlaybackViewNotifier] Total chapters: ${currentState.totalChapters}');
        debugPrint('[PlaybackViewNotifier] Has next? ${currentState.chapterIndex < currentState.totalChapters - 1}');
      } else {
        debugPrint('[PlaybackViewNotifier] WARNING: State is NOT ActiveState when ChapterEnded fired!');
      }
    }
    
    final (newState, effects) = transition(currentState, event);

    // Debug logging for LoadingComplete
    if (event is LoadingComplete) {
      debugPrint('[PlaybackViewNotifier] ${DateTime.now().toIso8601String()} LoadingComplete received!');
      debugPrint('[PlaybackViewNotifier] ${DateTime.now().toIso8601String()} segments count: ${event.segments.length}');
      debugPrint('[PlaybackViewNotifier] ${DateTime.now().toIso8601String()} Current state: ${currentState.runtimeType}');
      debugPrint('[PlaybackViewNotifier] ${DateTime.now().toIso8601String()} New state: ${newState.runtimeType}');
      if (newState is ActiveState) {
        debugPrint('[PlaybackViewNotifier] ${DateTime.now().toIso8601String()} ActiveState segments: ${newState.segments.length}');
      }
    }

    // Debug logging for state transition result
    if (event is ChapterEnded) {
      debugPrint('[PlaybackViewNotifier] ${DateTime.now().toIso8601String()} After ChapterEnded transition:');
      debugPrint('[PlaybackViewNotifier] ${DateTime.now().toIso8601String()} New state type: ${newState.runtimeType}');
      debugPrint('[PlaybackViewNotifier] ${DateTime.now().toIso8601String()} Effects: $effects');
    }

    // Update state if changed
    if (newState != currentState) {
      state = newState;

      // Manage auto-save timer based on state
      _manageAutoSaveTimer(newState);
    }

    // Execute side effects sequentially (await each one)
    // This ensures SavePosition completes before NavigateBack
    for (final effect in effects) {
      await _executeSideEffect(effect);
    }
  }

  /// Start playback from book details or library
  Future<void> startListening({
    required String bookId,
    required int chapterIndex,
    int segmentIndex = 0,
  }) async {
    handleEvent(StartListeningPressed(
      bookId: bookId,
      chapterIndex: chapterIndex,
      segmentIndex: segmentIndex,
    ));
  }

  /// Select a chapter (may enter preview mode)
  void selectChapter({
    required String bookId,
    required int chapterIndex,
  }) {
    handleEvent(ChapterSelected(
      bookId: bookId,
      chapterIndex: chapterIndex,
    ));
  }

  /// Tap a segment (seek in Active, commit in Preview)
  void tapSegment(int segmentIndex) {
    handleEvent(SegmentTapped(segmentIndex));
  }

  /// Toggle play/pause
  void togglePlayPause() {
    handleEvent(const PlayPauseToggled());
  }

  /// User scrolled the text view
  void userScrolled() {
    handleEvent(const UserScrolled());
  }

  /// Jump to current audio position
  void jumpToAudio() {
    handleEvent(const JumpToAudioPressed());
  }

  /// Skip forward one segment
  void skipForward() {
    handleEvent(const SkipForward());
  }

  /// Skip backward one segment
  void skipBackward() {
    handleEvent(const SkipBackward());
  }

  /// Stop playback
  void stop() {
    handleEvent(const StopPressed());
  }

  /// Handle back navigation
  void back() {
    handleEvent(const BackPressed());
  }

  /// Tap mini player (return to playing content)
  void tapMiniPlayer() {
    handleEvent(const MiniPlayerTapped());
  }

  /// Change playback speed
  void setSpeed(double speed) {
    handleEvent(SpeedChanged(speed));
  }

  /// Set sleep timer (null to cancel)
  void setSleepTimer(int? minutes) {
    handleEvent(SleepTimerSet(minutes));
  }

  /// Get current sleep timer minutes (null if not set)
  int? get sleepTimerMinutes => _sleepTimerMinutes;

  /// Handle voice change - warmup the new voice engine.
  /// This runs the warmUp in the background (unawaited) to avoid blocking the UI.
  void handleVoiceChange(String voiceId) {
    final current = state;
    if (current is! ActiveState) return;
    
    // Update status to warming
    _updateWarmupStatus(EngineWarmupStatus.warming);
    
    // Run warmUp in background (unawaited) to avoid blocking UI
    debugPrint('[WarmUp] ${DateTime.now().toIso8601String()} Starting background warmUp for $voiceId');
    unawaited(
      ref.read(ttsRoutingEngineProvider.future).then((engine) {
        return engine.warmUp(voiceId);
      }).then((success) {
        debugPrint('[WarmUp] ${DateTime.now().toIso8601String()} WarmUp completed: $success');
        _updateWarmupStatus(
          success ? EngineWarmupStatus.ready : EngineWarmupStatus.failed,
          errorMessage: success ? null : 'Voice warmup failed',
        );
      }).catchError((e) {
        debugPrint('[WarmUp] ${DateTime.now().toIso8601String()} Failed to warm up TTS engine: $e');
        _updateWarmupStatus(EngineWarmupStatus.failed, errorMessage: e.toString());
      }),
    );
  }
  
  /// Update the warmup status in the current state.
  /// 
  /// This is used to show loading progress in the voice selection button.
  void _updateWarmupStatus(EngineWarmupStatus status, {String? errorMessage}) {
    final current = state;
    if (current is ActiveState) {
      state = current.copyWith(
        warmupStatus: status,
        warmupError: errorMessage,
      );
      debugPrint('[WarmUp] ${DateTime.now().toIso8601String()} Status updated to: $status');
    }
  }

  // ===========================================================================
  // Side Effect Execution
  // ===========================================================================

  Future<void> _executeSideEffect(PlaybackSideEffect effect) async {
    try {
      switch (effect) {
        case LoadChapter(:final bookId, :final chapterIndex, :final segmentIndex, :final autoPlay):
          await _loadChapter(bookId, chapterIndex, segmentIndex, autoPlay);

        case LoadPreviewSegments(:final bookId, :final chapterIndex):
          await _loadPreviewSegments(bookId, chapterIndex);

        case StartPlayback(:final bookId, :final chapterIndex, :final segmentIndex):
          await _startPlayback(bookId, chapterIndex, segmentIndex);

        case SeekTo(:final segmentIndex):
          await _seekTo(segmentIndex);

        case PlayAudio():
          await _play();

        case PauseAudio():
          await _pause();

        case StopAudio():
          await _stop();

        case ScrollToSegment(:final segmentIndex):
          onScrollToSegment?.call(segmentIndex);

        case ShowError(:final message):
          _showError(message);

        case NavigateToChapter(:final bookId, :final chapterIndex):
          _navigateToChapter(bookId, chapterIndex);

        case SavePosition(:final bookId, :final chapterIndex, :final segmentIndex):
          await _savePosition(bookId, chapterIndex, segmentIndex);

        case MarkChapterComplete(:final bookId, :final chapterIndex):
          await _markChapterComplete(bookId, chapterIndex);

        case MarkBookComplete(:final bookId):
          await _markBookComplete(bookId);

        case SetPlaybackSpeed(:final speed):
          await _setPlaybackSpeed(speed);

        case StartSleepTimer(:final minutes):
          _startSleepTimer(minutes);

        case CancelSleepTimer():
          _cancelSleepTimer();

        case CancelLoading():
          _cancelLoading();

        case NavigateBack():
          onNavigateBack?.call();

        case SkipForwardSegment():
          await _skipForward();

        case SkipBackwardSegment():
          await _skipBackward();
      }
    } catch (e, stackTrace) {
      debugPrint('Error executing side effect $effect: $e\n$stackTrace');
      _handleEvent(LoadingFailed(e.toString()));
    }
  }

  Future<void> _loadChapter(
    String bookId,
    int chapterIndex,
    int? segmentIndex,
    bool autoPlay,
  ) async {
    try {
      // Get book info
      final library = ref.read(libraryProvider).value;
      if (library == null) {
        throw Exception('Library not loaded');
      }
      final book = library.books.where((b) => b.id == bookId).firstOrNull;
      if (book == null) {
        throw Exception('Book not found: $bookId');
      }
      final libraryController = ref.read(libraryProvider.notifier);

      // Check if the requested chapter is playable
      final isPlayable = await libraryController.isChapterPlayable(bookId, chapterIndex);
      
      int actualChapterIndex = chapterIndex;
      
      if (!isPlayable) {
        // Find the next playable chapter (forward navigation by default)
        final nextPlayable = await libraryController.findNextPlayableChapter(bookId, chapterIndex);
        if (nextPlayable != null) {
          actualChapterIndex = nextPlayable;
          debugPrint('Auto-skipping empty chapter $chapterIndex -> $actualChapterIndex');
        } else {
          // No playable chapter forward - this means we've reached the end of playable content
          // Dispatch NoMorePlayableContent event to transition to book complete
          debugPrint('No more playable chapters after $chapterIndex, treating as book complete');
          
          // Find the last playable chapter we had (for marking complete)
          final prevPlayable = await libraryController.findPreviousPlayableChapter(bookId, chapterIndex);
          if (prevPlayable != null) {
            await libraryController.markChapterComplete(bookId, prevPlayable);
          }
          
          _handleEvent(const NoMorePlayableContent());
          return;
        }
      }

      // Load segments from SQLite (this is fast - instant)
      final segments = await libraryController.getSegmentsForChapter(bookId, actualChapterIndex);

      // Get chapter title
      final chapter = book.chapters[actualChapterIndex];
      final chapterTitle = chapter.title;

      // Emit loading complete IMMEDIATELY so UI shows content
      // Don't wait for playback controller setup
      _handleEvent(LoadingComplete(
        segments: segments,
        bookTitle: book.title,
        chapterTitle: chapterTitle,
        totalChapters: book.chapters.length,
        actualChapterIndex: actualChapterIndex,  // Pass actual chapter (may differ from requested)
      ));
      
      // Verify state changed to ActiveState
      debugPrint('[_loadChapter] ${DateTime.now().toIso8601String()} After LoadingComplete, state is: ${state.runtimeType}');
      if (state is ActiveState) {
        debugPrint('[_loadChapter] ${DateTime.now().toIso8601String()} ActiveState segments: ${(state as ActiveState).segments.length}');
      }

      // Pre-warm the TTS engine for the selected voice BEFORE loading the chapter.
      // This initializes the CoreML/ONNX models before playback starts,
      // preventing UI jank during the first synthesis.
      // Note: UI already shows content (LoadingComplete emitted above), so user
      // sees the chapter while warmUp runs.
      final selectedVoice = ref.read(settingsProvider).selectedVoice;
      debugPrint('[WarmUp] ${DateTime.now().toIso8601String()} Selected voice: $selectedVoice');
      
      // Check if warmUp is already in progress from voice change listener
      // If so, skip the awaited warmUp call to avoid blocking the UI
      final currentWarmupStatus = (state is ActiveState) 
          ? (state as ActiveState).warmupStatus 
          : EngineWarmupStatus.notStarted;
      final isAlreadyWarming = currentWarmupStatus == EngineWarmupStatus.warming;
      final isAlreadyReady = currentWarmupStatus == EngineWarmupStatus.ready;
      
      // Track if warmUp was started and needs to trigger autoPlay when done
      bool needsAutoPlayAfterWarmUp = false;
      
      if (isAlreadyReady) {
        debugPrint('[WarmUp] ${DateTime.now().toIso8601String()} Engine already ready, no warmup needed');
        // Engine already warmed - proceed directly to autoPlay
      } else if (isAlreadyWarming) {
        debugPrint('[WarmUp] ${DateTime.now().toIso8601String()} WarmUp already in progress, skipping duplicate call');
        // Don't start another warmUp - the existing one will update status when done
        needsAutoPlayAfterWarmUp = autoPlay;
      } else if (selectedVoice != VoiceIds.none) {
        // Always run warmUp in background (unawaited) to avoid blocking UI
        // This is a change from the previous behavior where autoPlay awaited warmUp.
        // The tradeoff: first synthesis may be slower while CoreML compiles,
        // but the UI won't freeze for 20-30 seconds.
        _updateWarmupStatus(EngineWarmupStatus.warming);
        needsAutoPlayAfterWarmUp = autoPlay;
        
        debugPrint('[WarmUp] ${DateTime.now().toIso8601String()} Starting background warmUp for $selectedVoice');
        unawaited(
          ref.read(ttsRoutingEngineProvider.future).then((engine) {
            return engine.warmUp(selectedVoice);
          }).then((success) {
            debugPrint('[WarmUp] ${DateTime.now().toIso8601String()} WarmUp completed: $success');
            _updateWarmupStatus(
              success ? EngineWarmupStatus.ready : EngineWarmupStatus.failed,
              errorMessage: success ? null : 'Voice warmup failed',
            );
            // If we deferred autoPlay, start it now
            if (success && needsAutoPlayAfterWarmUp) {
              debugPrint('[WarmUp] ${DateTime.now().toIso8601String()} Starting deferred playback');
              final ctrl = ref.read(playbackControllerProvider.notifier).controller;
              ctrl?.play();
            }
          }).catchError((e) {
            debugPrint('[WarmUp] ${DateTime.now().toIso8601String()} Failed to warm up TTS engine: $e');
            _updateWarmupStatus(EngineWarmupStatus.failed, errorMessage: e.toString());
          }),
        );
      } else {
        // No voice selected - mark as ready (device voice or none)
        _updateWarmupStatus(EngineWarmupStatus.ready);
      }

      // THEN setup playback controller asynchronously
      // This can take time (cache checks, synthesis setup) but UI is already showing
      // If warmUp is in progress, load chapter but DON'T autoPlay - we'll start playback
      // after warmUp completes to avoid synthesis timeout during CoreML compilation.
      final effectiveAutoPlay = autoPlay && !needsAutoPlayAfterWarmUp;
      debugPrint('[_loadChapter] ${DateTime.now().toIso8601String()} Calling loadChapter with autoPlay=$effectiveAutoPlay (requested=$autoPlay, deferred=$needsAutoPlayAfterWarmUp)');
      
      final playbackController = ref.read(playbackControllerProvider.notifier);
      await playbackController.loadChapter(
        book: book,
        chapterIndex: actualChapterIndex,
        startSegmentIndex: segmentIndex ?? 0,
        autoPlay: effectiveAutoPlay,
      );
    } catch (e) {
      _handleEvent(LoadingFailed(e.toString()));
    }
  }

  Future<void> _loadPreviewSegments(String bookId, int chapterIndex) async {
    try {
      // Get book info
      final library = ref.read(libraryProvider).value;
      if (library == null) {
        throw Exception('Library not loaded');
      }
      final book = library.books.where((b) => b.id == bookId).firstOrNull;
      if (book == null) {
        throw Exception('Book not found: $bookId');
      }
      final libraryController = ref.read(libraryProvider.notifier);

      // Check if the requested chapter is playable
      final isPlayable = await libraryController.isChapterPlayable(bookId, chapterIndex);
      
      int actualChapterIndex = chapterIndex;
      
      if (!isPlayable) {
        // Find the next playable chapter (forward navigation by default)
        final nextPlayable = await libraryController.findNextPlayableChapter(bookId, chapterIndex);
        if (nextPlayable != null) {
          actualChapterIndex = nextPlayable;
          debugPrint('Preview: Auto-skipping empty chapter $chapterIndex -> $actualChapterIndex');
        } else {
          // No playable chapter found forward, try backward
          final prevPlayable = await libraryController.findPreviousPlayableChapter(bookId, chapterIndex);
          if (prevPlayable != null) {
            actualChapterIndex = prevPlayable;
            debugPrint('Preview: Auto-skipping empty chapter $chapterIndex -> $actualChapterIndex (backward)');
          } else {
            // No playable chapters at all!
            throw Exception('No playable chapters found in this book');
          }
        }
      }

      // Load segments
      final segments = await libraryController.getSegmentsForChapter(bookId, actualChapterIndex);

      // Get chapter title
      final chapter = book.chapters[actualChapterIndex];

      // Emit preview loaded event
      _handleEvent(PreviewSegmentsLoaded(
        segments: segments,
        chapterTitle: chapter.title,
        actualChapterIndex: actualChapterIndex,  // Pass actual chapter (may differ from requested)
      ));
    } catch (e) {
      _handleEvent(LoadingFailed('Failed to load preview: $e'));
    }
  }

  Future<void> _startPlayback(
      String bookId, int chapterIndex, int segmentIndex) async {
    final playbackController = ref.read(playbackControllerProvider.notifier);
    await playbackController.seekToTrack(segmentIndex);
    await playbackController.play();
  }

  Future<void> _seekTo(int segmentIndex) async {
    final playbackController = ref.read(playbackControllerProvider.notifier);
    await playbackController.seekToTrack(segmentIndex);
  }

  Future<void> _play() async {
    final playbackController = ref.read(playbackControllerProvider.notifier);
    await playbackController.play();
  }

  Future<void> _pause() async {
    final playbackController = ref.read(playbackControllerProvider.notifier);
    await playbackController.pause();
  }

  Future<void> _stop() async {
    final playbackController = ref.read(playbackControllerProvider.notifier);
    await playbackController.stop();
  }

  Future<void> _skipForward() async {
    final playbackController = ref.read(playbackControllerProvider.notifier);
    await playbackController.nextTrack();
  }

  Future<void> _skipBackward() async {
    final playbackController = ref.read(playbackControllerProvider.notifier);
    await playbackController.previousTrack();
  }

  Future<void> _savePosition(
      String bookId, int chapterIndex, int segmentIndex) async {
    try {
      final listeningActions = ref.read(listeningActionsProvider.notifier);
      await listeningActions.saveChapterPosition(
        bookId: bookId,
        chapterIndex: chapterIndex,
        segmentIndex: segmentIndex,
      );
    } catch (e) {
      debugPrint('Error saving position: $e');
    }
  }

  Future<void> _markChapterComplete(String bookId, int chapterIndex) async {
    try {
      final libraryController = ref.read(libraryProvider.notifier);
      await libraryController.markChapterComplete(bookId, chapterIndex);
    } catch (e) {
      debugPrint('Error marking chapter complete: $e');
    }
  }

  Future<void> _markBookComplete(String bookId) async {
    try {
      final libraryController = ref.read(libraryProvider.notifier);
      await libraryController.markBookComplete(bookId);
    } catch (e) {
      debugPrint('Error marking book complete: $e');
    }
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    final playbackController = ref.read(playbackControllerProvider.notifier);
    await playbackController.setPlaybackRate(speed);

    // Also save to settings
    ref.read(settingsProvider.notifier).setDefaultPlaybackRate(speed);
  }

  void _startSleepTimer(int minutes) {
    _cancelSleepTimer();
    _sleepTimerMinutes = minutes;
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      _sleepTimerMinutes = null;
      _handleEvent(const SleepTimerExpired());
    });
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerMinutes = null;
  }

  void _cancelLoading() {
    // Cancel any ongoing async operations
    // The state machine handles state recovery
  }

  void _showError(String message) {
    // This would typically show a snackbar or dialog
    // For now, just log it
    debugPrint('Playback error: $message');
  }

  void _navigateToChapter(String bookId, int chapterIndex) {
    // Navigation is handled by the UI via callbacks
    // This is just a placeholder for side effect handling
  }

  // ===========================================================================
  // Auto-save Timer Management
  // ===========================================================================

  void _manageAutoSaveTimer(PlaybackViewState newState) {
    if (newState.shouldAutoSavePosition) {
      // Start auto-save timer if not already running
      _autoSaveTimer ??= Timer.periodic(
        const Duration(seconds: 30),
        (_) => _handleEvent(const AutoSaveTriggered()),
      );
    } else {
      // Cancel auto-save timer
      _autoSaveTimer?.cancel();
      _autoSaveTimer = null;
    }
  }
}

// ===========================================================================
// Convenience Providers
// ===========================================================================

/// Provider for checking if we're in preview mode
final isPreviewModeProvider = Provider<bool>((ref) {
  final state = ref.watch(playbackViewProvider);
  return state is PreviewState;
});

/// Provider for the currently playing book ID (if any)
final playingBookIdProvider = Provider<String?>((ref) {
  final state = ref.watch(playbackViewProvider);
  return state.playingBookId;
});

/// Provider for the currently viewing book ID
final viewingBookIdProvider = Provider<String?>((ref) {
  final state = ref.watch(playbackViewProvider);
  return state.viewingBookId;
});

/// Provider for whether playback controls should be shown
final showPlaybackControlsProvider = Provider<bool>((ref) {
  final state = ref.watch(playbackViewProvider);
  return state.showFullPlaybackControls;
});

/// Provider for whether the mini player should be shown globally
final showMiniPlayerProvider = Provider<bool>((ref) {
  final state = ref.watch(playbackViewProvider);
  return state.showMiniPlayerGlobally;
});

/// Provider for current segments to display
final displaySegmentsProvider = Provider<List<Segment>>((ref) {
  final state = ref.watch(playbackViewProvider);
  return switch (state) {
    ActiveState(:final segments) => segments,
    PreviewState(:final viewingSegments) => viewingSegments,
    _ => const [],
  };
});

/// Provider for current segment index (for highlighting)
final currentSegmentIndexProvider = Provider<int>((ref) {
  final state = ref.watch(playbackViewProvider);
  return switch (state) {
    ActiveState(:final segmentIndex) => segmentIndex,
    // In preview, don't highlight any segment
    PreviewState() => -1,
    _ => 0,
  };
});

/// Provider for whether to show loading indicator
final isLoadingPlaybackProvider = Provider<bool>((ref) {
  final state = ref.watch(playbackViewProvider);
  return state.showLoadingIndicator;
});

/// Provider for auto-scroll state
final autoScrollEnabledProvider = Provider<bool>((ref) {
  final state = ref.watch(playbackViewProvider);
  return state.shouldAutoScroll;
});

/// Provider for whether to show jump-to-audio button
final showJumpToAudioProvider = Provider<bool>((ref) {
  final state = ref.watch(playbackViewProvider);
  return state.showJumpToAudioButton;
});
