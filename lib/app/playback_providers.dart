import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playback/playback.dart';
import 'package:tts_engines/tts_engines.dart';

import 'app_paths.dart';
import 'settings_controller.dart';
import 'tts_providers.dart';

/// Provider for the audio cache.
/// Re-exported from tts_providers for backwards compatibility.
final audioCacheProvider = FutureProvider<AudioCache>((ref) async {
  final paths = await ref.watch(appPathsProvider.future);
  return FileAudioCache(cacheDir: paths.audioCacheDir);
});

/// Provider for the routing engine.
/// Uses ttsRoutingEngineProvider which has all AI voice engines registered.
final routingEngineProvider = FutureProvider<RoutingEngine>((ref) async {
  return ref.read(ttsRoutingEngineProvider.future);
});

/// Provider for the playback controller.
/// Creates a single instance of the controller for the app.
final playbackControllerProvider =
    AsyncNotifierProvider<PlaybackControllerNotifier, PlaybackState>(() {
  return PlaybackControllerNotifier();
});

/// Notifier that wraps AudiobookPlaybackController and exposes it via Riverpod.
class PlaybackControllerNotifier extends AsyncNotifier<PlaybackState> {
  AudiobookPlaybackController? _controller;
  StreamSubscription<PlaybackState>? _stateSub;

  @override
  FutureOr<PlaybackState> build() async {
    print('[PlaybackProvider] Initializing playback controller...');
    
    try {
      // Use ref.read instead of ref.watch for dependencies that shouldn't 
      // cause rebuilds during playback (like the routing engine which depends
      // on download state)
      print('[PlaybackProvider] Loading routing engine...');
      final engine = await ref.read(routingEngineProvider.future);
      print('[PlaybackProvider] Routing engine loaded successfully');
      
      print('[PlaybackProvider] Loading audio cache...');
      final cache = await ref.read(audioCacheProvider.future);
      print('[PlaybackProvider] Audio cache loaded successfully');

      print('[PlaybackProvider] Creating AudiobookPlaybackController...');
      _controller = AudiobookPlaybackController(
        engine: engine,
        cache: cache,
        // Voice selection is global-only for now (per-book voice not implemented)
        voiceIdResolver: (_) => ref.read(settingsProvider).selectedVoice,
        onStateChange: (newState) {
          // Update Riverpod state when controller state changes
          state = AsyncData(newState);
        },
      );
      print('[PlaybackProvider] Controller created successfully');

      // Listen to state changes
      _stateSub = _controller!.stateStream.listen((newState) {
        state = AsyncData(newState);
      });

      ref.onDispose(() {
        print('[PlaybackProvider] Disposing playback controller');
        _stateSub?.cancel();
        _controller?.dispose();
      });

      print('[PlaybackProvider] Initialization complete');
      return _controller!.state;
    } catch (e, st) {
      print('[PlaybackProvider] ERROR during initialization: $e');
      print('[PlaybackProvider] Stack trace: $st');
      rethrow;
    }
  }

  /// Get the underlying controller.
  AudiobookPlaybackController? get controller => _controller;

