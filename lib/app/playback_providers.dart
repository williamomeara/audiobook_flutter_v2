import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playback/playback.dart';
import 'package:tts_engines/tts_engines.dart';

import 'app_paths.dart';
import 'settings_controller.dart';
import 'tts_providers.dart';

/// Global segment readiness tracker singleton.
/// This is used to track synthesis state for UI opacity feedback.
/// Key format: "bookId:chapterIndex"
class SegmentReadinessTracker {
  SegmentReadinessTracker._();
  static final instance = SegmentReadinessTracker._();
  
  final Map<String, Map<int, SegmentReadiness>> _readiness = {};
  final _controllers = <String, StreamController<Map<int, SegmentReadiness>>>{};
  
  /// Get current readiness for a chapter.
  Map<int, SegmentReadiness> getReadiness(String key) {
    return _readiness[key] ?? {};
  }
  
  /// Get readiness for a specific segment.
  SegmentReadiness? getForSegment(String key, int index) {
    return _readiness[key]?[index];
  }
  
  /// Get opacity for a specific segment.
  double opacityForSegment(String key, int index) {
    return _readiness[key]?[index]?.opacity ?? 0.4;
  }
  
  /// Stream of readiness changes for a chapter.
  Stream<Map<int, SegmentReadiness>> stream(String key) {
    _controllers[key] ??= StreamController.broadcast();
    return _controllers[key]!.stream;
  }
  
  /// Mark segment as synthesis started.
  void onSynthesisStarted(String key, int index) {
    _readiness[key] ??= {};
    _readiness[key]![index] = SegmentReadiness.synthesizing(index);
    _notify(key);
  }
  
  /// Mark segment as ready.
  void onSynthesisComplete(String key, int index) {
    _readiness[key] ??= {};
    _readiness[key]![index] = SegmentReadiness.ready(index);
    _notify(key);
  }
  
  /// Mark segment as queued.
  void onSegmentQueued(String key, int index) {
    _readiness[key] ??= {};
    final current = _readiness[key]![index];
    if (current?.state == SegmentState.ready ||
        current?.state == SegmentState.synthesizing) {
      return;
    }
    _readiness[key]![index] = SegmentReadiness.queued(index);
    _notify(key);
  }
  
  /// Initialize from cached segments.
  void initializeFromCache(String key, List<int> cachedIndices) {
    _readiness[key] = {};
    for (final index in cachedIndices) {
      _readiness[key]![index] = SegmentReadiness.ready(index);
    }
    _notify(key);
  }
  
  /// Reset readiness for a chapter.
  void reset(String key) {
    _readiness[key]?.clear();
    _notify(key);
  }
  
  void _notify(String key) {
    if (_controllers[key] != null && !_controllers[key]!.isClosed) {
      _controllers[key]!.add(_readiness[key] ?? {});
    }
  }
}

/// Provider that streams segment readiness for a chapter.
final segmentReadinessStreamProvider = StreamProvider.family<Map<int, SegmentReadiness>, String>(
  (ref, key) async* {
    // Emit current state first
    yield SegmentReadinessTracker.instance.getReadiness(key);
    // Then emit updates
    await for (final update in SegmentReadinessTracker.instance.stream(key)) {
      yield update;
    }
  },
);

/// Simple provider for current segment readiness (non-reactive snapshot).
final segmentReadinessProvider = Provider.family<Map<int, SegmentReadiness>, String>(
  (ref, key) => SegmentReadinessTracker.instance.getReadiness(key),
);

/// Provider for smart synthesis manager
/// Creates appropriate manager based on selected voice engine type
/// Returns null if smart synthesis is disabled in settings
final smartSynthesisManagerProvider = Provider<SmartSynthesisManager?>((ref) {
  // Check if smart synthesis is enabled
  final smartSynthesisEnabled = ref.watch(settingsProvider.select((s) => s.smartSynthesisEnabled));
  
  if (!smartSynthesisEnabled) {
    return null;  // Disabled - will use JIT synthesis
  }
  
  // Get selected voice and determine engine type
  final selectedVoice = ref.watch(settingsProvider.select((s) => s.selectedVoice));
  final engineType = VoiceIds.engineFor(selectedVoice);
  
  // Select appropriate manager based on engine type
  switch (engineType) {
    case EngineType.supertonic:
      return SupertonicSmartSynthesis();
    case EngineType.piper:
      return PiperSmartSynthesis();
    case EngineType.kokoro:
      // Kokoro RTF > 1.0 means it's slower than real-time
      // Use Supertonic strategy as fallback until Kokoro-specific strategy is implemented
      // TODO: Implement KokoroSmartSynthesis with pre-synthesis workflow
      return SupertonicSmartSynthesis();
    case EngineType.device:
      // Device TTS doesn't need smart synthesis (no caching)
      return null;
  }
});

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

