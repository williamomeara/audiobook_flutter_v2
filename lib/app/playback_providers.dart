import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playback/playback.dart' hide PrefetchMode;
import 'package:playback/playback.dart' as playback show PrefetchMode, AdaptivePrefetchConfig;
import 'package:tts_engines/tts_engines.dart';

import 'app_paths.dart';
import 'audio_service_handler.dart';
import 'cache/cache_reconciliation_service.dart';
import 'config/config_providers.dart';
import 'config/runtime_playback_config.dart' as app_config show PrefetchMode;
import 'database/database.dart';
import 'library_controller.dart';
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
    PlaybackLogger.debug('[SegmentReadinessTracker] onSynthesisStarted: key=$key, index=$index');
    _notify(key);
  }
  
  /// Mark segment as ready.
  void onSynthesisComplete(String key, int index) {
    _readiness[key] ??= {};
    _readiness[key]![index] = SegmentReadiness.ready(index);
    PlaybackLogger.debug('[SegmentReadinessTracker] onSynthesisComplete: key=$key, index=$index');
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
    // Ensure controller exists before notifying
    _controllers[key] ??= StreamController.broadcast();
    if (!_controllers[key]!.isClosed) {
      _controllers[key]!.add(_readiness[key] ?? {});
    }
  }
  
  /// Mark segment as not ready (evicted or missing from cache).
  void onSegmentEvicted(String key, int index) {
    _readiness[key] ??= {};
    final current = _readiness[key]![index];
    // Only downgrade if it was previously ready
    if (current?.state == SegmentState.ready) {
      _readiness[key]![index] = SegmentReadiness(
        segmentIndex: index,
        state: SegmentState.notQueued,
      );
      _notify(key);
    }
  }
  
  /// Verify readiness against actual cache state.
  /// Returns list of segments that were marked ready but aren't in cache.
  Future<List<int>> verifyAgainstCache({
    required String key,
    required Future<bool> Function(int index) isSegmentCached,
    int? startIndex,
    int windowSize = 10,
  }) async {
    final readiness = _readiness[key];
    if (readiness == null) return [];
    
    final start = startIndex ?? 0;
    final evictedSegments = <int>[];
    
    // Check segments in the window ahead of current position
    for (int i = start; i < start + windowSize; i++) {
      final segmentReadiness = readiness[i];
      if (segmentReadiness?.state == SegmentState.ready) {
        // Segment marked as ready - verify it's actually cached
        final isCached = await isSegmentCached(i);
        if (!isCached) {
          // Cache miss! Update tracker
          onSegmentEvicted(key, i);
          evictedSegments.add(i);
        }
      }
    }
    
    return evictedSegments;
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

/// Provider for the audio cache.
/// Re-exported from tts_providers for backwards compatibility.
/// Uses ref.read to avoid cascading rebuilds during initialization.
final audioCacheProvider = FutureProvider<AudioCache>((ref) async {
  // Use IntelligentCacheManager as the single source of truth for audio cache
  final manager = await ref.read(intelligentCacheManagerProvider.future);
  return manager;
});

/// Provider for the intelligent cache manager (Phase 3: Cache management).
/// Provides quota control, eviction scoring, and usage stats.
/// Uses SQLite for cache metadata storage (migrated from JSON).
/// Uses ref.read to avoid cascading rebuilds during initialization.
///
/// Includes automatic cache reconciliation on startup and periodic reconciliation
/// to ensure disk files and database entries stay in sync.
final intelligentCacheManagerProvider = FutureProvider<IntelligentCacheManager>((ref) async {
  final paths = await ref.read(appPathsProvider.future);
  final settings = ref.read(settingsProvider);

  // Get database instance and create SQLite storage
  final db = await AppDatabase.instance;
  final cacheDao = CacheDao(db);
  final settingsDao = SettingsDao(db);
  final storage = SqliteCacheMetadataStorage(cacheDao, settingsDao);

  final manager = IntelligentCacheManager(
    cacheDir: paths.audioCacheDir,
    storage: storage,
    quotaSettings: CacheQuotaSettings.fromGB(settings.cacheQuotaGB),
  );

  await manager.initialize();

  // Run startup reconciliation to sync disk files with database
  final reconciliation = CacheReconciliationService(cache: manager);
  final result = await reconciliation.reconcile();

  developer.log(
    '📦 Cache reconciliation: ${result.summary}',
    name: 'CacheManager',
  );

  // Start periodic reconciliation (every 6 hours while app is running)
  reconciliation.startPeriodic(interval: const Duration(hours: 6));

  ref.onDispose(() {
    reconciliation.dispose();
    manager.dispose();
  });

  return manager;
});

/// Provider for cache usage statistics.
/// Refreshes when quota settings change or on demand.
final cacheUsageStatsProvider = FutureProvider<CacheUsageStats>((ref) async {
  final manager = await ref.watch(intelligentCacheManagerProvider.future);
  return manager.getUsageStats();
});

/// Provider for the progress DAO (reading position, last played).
final progressDaoProvider = FutureProvider<ProgressDao>((ref) async {
  final db = await AppDatabase.instance;
  return ProgressDao(db);
});

/// Provider for the chapter position DAO (per-chapter resume).
/// Tracks listening positions within each chapter for snap-back functionality.
final chapterPositionDaoProvider = FutureProvider<ChapterPositionDao>((ref) async {
  final db = await AppDatabase.instance;
  return ChapterPositionDao(db);
});

/// Provider for last played timestamp of a book.
/// Returns DateTime or null if never played.
/// Parameter: bookId
final lastPlayedAtProvider = FutureProvider.family<DateTime?, String>((ref, bookId) async {
  final dao = await ref.watch(progressDaoProvider.future);
  final timestamp = await dao.getLastPlayedAt(bookId);
  if (timestamp == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(timestamp);
});

/// Provider for the segment progress DAO (Phase 5.5: Per-segment tracking).
/// Tracks which segments have been listened to for chapter progress.
final segmentProgressDaoProvider = FutureProvider<SegmentProgressDao>((ref) async {
  final db = await AppDatabase.instance;
  return SegmentProgressDao(db);
});

// ===========================================================================
// Chapter Position Providers (Last Listened Location Feature)
// ===========================================================================

// ===========================================================================
// Browsing Mode Notifier (Last Listened Location Feature)
// ===========================================================================

/// Tracks whether the user is browsing chapters (viewing text) while audio plays.
///
/// This is a simple boolean state - no timers needed.
/// The user explicitly commits to a new position by tapping a segment.
class BrowsingModeNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => {};

  /// Check if browsing mode is active for a book.
  bool isBrowsing(String bookId) => state[bookId] ?? false;

  /// Enter browsing mode for a book.
  void enterBrowsingMode(String bookId) {
    state = {...state, bookId: true};
  }

  /// Exit browsing mode for a book.
  void exitBrowsingMode(String bookId) {
    state = {...state, bookId: false};
  }
}

/// Provider for browsing mode state.
/// Use `ref.watch(browsingModeNotifierProvider.notifier).isBrowsing(bookId)` to check.
final browsingModeNotifierProvider =
    NotifierProvider<BrowsingModeNotifier, Map<String, bool>>(
  BrowsingModeNotifier.new,
);

/// Convenience provider to check if a specific book is in browsing mode.
/// Parameter: bookId
/// Returns: true if browsing mode is active for this book
final isBrowsingProvider = Provider.family<bool, String>((ref, bookId) {
  final browsingState = ref.watch(browsingModeNotifierProvider);
  return browsingState[bookId] ?? false;
});

/// Primary listening position for a book (snap-back target).
/// 
/// The primary position is where the user was actively listening before
/// they started browsing other chapters. This is the target for the
/// "Back to Chapter X" snap-back feature.
/// 
/// Returns null if:
/// - No position has been saved yet
/// - User hasn't started any chapter navigation
/// 
/// Parameter: bookId
final primaryPositionProvider = FutureProvider.family<ChapterPosition?, String>(
  (ref, bookId) async {
    final dao = await ref.watch(chapterPositionDaoProvider.future);
    return dao.getPrimaryPosition(bookId);
  },
);

/// All chapter positions for a book, keyed by chapter index.
/// 
/// Each position represents where the user last stopped in that chapter.
/// Used for:
/// - Resuming from the correct position when returning to a chapter
/// - Showing position indicators in the chapter list
/// 
/// Parameter: bookId
final chapterPositionsProvider = FutureProvider.family<Map<int, ChapterPosition>, String>(
  (ref, bookId) async {
    final dao = await ref.watch(chapterPositionDaoProvider.future);
    return dao.getAllPositions(bookId);
  },
);

/// Provider for chapter progress for all chapters in a book.
/// 
/// Returns a map of chapterIndex -> ChapterProgress.
/// Parameter: bookId
final bookChapterProgressProvider = FutureProvider.family<Map<int, ChapterProgress>, String>((ref, bookId) async {
  final dao = await ref.watch(segmentProgressDaoProvider.future);
  return dao.getBookProgress(bookId);
});

/// Provider for a single chapter's progress.
/// 
/// Parameter: "$bookId:$chapterIndex"
final chapterProgressProvider = FutureProvider.family<ChapterProgress?, String>((ref, key) async {
  final parts = key.split(':');
  if (parts.length != 2) return null;
  final bookId = parts[0];
  final chapterIndex = int.tryParse(parts[1]);
  if (chapterIndex == null) return null;
  
  final dao = await ref.watch(segmentProgressDaoProvider.future);
  return dao.getChapterProgress(bookId, chapterIndex);
});

/// Provider for total book progress summary.
/// 
/// Parameter: bookId
final bookProgressSummaryProvider = FutureProvider.family<BookProgressSummary, String>((ref, bookId) async {
  final dao = await ref.watch(segmentProgressDaoProvider.future);
  return dao.getBookProgressSummary(bookId);
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

/// Provider for the synthesis strategy manager.
///
/// Bridges the app's RuntimePlaybackConfig to the playback package's
/// SynthesisStrategyManager. Initializes strategy from persisted state
/// and type from PrefetchMode (which maps to strategy types).
final synthesisStrategyManagerProvider = Provider<SynthesisStrategyManager>((ref) {
  final runtimeConfig = ref.watch(runtimePlaybackConfigProvider).value;
  
  // Create strategy from persisted state or default based on prefetch mode
  SynthesisStrategy strategy;
  
  if (runtimeConfig?.synthesisStrategyState != null) {
    // Restore from persisted state (includes learned RTF values)
    strategy = SynthesisStrategy.fromJson(runtimeConfig!.synthesisStrategyState!);
  } else {
    // Create new strategy based on prefetch mode
    strategy = _createStrategyFromPrefetchMode(
      runtimeConfig?.prefetchMode ?? app_config.PrefetchMode.adaptive,
    );
  }
  
  return SynthesisStrategyManager(strategy: strategy);
});

/// Create a SynthesisStrategy from the app's PrefetchMode.
///
/// Maps:
/// - adaptive -> AdaptiveSynthesisStrategy
/// - aggressive -> AggressiveSynthesisStrategy  
/// - conservative -> ConservativeSynthesisStrategy
/// - off -> ConservativeSynthesisStrategy (minimal prefetch)
SynthesisStrategy _createStrategyFromPrefetchMode(app_config.PrefetchMode mode) {
  return switch (mode) {
    app_config.PrefetchMode.adaptive => AdaptiveSynthesisStrategy(),
    app_config.PrefetchMode.aggressive => AggressiveSynthesisStrategy(),
    app_config.PrefetchMode.conservative => ConservativeSynthesisStrategy(),
    app_config.PrefetchMode.off => ConservativeSynthesisStrategy(),
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
  
  /// Current selected voice, updated by listener when user changes voice.
  /// Used by the voiceIdResolver callback to avoid calling ref.read() which
  /// can cause CircularDependencyError.
  String _currentVoice = VoiceIds.none;

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

      // Get IntelligentCacheManager for compression callback
      PlaybackLogger.info('[PlaybackProvider] Loading intelligent cache manager...');
      final intelligentCache = await ref.read(intelligentCacheManagerProvider.future);
      PlaybackLogger.info('[PlaybackProvider] Intelligent cache manager loaded successfully');

      // Resource monitor for battery-aware synthesis
      PlaybackLogger.info('[PlaybackProvider] Loading resource monitor...');
      final resourceMonitor = ref.read(resourceMonitorProvider);
      PlaybackLogger.info('[PlaybackProvider] Resource monitor loaded (mode: ${resourceMonitor.currentMode})');

      // Load segment progress DAO for tracking listened segments
      PlaybackLogger.info('[PlaybackProvider] Loading segment progress DAO...');
      final segmentProgressDao = await ref.read(segmentProgressDaoProvider.future);
      PlaybackLogger.info('[PlaybackProvider] Segment progress DAO loaded');

      // Create audio output externally so we can access its player
      // for audio service integration (system media controls)
      PlaybackLogger.info('[PlaybackProvider] Creating audio output...');
      _audioOutput = JustAudioOutput();

      // Initialize current voice from settings (will be kept in sync by listener below)
      _currentVoice = ref.read(settingsProvider).selectedVoice;

      PlaybackLogger.info('[PlaybackProvider] Creating AudiobookPlaybackController...');
      _controller = AudiobookPlaybackController(
        engine: engine,
        cache: cache,
        audioOutput: _audioOutput,
        // Voice selection - return the current voice stored in _currentVoice.
        // This avoids calling ref.read() in the callback which can cause
        // CircularDependencyError. The _currentVoice is kept in sync by the
        // listener below when user changes voice.
        voiceIdResolver: (_) => _currentVoice,
        resourceMonitor: resourceMonitor,
        onStateChange: (newState) {
          // Update Riverpod state when controller state changes
          state = AsyncData(newState);
        },
        // Wire up segment readiness callbacks for UI feedback
        onSegmentSynthesisStarted: (bookId, chapterIndex, segmentIndex) {
          final key = '$bookId:$chapterIndex';
          SegmentReadinessTracker.instance.onSynthesisStarted(key, segmentIndex);
          // Force provider refresh to pick up the new state
          ref.invalidate(segmentReadinessStreamProvider(key));
        },
        onSegmentSynthesisComplete: (bookId, chapterIndex, segmentIndex) {
          final key = '$bookId:$chapterIndex';
          SegmentReadinessTracker.instance.onSynthesisComplete(key, segmentIndex);
          // Force provider refresh to pick up the new state
          ref.invalidate(segmentReadinessStreamProvider(key));
        },
        // Track segment progress when audio finishes playing
        onSegmentAudioComplete: (bookId, chapterIndex, segmentIndex) {
          // Mark segment as listened (fire and forget - don't block playback)
          segmentProgressDao.markListened(bookId, chapterIndex, segmentIndex).then((_) {
            PlaybackLogger.debug('[PlaybackProvider] Marked segment $segmentIndex as listened');
            // Invalidate progress providers so time remaining updates in UI
            ref.invalidate(bookProgressSummaryProvider(bookId));
            ref.invalidate(chapterProgressProvider('$bookId:$chapterIndex'));
          }).catchError((e) {
            PlaybackLogger.error('[PlaybackProvider] Failed to mark segment listened: $e');
          });
        },
        // Prevent play button flicker during segment transitions
        onPlayIntentOverride: (override) {
          _audioServiceHandler?.setPlayIntentOverride(override);
        },
        // Trigger compression after cache entry is registered
        // This is the key callback that ensures entries exist in metadata
        // before compression is attempted (fixes timing issue)
        // Only compress if the setting is enabled
        onEntryRegistered: (filename) async {
          final shouldCompress = ref.read(settingsProvider).compressOnSynthesize;
          if (!shouldCompress) {
            PlaybackLogger.debug('[PlaybackProvider] Entry registered (compression disabled): $filename');
            return;
          }
          PlaybackLogger.debug('[PlaybackProvider] Entry registered, triggering compression: $filename');
          await intelligentCache.compressEntryByFilenameInBackground(filename);
        },
      );
      PlaybackLogger.info('[PlaybackProvider] Controller created successfully');

      // Listen to state changes
      _stateSub = _controller!.stateStream.listen((newState) {
        state = AsyncData(newState);
      });
      
      // Listen for voice changes to notify controller (clears synthesis queue)
      // Also update _currentVoice so the voiceIdResolver always has the latest value
      // Use fireImmediately to sync _currentVoice in case settings already loaded
      // from SQLite before this listener was set up (race condition fix)
      ref.listen(
        settingsProvider.select((s) => s.selectedVoice),
        (prev, next) {
          final previousVoice = _currentVoice;
          _currentVoice = next;  // Keep _currentVoice in sync
          
          // Only notify controller if voice actually changed AND controller exists
          // Check against previousVoice (not prev) because prev might be the initial
          // callback value which doesn't reflect what we actually had stored
          if (previousVoice != VoiceIds.none && previousVoice != next && _controller != null) {
            PlaybackLogger.info('[PlaybackProvider] Voice changed: $previousVoice -> $next');
            _controller!.notifyVoiceChanged();
          } else if (previousVoice == VoiceIds.none && next != VoiceIds.none) {
            // Voice was loaded from settings (initial sync) - just log, no need to notify
            PlaybackLogger.info('[PlaybackProvider] Voice synced from settings: $next');
          }
        },
        fireImmediately: true,  // Sync voice immediately in case settings already loaded
      );
      
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
    PlaybackLogger.info('[PlaybackProvider] Chapter: "${chapter.title}"');

    // Load pre-segmented content from SQLite (no runtime segmentation)
    final segmentStart = DateTime.now();
    final libraryController = ref.read(libraryProvider.notifier);
    final segments = await libraryController.getSegmentsForChapter(
      book.id, 
      chapterIndex,
    );
    final segmentDuration = DateTime.now().difference(segmentStart);
    PlaybackLogger.info('[PlaybackProvider] Loaded ${segments.length} segments from SQLite in ${segmentDuration.inMilliseconds}ms');

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
      
      // Pre-synthesize first segment of next chapter (fire-and-forget)
      // This eliminates cold-start delay at chapter boundaries
      _preSynthNextChapterFirstSegment(book: book, currentChapterIndex: chapterIndex);
    } catch (e, st) {
      PlaybackLogger.error('[PlaybackProvider] ERROR loading chapter: $e');
      PlaybackLogger.error('[PlaybackProvider] Stack trace: $st');
      rethrow;
    }
  }
  
  /// Pre-synthesize the first segment of the next chapter in the background.
  /// This runs fire-and-forget to eliminate cold-start delays at chapter boundaries.
  /// 
  /// Uses the SynthesisCoordinator with background priority so that current
  /// chapter playback is always prioritized over pre-synthesis.
  void _preSynthNextChapterFirstSegment({
    required Book book,
    required int currentChapterIndex,
  }) {
    // Check if there's a next chapter
    final nextChapterIndex = currentChapterIndex + 1;
    if (nextChapterIndex >= book.chapters.length) {
      PlaybackLogger.debug('[NextChapterPresynth] No next chapter to pre-synthesize');
      return;
    }
    
    // Run in background (fire-and-forget)
    Future(() async {
      try {
        PlaybackLogger.info('[NextChapterPresynth] Pre-synthesizing first segment of chapter $nextChapterIndex');

        // Load pre-segmented content from SQLite (no runtime segmentation)
        final libraryController = ref.read(libraryProvider.notifier);
        final segments = await libraryController.getSegmentsForChapter(
          book.id, 
          nextChapterIndex,
        );
        if (segments.isEmpty) {
          PlaybackLogger.debug('[NextChapterPresynth] Next chapter has no segments');
          return;
        }

        final nextChapter = book.chapters[nextChapterIndex];
        
        // Get current voice and engine
        final settings = ref.read(settingsProvider);
        final voiceId = settings.selectedVoice;
        
        // Use default playback rate (1.0) for pre-synthesis
        // Rate-independent synthesis ensures cache hits regardless of user speed
        const synthRate = 1.0;
        
        // Generate cache key for first segment
        final firstSegmentText = segments.first.text;
        final cacheKey = CacheKeyGenerator.generate(
          voiceId: voiceId,
          text: firstSegmentText,
          playbackRate: CacheKeyGenerator.getSynthesisRate(synthRate),
        );
        
        // Check if already cached
        final cache = await ref.read(audioCacheProvider.future);
        if (await cache.isReady(cacheKey)) {
          PlaybackLogger.debug('[NextChapterPresynth] First segment already cached');
          return;
        }
        
        // Use the SynthesisCoordinator with background priority
        // This ensures current chapter playback is always prioritized
        final controller = _controller;
        if (controller == null) {
          PlaybackLogger.debug('[NextChapterPresynth] Controller not ready, skipping');
          return;
        }
        
        // Create an AudioTrack for the presynth segment
        final track = AudioTrack(
          id: '${book.id}_ch${nextChapterIndex}_seg0_presynth',
          text: firstSegmentText,
          chapterIndex: nextChapterIndex,
          segmentIndex: 0,
          bookId: book.id,
          title: nextChapter.title,
        );
        
        // Queue through the coordinator with background priority
        // This yields to immediate/prefetch requests for current chapter
        await controller.synthesisCoordinator.queueRange(
          tracks: [track],
          voiceId: voiceId,
          startIndex: 0,
          endIndex: 1,
          playbackRate: synthRate,
          bookId: book.id,
          chapterIndex: nextChapterIndex,
          priority: SynthesisPriority.background,
        );
        
        PlaybackLogger.info('[NextChapterPresynth] ✓ Queued first segment of chapter $nextChapterIndex (background priority)');
      } catch (e) {
        // Don't fail silently but don't crash either - this is best-effort
        PlaybackLogger.error('[NextChapterPresynth] Failed to pre-synth next chapter: $e');
      }
    });
  }
  
  /// Update audio service with current book/chapter metadata.
  /// This makes the notification/lock screen show the correct info.
  Future<void> _updateAudioServiceMetadata({
    required Book book,
    required int chapterIndex,
  }) async {
    PlaybackLogger.debug('_updateAudioServiceMetadata called: ${book.title}, chapter $chapterIndex');
    
    try {
      final handler = await ref.read(audioServiceHandlerProvider.future);
      final chapter = book.chapters[chapterIndex];
      PlaybackLogger.debug('Got handler, setting mediaItem...');
      
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
      
      PlaybackLogger.debug('Calling updateNowPlaying: title=${chapter.title}, album=${book.title}');
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
      PlaybackLogger.debug('updateNowPlaying called successfully');
    } catch (e, st) {
      PlaybackLogger.error('ERROR updating audio service metadata: $e');
      PlaybackLogger.debug('Stack: $st');
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
