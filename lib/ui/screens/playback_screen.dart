import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playback/playback.dart' hide SegmentReadinessTracker;

import '../../app/library_controller.dart';
import '../../app/playback/playback.dart';
import '../../app/playback_providers.dart';
import '../../app/settings_controller.dart';
import '../../app/granular_download_manager.dart';
import '../../utils/app_haptics.dart';
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
  final int? initialChapter;
  final int? initialSegment;
  final bool startPlayback;

  @override
  ConsumerState<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends ConsumerState<PlaybackScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _initialized = false;

  // Scroll controller for text view
  final ScrollController _scrollController = ScrollController();
  GlobalKey? _activeSegmentKey;

  // View mode: true = cover view, false = text view
  bool _showCover = false;

  // Orientation transition animation
  late AnimationController _orientationAnimController;
  late Animation<double> _fadeAnimation;
  bool _showOverlay = false;
  Size? _lastWindowSize;

  // Fullscreen mode for landscape
  bool _wasLandscape = false;

  bool _isLandscape(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > size.height;
  }

  @override
  void didChangeMetrics() {
    final window = WidgetsBinding.instance.platformDispatcher.views.first;
    final newSize = window.physicalSize;

    if (_lastWindowSize != null) {
      final wasLandscape = _lastWindowSize!.width > _lastWindowSize!.height;
      final isNowLandscape = newSize.width > newSize.height;

      if (wasLandscape != isNowLandscape && mounted) {
        setState(() {
          _showOverlay = true;
        });
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Trigger auto-save when app goes to background
      ref.read(playbackViewProvider.notifier).handleEvent(
            const AutoSaveTriggered(),
          );
    }
  }

  void _updateSystemUI(bool isLandscape) {
    if (isLandscape && !_wasLandscape) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
      _wasLandscape = true;
    } else if (!isLandscape && _wasLandscape) {
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
    WidgetsBinding.instance.addObserver(this);

    final window = WidgetsBinding.instance.platformDispatcher.views.first;
    _lastWindowSize = window.physicalSize;

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
    _orientationAnimController.value = 1.0;

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePlayback();
      _setupScrollCallback();
      _setupHapticListener();
    });
  }

  void _setupScrollCallback() {
    // Wire up scroll-to-segment callback from state machine
    ref.read(playbackViewProvider.notifier).onScrollToSegment = (index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveSegment();
      });
    };

    ref.read(playbackViewProvider.notifier).onNavigateBack = () {
      if (mounted) {
        context.pop();
      }
    };
  }

  void _setupHapticListener() {
    ref.listenManual(settingsProvider.select((s) => s.hapticFeedbackEnabled), (
      _,
      enabled,
    ) {
      AppHaptics.setEnabled(enabled);
    });
    AppHaptics.setEnabled(ref.read(settingsProvider).hapticFeedbackEnabled);
  }

  void _scrollToActiveSegment() {
    if (_activeSegmentKey?.currentContext == null) return;

    Scrollable.ensureVisible(
      _activeSegmentKey!.currentContext!,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: 0.15,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orientationAnimController.dispose();
    _restoreSystemUI();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializePlayback() async {
    if (_initialized) return;

    final libraryAsync = ref.read(libraryProvider);
    LibraryState? library;

    if (libraryAsync.hasValue) {
      library = libraryAsync.value;
    } else if (libraryAsync.isLoading) {
      library = await ref.read(libraryProvider.future);
    }

    if (library == null) return;

    _initialized = true;

    final book = library.books.where((b) => b.id == widget.bookId).firstOrNull;
    if (book == null) return;

    final chapterIndex = (widget.initialChapter ?? book.progress.chapterIndex)
        .clamp(0, book.chapters.length - 1);
    final segmentIndex = widget.initialSegment ?? book.progress.segmentIndex;

    final notifier = ref.read(playbackViewProvider.notifier);
    final playbackState = ref.read(playbackStateProvider);

    // Determine what to do based on current state
    final hasActivePlayback = playbackState.queue.isNotEmpty;
    final isPlayingSameBook =
        hasActivePlayback && playbackState.bookId == widget.bookId;
    final isPlayingDifferentBook =
        hasActivePlayback && playbackState.bookId != widget.bookId;

    if (isPlayingSameBook) {
      final activeChapter = playbackState.queue.first.chapterIndex;
      if (activeChapter != chapterIndex) {
        // Preview mode - viewing different chapter of same book
        notifier.selectChapter(bookId: widget.bookId, chapterIndex: chapterIndex);
      } else if (segmentIndex != playbackState.currentIndex) {
        // Same chapter, just seek to segment
        notifier.tapSegment(segmentIndex);
      }
    } else if (isPlayingDifferentBook && !widget.startPlayback) {
      // Preview mode - viewing different book
      notifier.selectChapter(bookId: widget.bookId, chapterIndex: chapterIndex);
    } else {
      // Start fresh playback
      notifier.startListening(
        bookId: widget.bookId,
        chapterIndex: chapterIndex,
        segmentIndex: segmentIndex,
      );
    }
  }

  Future<void> _togglePlay() async {
    final voiceId = ref.read(settingsProvider).selectedVoice;
    if (voiceId == VoiceIds.none) {
      if (mounted) {
        NoVoiceDialog.show(context);
      }
      return;
    }

    final viewState = ref.read(playbackViewProvider);
    if (viewState.isPlaying) {
      AppHaptics.medium();
    } else {
      AppHaptics.light();
    }

    ref.read(playbackViewProvider.notifier).togglePlayPause();
  }

  void _onSegmentTap(int index) {
    final viewState = ref.read(playbackViewProvider);

    if (viewState is PreviewState) {
      AppHaptics.medium();
    } else {
      AppHaptics.light();
    }

    ref.read(playbackViewProvider.notifier).tapSegment(index);
  }

  void _onUserScrolled() {
    ref.read(playbackViewProvider.notifier).userScrolled();
  }

  void _jumpToCurrent() {
    ref.read(playbackViewProvider.notifier).jumpToAudio();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActiveSegment();
    });
  }

  void _nextSegment() {
    AppHaptics.light();
    ref.read(playbackViewProvider.notifier).skipForward();
  }

  void _previousSegment() {
    AppHaptics.light();
    ref.read(playbackViewProvider.notifier).skipBackward();
  }

  Future<void> _nextChapter() async {
    final viewState = ref.read(playbackViewProvider);

    final (targetBookId, currentChapter, totalChapters) = switch (viewState) {
      ActiveState(:final bookId, :final chapterIndex, :final totalChapters) =>
        (bookId, chapterIndex, totalChapters),
      PreviewState(:final viewingBookId, :final viewingChapterIndex, :final viewingTotalChapters) =>
        (viewingBookId, viewingChapterIndex, viewingTotalChapters),
      _ => (null, null, null),
    };

    if (targetBookId == null || currentChapter == null || totalChapters == null) return;

    if (currentChapter >= totalChapters - 1) {
      AppHaptics.heavy();
      return;
    }

    AppHaptics.medium();
    ref.read(playbackViewProvider.notifier).selectChapter(
          bookId: targetBookId,
          chapterIndex: currentChapter + 1,
        );
  }

  Future<void> _previousChapter() async {
    final viewState = ref.read(playbackViewProvider);

    final (targetBookId, currentChapter) = switch (viewState) {
      ActiveState(:final bookId, :final chapterIndex) => (bookId, chapterIndex),
      PreviewState(:final viewingBookId, :final viewingChapterIndex) =>
        (viewingBookId, viewingChapterIndex),
      _ => (null, null),
    };

    if (targetBookId == null || currentChapter == null) return;

    if (currentChapter <= 0) {
      AppHaptics.heavy();
      return;
    }

    AppHaptics.medium();
    ref.read(playbackViewProvider.notifier).selectChapter(
          bookId: targetBookId,
          chapterIndex: currentChapter - 1,
        );
  }

  void _increaseSpeed() {
    final playbackState = ref.read(playbackStateProvider);
    final currentRate = playbackState.playbackRate;
    final newRate = (currentRate + 0.25).clamp(0.5, 3.0);
    if (newRate == currentRate) {
      AppHaptics.heavy();
    } else {
      AppHaptics.selection();
    }
    ref.read(playbackViewProvider.notifier).setSpeed(newRate);
  }

  void _decreaseSpeed() {
    final playbackState = ref.read(playbackStateProvider);
    final currentRate = playbackState.playbackRate;
    final newRate = (currentRate - 0.25).clamp(0.5, 3.0);
    if (newRate == currentRate) {
      AppHaptics.heavy();
    } else {
      AppHaptics.selection();
    }
    ref.read(playbackViewProvider.notifier).setSpeed(newRate);
  }

  Future<void> _showSleepTimerPicker(BuildContext context) async {
    final notifier = ref.read(playbackViewProvider.notifier);
    final currentMinutes = notifier.sleepTimerMinutes;

    final selected = await SleepTimerPicker.show(
      context,
      currentMinutes: currentMinutes,
    );

    if (selected != currentMinutes) {
      notifier.setSleepTimer(selected);
    }
  }

  void _showVoicePicker(BuildContext context) {
    final colors = context.appColors;
    final currentVoice = ref.read(settingsProvider).selectedVoice;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Consumer(
              builder: (context, ref, _) {
                final downloadState = ref.watch(granularDownloadManagerProvider);

                // Get ready voice IDs
                final readyVoiceIds = downloadState.maybeWhen(
                  data: (state) => state.readyVoices.map((v) => v.voiceId).toSet(),
                  orElse: () => <String>{},
                );

                // Filter voices by engine to only include downloaded ones
                final readyKokoroVoices = VoiceIds.kokoroVoices
                    .where((id) => readyVoiceIds.contains(id))
                    .toList();
                final readyPiperVoices = VoiceIds.piperVoices
                    .where((id) => readyVoiceIds.contains(id))
                    .toList();
                final readySupertonicVoices = VoiceIds.supertonicVoices
                    .where((id) => readyVoiceIds.contains(id))
                    .toList();

                final hasNoDownloadedVoices = readyKokoroVoices.isEmpty &&
                    readyPiperVoices.isEmpty &&
                    readySupertonicVoices.isEmpty;

                return Column(
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
                        'Select Voice',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                    ),
                    if (hasNoDownloadedVoices)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download_outlined, size: 48, color: colors.textTertiary),
                              const SizedBox(height: 16),
                              Text(
                                'No voices downloaded',
                                style: TextStyle(fontSize: 16, color: colors.textSecondary),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  context.push('/settings/downloads');
                                },
                                child: const Text('Download Voices'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: [
                            // Piper voices first (fastest engine)
                            if (readyPiperVoices.isNotEmpty) ...[
                              _buildVoiceSection('Piper Voices', readyPiperVoices, currentVoice, colors),
                            ],
                            // Supertonic voices second
                            if (readySupertonicVoices.isNotEmpty) ...[
                              _buildVoiceSection('Supertonic Voices', readySupertonicVoices, currentVoice, colors),
                            ],
                            // Kokoro voices last (highest quality)
                            if (readyKokoroVoices.isNotEmpty) ...[
                              _buildVoiceSection('Kokoro Voices', readyKokoroVoices, currentVoice, colors),
                            ],
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceSection(String title, List<String> voiceIds, String currentVoice, AppThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
        for (final voiceId in voiceIds)
          _VoiceOptionTile(
            voiceId: voiceId,
            isSelected: voiceId == currentVoice,
            onTap: () {
              ref.read(settingsProvider.notifier).setSelectedVoice(voiceId);
              // Trigger warmup for the new voice
              ref.read(playbackViewProvider.notifier).handleVoiceChange(voiceId);
              Navigator.pop(context);
            },
          ),
      ],
    );
  }

  void _saveProgressAndPop() {
    final viewState = ref.read(playbackViewProvider);

    // Save position if not in preview mode
    if (viewState is ActiveState) {
      ref.read(playbackViewProvider.notifier).handleEvent(
            const AutoSaveTriggered(),
          );
    }

    context.pop();
  }

  void _onMiniPlayerTap() {
    ref.read(playbackViewProvider.notifier).tapMiniPlayer();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final libraryAsync = ref.watch(libraryProvider);
    final viewState = ref.watch(playbackViewProvider);
    final playbackState = ref.watch(playbackStateProvider);

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
          error: (e, st) => Center(
            child: Text(
              'Error loading book',
              style: TextStyle(color: colors.danger),
            ),
          ),
          data: (library) {
            // Get book based on view state
            final viewingBookId = viewState.viewingBookId ?? widget.bookId;
            final book =
                library.books.where((b) => b.id == viewingBookId).firstOrNull;

            if (book == null) {
              return Center(
                child: Text(
                  'Book not found',
                  style: TextStyle(color: colors.textSecondary),
                ),
              );
            }

            // Derive values from state
            final (chapterIndex, segments, currentSegmentIndex, isPreview, isLoading) =
                _deriveFromState(viewState, playbackState, book);

            final chapterIdx = chapterIndex.clamp(0, book.chapters.length - 1);
            final chapter = book.chapters[chapterIdx];

            // Build queue from segments or playback state
            final queue = _buildQueue(viewState, playbackState, segments, chapterIdx);
            final queueLength = queue.length;

            final isLandscape = _isLandscape(context);

            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateSystemUI(isLandscape);
            });

            final layout = isLandscape
                ? LandscapeLayout(
                    book: book,
                    playbackState: playbackState,
                    queue: queue,
                    currentIndex: currentSegmentIndex,
                    queueLength: queueLength,
                    chapterIdx: chapterIdx,
                    isLoading: isLoading,
                    showCover: _showCover,
                    bookId: viewingBookId,
                    chapterIndex: chapterIdx,
                    autoScrollEnabled: viewState.shouldAutoScroll,
                    scrollController: _scrollController,
                    activeSegmentKey: _activeSegmentKey ??= GlobalKey(),
                    isPreviewMode: isPreview,
                    sleepTimerMinutes: ref.read(playbackViewProvider.notifier).sleepTimerMinutes,
                    sleepTimeRemainingSeconds: null, // TODO: expose from notifier
                    onBack: _saveProgressAndPop,
                    onSegmentTap: _onSegmentTap,
                    onAutoScrollDisabled: _onUserScrolled,
                    onJumpToCurrent: _jumpToCurrent,
                    onDecreaseSpeed: _decreaseSpeed,
                    onIncreaseSpeed: _increaseSpeed,
                    onPreviousSegment: _previousSegment,
                    onNextSegment: _nextSegment,
                    onTogglePlay: _togglePlay,
                    onShowSleepTimerPicker: () => _showSleepTimerPicker(context),
                    onPreviousChapter: _previousChapter,
                    onNextChapter: _nextChapter,
                    onSnapBack: () {},
                    warmupStatus: viewState.warmupStatus,
                    onVoiceTap: () => _showVoicePicker(context),
                    errorBannerBuilder: (error) => _buildErrorBanner(colors, error),
                  )
                : PortraitLayout(
                    book: book,
                    chapter: chapter,
                    playbackState: playbackState,
                    queue: queue,
                    currentIndex: currentSegmentIndex,
                    queueLength: queueLength,
                    chapterIdx: chapterIdx,
                    isLoading: isLoading,
                    showCover: _showCover,
                    bookId: viewingBookId,
                    chapterIndex: chapterIdx,
                    autoScrollEnabled: viewState.shouldAutoScroll,
                    scrollController: _scrollController,
                    activeSegmentKey: _activeSegmentKey ??= GlobalKey(),
                    isPreviewMode: isPreview,
                    onBack: _saveProgressAndPop,
                    onToggleView: () => setState(() => _showCover = !_showCover),
                    onSegmentTap: _onSegmentTap,
                    onAutoScrollDisabled: _onUserScrolled,
                    onJumpToCurrent: _jumpToCurrent,
                    warmupStatus: viewState.warmupStatus,
                    onVoiceTap: () => _showVoicePicker(context),
                    playbackControlsBuilder: () => isPreview
                        ? _buildPreviewModeControls(colors, viewState as PreviewState, library)
                        : _buildPlaybackControls(
                            colors,
                            viewState,
                            playbackState,
                            currentSegmentIndex,
                            queueLength,
                            chapterIdx,
                            book.chapters.length,
                          ),
                    errorBannerBuilder: (error) => _buildErrorBanner(colors, error),
                  );

            if (!_showOverlay) {
              return layout;
            }

            return Stack(
              children: [
                layout,
                AnimatedBuilder(
                  animation: _orientationAnimController,
                  builder: (context, child) {
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

  /// Derive UI values from the current state
  (int chapterIndex, List<Segment> segments, int currentSegmentIndex, bool isPreview, bool isLoading)
      _deriveFromState(
    PlaybackViewState viewState,
    PlaybackState playbackState,
    Book book,
  ) {
    switch (viewState) {
      case IdleState():
        return (0, const [], 0, false, false);

      case LoadingState(:final chapterIndex, :final segmentIndex):
        return (chapterIndex, const [], segmentIndex ?? 0, false, true);

      case ActiveState(
          :final chapterIndex,
          :final segments,
          :final segmentIndex
        ):
        return (chapterIndex, segments, segmentIndex, false, false);

      case PreviewState(
          :final viewingChapterIndex,
          :final viewingSegments,
          :final isLoadingPreview
        ):
        return (viewingChapterIndex, viewingSegments, -1, true, isLoadingPreview);
    }
  }

  /// Build the audio track queue for display.
  ///
  /// Design Decision: We have two sources of segment data:
  /// 1. ActiveState.segments - loaded from SQLite, available immediately on LoadingComplete
  /// 2. playbackState.queue - populated by PlaybackController.loadChapter(), has audio metadata
  ///
  /// During engine warmUp (which can take 2-45 seconds on iOS), loadChapter hasn't run yet,
  /// so playbackState.queue is empty. We use ActiveState.segments as fallback to show content
  /// immediately while warmUp runs. Once loadChapter completes, we switch to playbackState.queue
  /// which has richer metadata (synthesis status, cache status, actual duration).
  List<AudioTrack> _buildQueue(
    PlaybackViewState viewState,
    PlaybackState playbackState,
    List<Segment> segments,
    int chapterIndex,
  ) {
    if (viewState is PreviewState) {
      // In preview mode, build queue from preview segments
      return segments
          .map((s) => AudioTrack(
                id: 'preview_${s.index}',
                text: s.text,
                chapterIndex: chapterIndex,
                segmentIndex: s.index,
                estimatedDuration: s.estimatedDuration,
                segmentType: s.type,
                metadata: s.metadata,
              ))
          .toList();
    } else {
      // In active mode, prefer the actual playback queue if available
      // If playback queue is empty (e.g., during engine warmUp), use segments from ActiveState
      if (playbackState.queue.isNotEmpty) {
        return playbackState.queue;
      }
      
      // Fallback: build queue from segments during warmUp or before loadChapter completes
      return segments
          .map((s) => AudioTrack(
                id: 'pending_${s.index}',
                text: s.text,
                chapterIndex: chapterIndex,
                segmentIndex: s.index,
                estimatedDuration: s.estimatedDuration,
                segmentType: s.type,
                metadata: s.metadata,
              ))
          .toList();
    }
  }

  Widget _buildPreviewModeControls(
    AppThemeColors colors,
    PreviewState previewState,
    LibraryState library,
  ) {
    // Get the currently playing book
    Book? playingBook = library.books
        .where((b) => b.id == previewState.playingBookId)
        .firstOrNull;

    final playingChapterIndex = previewState.playingChapterIndex;
    final playingChapter = playingBook != null &&
            playingChapterIndex < playingBook.chapters.length
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
          onTap: _onMiniPlayerTap,
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
                    // Book cover thumbnail
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
                                previewState.isPlaying
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
                            playingChapter?.title ??
                                'Chapter ${playingChapterIndex + 1}',
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
                            previewState.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            size: 28,
                            color: colors.primary,
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
    final isVoiceError = error.toLowerCase().contains('voice not available') ||
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
    String voiceId = 'unknown';
    final voiceMatch = RegExp(r'\(voice:\s*([^\)]+)\)').firstMatch(error);
    if (voiceMatch != null) {
      voiceId = voiceMatch.group(1) ?? 'unknown';
    } else {
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
        break;
      case VoiceUnavailableAction.selectDifferent:
        context.push('/settings');
        break;
      case VoiceUnavailableAction.cancel:
        break;
    }
  }

  Widget _buildPlaybackControls(
    AppThemeColors colors,
    PlaybackViewState viewState,
    PlaybackState playbackState,
    int currentIndex,
    int queueLength,
    int chapterIdx,
    int chapterCount,
  ) {
    final queue = playbackState.queue;

    // Get segment readiness
    final bookId = viewState.playingBookId ?? widget.bookId;
    final chapterIndex = viewState is ActiveState ? viewState.chapterIndex : 0;
    final readinessKey = '$bookId:$chapterIndex';
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
                            if (text.length > 50) {
                              return '${text.substring(0, 50)}...';
                            }
                            return text;
                          }
                          return '';
                        },
                        onSeek: _onSegmentTap,
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
                bookId: bookId,
                chapterIndex: chapterIndex,
              ),

              // Speed and Sleep Timer controls
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SpeedControl(
                      playbackRate: playbackState.playbackRate,
                      onDecrease: _decreaseSpeed,
                      onIncrease: _increaseSpeed,
                    ),
                    SleepTimerControl(
                      timerMinutes: ref.read(playbackViewProvider.notifier).sleepTimerMinutes,
                      remainingSeconds: null, // TODO: expose from notifier
                      onTap: () => _showSleepTimerPicker(context),
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
                    PreviousChapterButton(
                      enabled: chapterIdx > 0,
                      onTap: _previousChapter,
                    ),
                    PreviousSegmentButton(
                      enabled: currentIndex > 0,
                      onTap: _previousSegment,
                    ),
                    const SizedBox(width: 12),
                    PlayButton(
                      isPlaying: playbackState.isPlaying,
                      isBuffering: playbackState.isBuffering,
                      onToggle: _togglePlay,
                    ),
                    const SizedBox(width: 12),
                    NextSegmentButton(
                      enabled: currentIndex < queueLength - 1,
                      onTap: _nextSegment,
                    ),
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

/// Voice option tile for the voice picker sheet.
class _VoiceOptionTile extends StatelessWidget {
  const _VoiceOptionTile({
    required this.voiceId,
    required this.isSelected,
    required this.onTap,
  });

  final String voiceId;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final displayName = VoiceIds.getDisplayName(voiceId);

    return ListTile(
      title: Text(
        displayName,
        style: TextStyle(
          color: colors.text,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: colors.primary)
          : null,
      onTap: onTap,
    );
  }
}
