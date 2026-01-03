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
  return ref.watch(ttsRoutingEngineProvider.future);
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
    // Create the controller when first accessed
    final engine = await ref.watch(routingEngineProvider.future);
    final cache = await ref.watch(audioCacheProvider.future);

    _controller = AudiobookPlaybackController(
      engine: engine,
      cache: cache,
      voiceIdResolver: (bookVoiceId) {
        final settings = ref.read(settingsProvider);
        return bookVoiceId ?? settings.selectedVoice;
      },
      onStateChange: (newState) {
        // Update Riverpod state when controller state changes
        state = AsyncData(newState);
      },
    );

    // Listen to state changes
    _stateSub = _controller!.stateStream.listen((newState) {
      state = AsyncData(newState);
    });

    ref.onDispose(() {
      _stateSub?.cancel();
      _controller?.dispose();
    });

    return _controller!.state;
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
    if (ctrl == null) return;

    if (chapterIndex < 0 || chapterIndex >= book.chapters.length) return;

    final chapter = book.chapters[chapterIndex];
    final segments = segmentText(chapter.content);

    // Convert segments to AudioTracks
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

    await ctrl.loadChapter(
      tracks: tracks,
      bookId: book.id,
      startIndex: startSegmentIndex.clamp(0, tracks.isEmpty ? 0 : tracks.length - 1),
      autoPlay: autoPlay,
    );
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