/// Provider for the resource monitor (Phase 2: Battery-aware prefetch).
/// Singleton that monitors battery level and charging state.
final resourceMonitorProvider = Provider<ResourceMonitor>((ref) {
  final monitor = ResourceMonitor();
  // Initialize in background - don't block
  monitor.initialize();
  ref.onDispose(() => monitor.dispose());
  return monitor;
});

/// Provider for the engine config manager (Phase 4: Auto-tuning).
/// Manages per-engine, per-device configurations.
final engineConfigManagerProvider = Provider<DeviceEngineConfigManager>((ref) {
  final manager = DeviceEngineConfigManager();
  // Initialize in background
  manager.initialize();
  return manager;
});

/// Provider for the device profiler (Phase 4: Auto-tuning).
/// Profiles device performance to determine optimal synthesis settings.
final deviceProfilerProvider = Provider<DevicePerformanceProfiler>((ref) {
  return DevicePerformanceProfiler();
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

      print('[PlaybackProvider] Loading smart synthesis manager...');
      final smartSynthesisManager = ref.read(smartSynthesisManagerProvider);
      print('[PlaybackProvider] Smart synthesis manager loaded');

      // Phase 2: Resource monitor for battery-aware prefetch
      print('[PlaybackProvider] Loading resource monitor...');
      final resourceMonitor = ref.read(resourceMonitorProvider);
      print('[PlaybackProvider] Resource monitor loaded (mode: ${resourceMonitor.currentMode})');

      print('[PlaybackProvider] Creating AudiobookPlaybackController...');
      _controller = AudiobookPlaybackController(
        engine: engine,
        cache: cache,
        // Voice selection is global-only for now (per-book voice not implemented)
        voiceIdResolver: (_) => ref.read(settingsProvider).selectedVoice,
        smartSynthesisManager: smartSynthesisManager,
        resourceMonitor: resourceMonitor,  // Phase 2
        onStateChange: (newState) {
          // Update Riverpod state when controller state changes
          state = AsyncData(newState);
        },
        // Wire up segment readiness callbacks for UI feedback
        onSegmentSynthesisStarted: (bookId, chapterIndex, segmentIndex) {
          final key = '$bookId:$chapterIndex';
          SegmentReadinessTracker.instance.onSynthesisStarted(key, segmentIndex);
        },
        onSegmentSynthesisComplete: (bookId, chapterIndex, segmentIndex) {
          final key = '$bookId:$chapterIndex';
          SegmentReadinessTracker.instance.onSynthesisComplete(key, segmentIndex);
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

    // Initialize segment readiness tracker - check which segments are already cached
    final readinessKey = '${book.id}:$chapterIndex';
    SegmentReadinessTracker.instance.reset(readinessKey);
    
    try {
      // Check cache for already-ready segments
      final cache = await ref.read(audioCacheProvider.future);
      final voiceId = ref.read(settingsProvider).selectedVoice;
      final playbackRate = ref.read(settingsProvider).defaultPlaybackRate;
      
      for (var i = 0; i < tracks.length; i++) {
        final cacheKey = CacheKeyGenerator.generate(
          voiceId: voiceId,
          text: tracks[i].text,
          playbackRate: CacheKeyGenerator.getSynthesisRate(playbackRate),
        );
        if (await cache.isReady(cacheKey)) {
          SegmentReadinessTracker.instance.onSynthesisComplete(readinessKey, i);
        }
      }
    } catch (e) {
      print('[PlaybackProvider] Error checking cache: $e');
      // Continue anyway - readiness will update as segments are synthesized
    }

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
