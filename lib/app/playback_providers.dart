import 'dart:async';
import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playback/playback.dart' hide PrefetchMode;
import 'package:playback/playback.dart' as playback show PrefetchMode, AdaptivePrefetchConfig;
import 'package:tts_engines/tts_engines.dart';

import 'app_paths.dart';
import 'audio_service_handler.dart';
import 'config/config_providers.dart';
import 'config/runtime_playback_config.dart' as app_config show PrefetchMode;
import 'settings_controller.dart';
import 'tts_providers.dart';
import '../main.dart' show initAudioService;
import '../utils/app_logger.dart';

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
  // Use IntelligentCacheManager as the single source of truth for audio cache
  final manager = await ref.watch(intelligentCacheManagerProvider.future);
  return manager;
});

/// Provider for the intelligent cache manager (Phase 3: Cache management).
/// Provides quota control, eviction scoring, and usage stats.
final intelligentCacheManagerProvider = FutureProvider<IntelligentCacheManager>((ref) async {
  final paths = await ref.watch(appPathsProvider.future);
  final settings = ref.watch(settingsProvider);
  
  final manager = IntelligentCacheManager(
    cacheDir: paths.audioCacheDir,
    metadataFile: File('${paths.audioCacheDir.path}/.cache_metadata.json'),
    quotaSettings: CacheQuotaSettings.fromGB(settings.cacheQuotaGB),
  );
  
  await manager.initialize();
  
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Provider for cache usage statistics.
/// Refreshes when quota settings change or on demand.
final cacheUsageStatsProvider = FutureProvider<CacheUsageStats>((ref) async {
  final manager = await ref.watch(intelligentCacheManagerProvider.future);
  return manager.getUsageStats();
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

/// Provider for adaptive prefetch configuration.
///
/// Bridges the app's RuntimePlaybackConfig to the playback package's
/// AdaptivePrefetchConfig. Converts PrefetchMode enums between packages.
final adaptivePrefetchConfigProvider = Provider<playback.AdaptivePrefetchConfig>((ref) {
  final runtimeConfig = ref.watch(runtimePlaybackConfigProvider).value;
  
  // Convert app's PrefetchMode to playback's PrefetchMode
  final prefetchMode = _convertPrefetchMode(
    runtimeConfig?.prefetchMode ?? app_config.PrefetchMode.adaptive,
  );
  
  return playback.AdaptivePrefetchConfig(prefetchMode: prefetchMode);
});

/// Convert between the two PrefetchMode enums.
///
/// The app defines PrefetchMode in runtime_playback_config.dart,
/// while the playback package defines it in adaptive_prefetch.dart.
/// They have the same values but are different types due to package boundaries.
playback.PrefetchMode _convertPrefetchMode(app_config.PrefetchMode appMode) {
  return switch (appMode) {
    app_config.PrefetchMode.adaptive => playback.PrefetchMode.adaptive,
    app_config.PrefetchMode.aggressive => playback.PrefetchMode.aggressive,
    app_config.PrefetchMode.conservative => playback.PrefetchMode.conservative,
    app_config.PrefetchMode.off => playback.PrefetchMode.off,
  };
}

/// Provider for the audio service handler (system media controls).
/// Uses lazy initialization to avoid blocking app startup.
final audioServiceHandlerProvider = FutureProvider<AudioServiceHandler>((ref) async {
  return await initAudioService();
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
  JustAudioOutput? _audioOutput;
  AudioServiceHandler? _audioServiceHandler;

  @override
  FutureOr<PlaybackState> build() async {
    PlaybackLogger.info('[PlaybackProvider] Initializing playback controller...');
    
    try {
      // Use ref.read instead of ref.watch for dependencies that shouldn't 
      // cause rebuilds during playback (like the routing engine which depends
      // on download state)
      PlaybackLogger.info('[PlaybackProvider] Loading routing engine...');
      final engine = await ref.read(routingEngineProvider.future);
      PlaybackLogger.info('[PlaybackProvider] Routing engine loaded successfully');
      
      PlaybackLogger.info('[PlaybackProvider] Loading audio cache...');
      final cache = await ref.read(audioCacheProvider.future);
      PlaybackLogger.info('[PlaybackProvider] Audio cache loaded successfully');

      PlaybackLogger.info('[PlaybackProvider] Loading smart synthesis manager...');
      final smartSynthesisManager = ref.read(smartSynthesisManagerProvider);
      PlaybackLogger.info('[PlaybackProvider] Smart synthesis manager loaded');

      // Phase 2: Resource monitor for battery-aware prefetch
      PlaybackLogger.info('[PlaybackProvider] Loading resource monitor...');
      final resourceMonitor = ref.read(resourceMonitorProvider);
      PlaybackLogger.info('[PlaybackProvider] Resource monitor loaded (mode: ${resourceMonitor.currentMode})');

      // Create audio output externally so we can access its player
      // for audio service integration (system media controls)
      PlaybackLogger.info('[PlaybackProvider] Creating audio output...');
      _audioOutput = JustAudioOutput();

      PlaybackLogger.info('[PlaybackProvider] Creating AudiobookPlaybackController...');
      _controller = AudiobookPlaybackController(
        engine: engine,
        cache: cache,
        audioOutput: _audioOutput,
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
        // Prevent play button flicker during segment transitions
        onPlayIntentOverride: (override) {
          _audioServiceHandler?.setPlayIntentOverride(override);
        },
      );
      PlaybackLogger.info('[PlaybackProvider] Controller created successfully');

      // Listen to state changes
      _stateSub = _controller!.stateStream.listen((newState) {
        state = AsyncData(newState);
      });
      
      // Connect audio output player to audio service for system media controls
      await _connectAudioService();

      ref.onDispose(() {
        PlaybackLogger.info('[PlaybackProvider] Disposing playback controller');
        _stateSub?.cancel();
        _controller?.dispose();
      });

      PlaybackLogger.info('[PlaybackProvider] Initialization complete');
      return _controller!.state;
    } catch (e, st) {
      PlaybackLogger.error('[PlaybackProvider] ERROR during initialization: $e');
      PlaybackLogger.error('[PlaybackProvider] Stack trace: $st');
      rethrow;
    }
  }
  
  /// Connect the audio player to the audio service for system media controls.
  Future<void> _connectAudioService() async {
    PlaybackLogger.info('[PlaybackProvider] _connectAudioService() called');
    
    final player = _audioOutput?.player;
    if (player == null) {
      PlaybackLogger.info('[PlaybackProvider] No player available for audio service');
      return;
    }
    
    PlaybackLogger.info('[PlaybackProvider] Player available, connecting to audio service...');
    
    try {
      PlaybackLogger.info('[PlaybackProvider] Calling audioServiceHandlerProvider.future...');
      final handler = await ref.read(audioServiceHandlerProvider.future);
      PlaybackLogger.info('[PlaybackProvider] Got handler: ${handler.runtimeType}');
      
      // Store reference so controller callbacks can access it
      _audioServiceHandler = handler;
      
      handler.connectPlayer(player);
      PlaybackLogger.info('[PlaybackProvider] Player connected to handler');
      
      // Wire up callbacks so media control buttons trigger our controller
      handler.onPlayCallback = () {
        PlaybackLogger.info('[PlaybackProvider] onPlayCallback triggered from media controls');
        _controller?.play();
      };
      handler.onPauseCallback = () {
        PlaybackLogger.info('[PlaybackProvider] onPauseCallback triggered from media controls');
        _controller?.pause();
      };
      handler.onStopCallback = () {
        PlaybackLogger.info('[PlaybackProvider] onStopCallback triggered from media controls');
        _controller?.pause();
      };
      handler.onSkipToNextCallback = () {
        PlaybackLogger.info('[PlaybackProvider] onSkipToNextCallback triggered from media controls');
        _controller?.nextTrack();
      };
      handler.onSkipToPreviousCallback = () {
        PlaybackLogger.info('[PlaybackProvider] onSkipToPreviousCallback triggered from media controls');
        _controller?.previousTrack();
      };
      handler.onSpeedChangeCallback = (speed) {
        PlaybackLogger.info('[PlaybackProvider] Speed changed from media controls: ${speed}x');
        // The player speed is already set by the handler, just log it
      };
      
      PlaybackLogger.info('[PlaybackProvider] Audio service callbacks wired up');
    } catch (e, st) {
      PlaybackLogger.error('[PlaybackProvider] Failed to connect audio service: $e');
      PlaybackLogger.error('[PlaybackProvider] Stack trace: $st');
      // Non-fatal - app works without system media controls
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
      PlaybackLogger.error('[PlaybackProvider] ERROR: Controller is null, cannot load chapter');
      return;
    }

    if (chapterIndex < 0 || chapterIndex >= book.chapters.length) {
      PlaybackLogger.error('[PlaybackProvider] ERROR: Invalid chapter index $chapterIndex (book has ${book.chapters.length} chapters)');
      return;
    }

    PlaybackLogger.info('[PlaybackProvider] Loading chapter $chapterIndex for book "${book.title}"');
    PlaybackLogger.info('[PlaybackProvider] Start segment: $startSegmentIndex, autoPlay: $autoPlay');

    final chapter = book.chapters[chapterIndex];
    PlaybackLogger.info('[PlaybackProvider] Chapter: "${chapter.title}", content length: ${chapter.content.length} chars');
    
    final segmentStart = DateTime.now();
    final segments = segmentText(chapter.content);
    final segmentDuration = DateTime.now().difference(segmentStart);
    PlaybackLogger.info('[PlaybackProvider] Segmented into ${segments.length} segments in ${segmentDuration.inMilliseconds}ms');

    // Handle empty chapter - create a single "empty" track to show in UI
    if (segments.isEmpty) {
      PlaybackLogger.error('[PlaybackProvider] WARNING: Chapter has no segments, creating empty track');
      final emptyTrack = AudioTrack(
        id: IdGenerator.audioTrackId(book.id, chapterIndex, 0),
        text: '(This chapter has no readable content)',
        chapterIndex: chapterIndex,
        segmentIndex: 0,
        estimatedDuration: Duration.zero,
      );
      PlaybackLogger.info('[PlaybackProvider] Loading controller with 1 empty track');
      await ctrl.loadChapter(
        tracks: [emptyTrack],
        bookId: book.id,
        startIndex: 0,
        autoPlay: false,  // Don't auto-play empty content
      );
      PlaybackLogger.info('[PlaybackProvider] Empty chapter loaded successfully');
      return;
    }

    // Convert segments to AudioTracks
    PlaybackLogger.info('[PlaybackProvider] Converting ${segments.length} segments to AudioTracks...');
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
    PlaybackLogger.info('[PlaybackProvider] Loading ${tracks.length} tracks into controller (starting at index $clampedStart)');

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
      PlaybackLogger.error('[PlaybackProvider] Error checking cache: $e');
      // Continue anyway - readiness will update as segments are synthesized
    }

    try {
      await ctrl.loadChapter(
        tracks: tracks,
        bookId: book.id,
        startIndex: clampedStart,
        autoPlay: autoPlay,
      );
      PlaybackLogger.info('[PlaybackProvider] Chapter loaded successfully');
      
      // Always update audio service with media metadata for lock screen/notification controls
      // This ensures metadata is set even when the user manually presses play later
      await _updateAudioServiceMetadata(book: book, chapterIndex: chapterIndex);
    } catch (e, st) {
      PlaybackLogger.error('[PlaybackProvider] ERROR loading chapter: $e');
      PlaybackLogger.error('[PlaybackProvider] Stack trace: $st');
      rethrow;
    }
  }
  
  /// Update audio service with current book/chapter metadata.
  /// This makes the notification/lock screen show the correct info.
  Future<void> _updateAudioServiceMetadata({
    required Book book,
    required int chapterIndex,
  }) async {
    // ignore: avoid_print
    print('[PlaybackProvider] _updateAudioServiceMetadata called: ${book.title}, chapter $chapterIndex');
    
    try {
      final handler = await ref.read(audioServiceHandlerProvider.future);
      final chapter = book.chapters[chapterIndex];
      // ignore: avoid_print
      print('[PlaybackProvider] Got handler, setting mediaItem...');
      
      // Get artwork URI from cover image path
      Uri? artUri;
      String? artCacheFile;
      if (book.coverImagePath != null) {
        final coverFile = File(book.coverImagePath!);
        if (await coverFile.exists()) {
          artUri = coverFile.uri;
          // iOS requires artCacheFile in extras for lock screen artwork
          artCacheFile = coverFile.path;
        }
      }
      
      // ignore: avoid_print
      print('[PlaybackProvider] Calling updateNowPlaying: title=${chapter.title}, album=${book.title}');
      handler.updateNowPlaying(
        id: book.id,
        title: chapter.title,
        album: book.title,
        artist: book.author,
        artUri: artUri,
        extras: {
          'chapterIndex': chapterIndex,
          'totalChapters': book.chapters.length,
          // iOS-specific: local file path for artwork
          if (artCacheFile != null) 'artCacheFile': artCacheFile,
        },
      );
      // ignore: avoid_print
      print('[PlaybackProvider] updateNowPlaying called successfully');
    } catch (e, st) {
      // ignore: avoid_print
      print('[PlaybackProvider] ERROR updating audio service metadata: $e');
      // ignore: avoid_print
      print('[PlaybackProvider] Stack: $st');
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