  /// Load a chapter for playback.
  Future<void> loadChapter({
    required Book book,
    required int chapterIndex,
    int startSegmentIndex = 0,
    bool autoPlay = true,
  }) async {
    final ctrl = _controller;
    if (ctrl == null) {
      print('[PlaybackProvider] ERROR: Controller is null, cannot load chapter');
      return;
    }

    if (chapterIndex < 0 || chapterIndex >= book.chapters.length) {
      print('[PlaybackProvider] ERROR: Invalid chapter index $chapterIndex (book has ${book.chapters.length} chapters)');
      return;
    }

    print('[PlaybackProvider] Loading chapter $chapterIndex for book "${book.title}"');
    print('[PlaybackProvider] Start segment: $startSegmentIndex, autoPlay: $autoPlay');

    final chapter = book.chapters[chapterIndex];
    print('[PlaybackProvider] Chapter: "${chapter.title}", content length: ${chapter.content.length} chars');
    
    final segmentStart = DateTime.now();
    final segments = segmentText(chapter.content);
    final segmentDuration = DateTime.now().difference(segmentStart);
    print('[PlaybackProvider] Segmented into ${segments.length} segments in ${segmentDuration.inMilliseconds}ms');

    // Handle empty chapter - create a single "empty" track to show in UI
    if (segments.isEmpty) {
      print('[PlaybackProvider] WARNING: Chapter has no segments, creating empty track');
      final emptyTrack = AudioTrack(
        id: IdGenerator.audioTrackId(book.id, chapterIndex, 0),
        text: '(This chapter has no readable content)',
        chapterIndex: chapterIndex,
        segmentIndex: 0,
        estimatedDuration: Duration.zero,
      );
      print('[PlaybackProvider] Loading controller with 1 empty track');
      await ctrl.loadChapter(
        tracks: [emptyTrack],
        bookId: book.id,
        startIndex: 0,
        autoPlay: false,  // Don't auto-play empty content
      );
      print('[PlaybackProvider] Empty chapter loaded successfully');
      return;
    }

    // Convert segments to AudioTracks
    print('[PlaybackProvider] Converting ${segments.length} segments to AudioTracks...');
    final tracks = segments.asMap().entries.map((entry) {
      final segment = entry.value;
      return AudioTrack(
        id: IdGenerator.audioTrackId(book.id, chapterIndex, entry.key),
        text: segment.text,
        chapterIndex: chapterIndex,
        segmentIndex: entry.key,
        estimatedDuration: segment.estimatedDuration,
      );
    }).toList();

    final clampedStart = startSegmentIndex.clamp(0, tracks.length - 1);
    print('[PlaybackProvider] Loading ${tracks.length} tracks into controller (starting at index $clampedStart)');

    try {
      await ctrl.loadChapter(
        tracks: tracks,
        bookId: book.id,
        startIndex: clampedStart,
        autoPlay: autoPlay,
      );
      print('[PlaybackProvider] Chapter loaded successfully');
    } catch (e, st) {
      print('[PlaybackProvider] ERROR loading chapter: $e');
      print('[PlaybackProvider] Stack trace: $st');
      rethrow;
    }
  }

  /// Play current track.
  Future<void> play() async {
    await _controller?.play();
  }

  /// Pause playback.
  Future<void> pause() async {
    await _controller?.pause();
  }

  /// Seek to a specific track/segment.
  Future<void> seekToTrack(int index, {bool play = true}) async {
    await _controller?.seekToTrack(index, play: play);
  }

  /// Go to next track.
  Future<void> nextTrack() async {
    await _controller?.nextTrack();
  }

  /// Go to previous track.
  Future<void> previousTrack() async {
    await _controller?.previousTrack();
  }

  /// Set playback rate.
  Future<void> setPlaybackRate(double rate) async {
    await _controller?.setPlaybackRate(rate);
  }

  /// Notify of user interaction.
  void notifyUserInteraction() {
    _controller?.notifyUserInteraction();
  }
}

/// Provider for the current playback state (convenience alias).
final playbackStateProvider = Provider<PlaybackState>((ref) {
  final asyncState = ref.watch(playbackControllerProvider);
  return asyncState.value ?? PlaybackState.empty;
});

/// Provider to check if playback is active.
final isPlayingProvider = Provider<bool>((ref) {
  return ref.watch(playbackStateProvider).isPlaying;
});

/// Provider to check if buffering.
final isBufferingProvider = Provider<bool>((ref) {
  return ref.watch(playbackStateProvider).isBuffering;
});

/// Provider for current track.
final currentTrackProvider = Provider<AudioTrack?>((ref) {
  return ref.watch(playbackStateProvider).currentTrack;
});
