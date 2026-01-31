import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:downloads/downloads.dart';
import 'package:core_domain/core_domain.dart';

import 'app_paths.dart';
import 'playback_providers.dart';
import 'settings_controller.dart';
import 'tts_providers.dart';

/// Provider for the granular download manager.
final granularDownloadManagerProvider =
    AsyncNotifierProvider<GranularDownloadManager, GranularDownloadState>(() {
  return GranularDownloadManager();
});

/// Manages granular downloads of cores and voices.
class GranularDownloadManager extends AsyncNotifier<GranularDownloadState> {
  late AtomicAssetManager _assetManager;
  late ManifestService _manifestService;
  late DownloadQueue _queue;
  late Directory _baseDir;
  
  /// Tracks whether a controller refresh is pending (deferred because playback was active).
  bool _pendingControllerRefresh = false;

  @override
  FutureOr<GranularDownloadState> build() async {
    final paths = await ref.read(appPathsProvider.future);
    _baseDir = paths.voiceAssetsDir;
    await _baseDir.create(recursive: true);

    _assetManager = AtomicAssetManager(baseDir: _baseDir);
    _manifestService = await _loadManifest();
    _queue = DownloadQueue(maxConcurrent: 1);
    
    // NOTE: We intentionally do NOT listen to playbackStateProvider here.
    // Doing so creates a circular dependency:
    //   playbackControllerProvider → routingEngine → adapters → granularDownloadManager
    //   → playbackStateProvider → playbackControllerProvider
    //
    // Instead, the deferred controller refresh (when downloads complete during playback)
    // is checked explicitly by the UI when playback stops via checkPendingControllerRefresh().

    ref.onDispose(() {
      _assetManager.dispose();
      _queue.dispose();
    });

    // Build initial state by scanning installed assets
    return await _buildInitialState();
  }
  
  /// Check if there's a pending controller refresh and perform it if playback has stopped.
  /// Call this from the UI when the user stops playback manually.
  void checkPendingControllerRefresh() {
    if (_pendingControllerRefresh) {
      final playbackAsync = ref.read(playbackControllerProvider);
      final isPlaying = playbackAsync.value?.isPlaying ?? false;
      if (!isPlaying) {
        debugPrint('[GranularDownloadManager] Performing deferred controller refresh');
        _pendingControllerRefresh = false;
        ref.invalidate(playbackControllerProvider);
      }
    }
  }

  /// Load manifest from bundled asset.
  Future<ManifestService> _loadManifest() async {
    try {
      final jsonString = await rootBundle.loadString(
        'packages/downloads/lib/manifests/voices_manifest.json',
      );
      return ManifestService.loadFromString(jsonString);
    } catch (e) {
      debugPrint('[GranularDownloadManager] Failed to load manifest: $e');
      rethrow;
    }
  }

  /// Build initial state by scanning what's installed.
  Future<GranularDownloadState> _buildInitialState() async {
    final cores = <String, CoreDownloadState>{};
    final voices = <String, VoiceDownloadState>{};

    debugPrint('[GranularDownloadManager] Building initial state...');
    
    // Build core states from manifest
    for (final core in _manifestService.allCores) {
      final isInstalled = await _isCoreInstalled(core.id);
      debugPrint('[GranularDownloadManager] Core ${core.id} (${core.engineType}): installed=$isInstalled');
      cores[core.id] = CoreDownloadState(
        coreId: core.id,
        displayName: core.displayName,
        engineType: core.engineType,
        status: isInstalled ? DownloadStatus.ready : DownloadStatus.notDownloaded,
        progress: isInstalled ? 1.0 : 0.0,
        sizeBytes: core.totalSize,
      );
    }

    // Build voice states from manifest
    for (final voice in _manifestService.allVoices) {
      // Resolve coreRequirements to platform-specific core IDs
      final resolvedCoreIds = _manifestService.getRequiredCores(voice.id)
          .map((c) => c.id)
          .toList();
      
      voices[voice.id] = VoiceDownloadState(
        voiceId: voice.id,
        displayName: voice.displayName,
        engineId: voice.engineId,
        language: voice.language,
        requiredCoreIds: resolvedCoreIds,
        speakerId: voice.speakerId,
        modelKey: voice.modelKey,
      );
    }

    final initialState = GranularDownloadState(cores: cores, voices: voices);
    
    // Validate selected voice on startup
    _validateSelectedVoiceOnStartup(initialState);
    
    return initialState;
  }
  
  /// Validates that the selected voice is still available after startup.
  /// If not, resets the selection to none.
  Future<void> _validateSelectedVoiceOnStartup(GranularDownloadState downloadState) async {
    try {
      final availableVoiceIds = downloadState.readyVoices
          .map((v) => v.voiceId)
          .toSet();
      
      final wasValid = await ref.read(settingsProvider.notifier)
          .validateSelectedVoice(availableVoiceIds);
      
      if (!wasValid) {
        debugPrint('[GranularDownloadManager] Selected voice was invalid and has been reset');
      }
    } catch (e) {
      debugPrint('[GranularDownloadManager] Failed to validate selected voice: $e');
      // Non-fatal - voice resolver will handle unavailable voice gracefully
    }
  }

  /// Check if a core is installed.
  Future<bool> _isCoreInstalled(String coreId) async {
    final key = _getCoreKey(coreId);
    final installDir = Directory('${_baseDir.path}/$key');
    if (!await installDir.exists()) return false;

    // Check for manifest file
    final manifestFile = File('${installDir.path}/.manifest');
    return manifestFile.exists();
  }

  /// Get storage key for a core.
  String _getCoreKey(String coreId) {
    final core = _manifestService.getCore(coreId);
    if (core == null) return coreId;
    return '${core.engineType}/$coreId';
  }

  /// Download a voice (auto-downloads required cores first).
  Future<void> downloadVoice(String voiceId) async {
    final voice = _manifestService.getVoice(voiceId);
    if (voice == null) {
      throw DownloadException(
        DownloadErrorType.manifestError,
        'Unknown voice: $voiceId',
      );
    }

    // Get required cores
    final requiredCores = _manifestService.getRequiredCores(voiceId);
    final currentState = state.value!;

    // Download missing cores first
    for (final core in requiredCores) {
      if (!currentState.isCoreReady(core.id)) {
        await downloadCore(core.id);
      }
    }

    // For most voices, downloading cores is sufficient
    // (Kokoro uses speakerId, Piper core IS the voice model)
    debugPrint('[GranularDownloadManager] Voice $voiceId is now ready');
    
    // Auto-select this voice if no voice is currently selected
    final settings = ref.read(settingsProvider);
    if (settings.selectedVoice == VoiceIds.none) {
      await ref.read(settingsProvider.notifier).setSelectedVoice(voiceId);
      debugPrint('[GranularDownloadManager] Auto-selected voice: $voiceId');
    }
  }

  /// Download a specific core.
  Future<void> downloadCore(String coreId) async {
    final core = _manifestService.getCore(coreId);
    if (core == null) {
      throw DownloadException(
        DownloadErrorType.manifestError,
        'Unknown core: $coreId',
      );
    }

    // Check if already downloading
    if (_queue.currentState.contains(coreId)) {
      debugPrint('[GranularDownloadManager] Core $coreId already in queue');
      return;
    }

    // Check if already downloaded
    if (state.value?.isCoreReady(coreId) ?? false) {
      debugPrint('[GranularDownloadManager] Core $coreId already downloaded');
      return;
    }

    // Set queued status BEFORE adding to queue (so UI shows immediately)
    _updateCoreState(coreId, DownloadStatus.queued, 0.0);

    await _queue.enqueue(coreId, () => _downloadCoreImpl(core));
  }

  /// Internal implementation of core download.
  Future<void> _downloadCoreImpl(CoreRequirement core) async {
    final key = _getCoreKey(core.id);
    StreamSubscription<DownloadState>? subscription;
    int lastLoggedPercent = -10; // Track last logged % to throttle output
    final downloadStartTime = DateTime.now();

    try {
      // Set downloading status when we actually start (moved from queued)
      _updateCoreState(core.id, DownloadStatus.downloading, 0.0, startTime: downloadStartTime);

      if (core.isMultiFile) {
        // Multi-file download (e.g., Piper ONNX + JSON)
        final files = core.files
            .map((f) => MultiFileSpec(
                  filename: f.filename,
                  url: f.url,
                  sizeBytes: f.sizeBytes,
                  sha256: f.sha256,
                ))
            .toList();

        await _assetManager.downloadMultiFile(
          key: key,
          files: files,
          onProgress: (p) => _updateCoreState(core.id, DownloadStatus.downloading, p),
        );
      } else if (core.url != null) {
        // Single file download - subscribe to state updates for progress
        subscription = _assetManager.watchState(key).listen((downloadState) {
          if (downloadState.status == DownloadStatus.downloading) {
            _updateCoreState(
              core.id, 
              DownloadStatus.downloading, 
              downloadState.progress,
              downloadedBytes: downloadState.downloadedBytes,
            );
            
            // Log every 10% progress
            final currentPercent = (downloadState.progress * 100).toInt();
            if (currentPercent >= lastLoggedPercent + 10) {
              lastLoggedPercent = (currentPercent ~/ 10) * 10;
              debugPrint('[Download] ${core.id}: $currentPercent%');
            }
          } else if (downloadState.status == DownloadStatus.extracting) {
            _updateCoreState(core.id, DownloadStatus.extracting, downloadState.progress);
            debugPrint('[Download] ${core.id}: Extracting...');
          }
        });

        await _assetManager.download(AssetSpec(
          key: key,
          displayName: core.displayName,
          downloadUrl: core.url!,
          installPath: key,
          sizeBytes: core.sizeBytes,
          checksum: core.sha256,
        ));
      } else {
        throw DownloadException(
          DownloadErrorType.manifestError,
          'Core ${core.id} has no download URL or files',
        );
      }

      _updateCoreState(core.id, DownloadStatus.ready, 1.0);
      debugPrint('[Download] ${core.id}: Complete!');
      
      // Invalidate TTS adapter providers so they pick up the newly downloaded core.
      // This is needed because adapters use ref.read() (not watch) to avoid cascading
      // rebuilds during initialization, so they won't auto-update when state changes.
      _invalidateAdapterForCore(core.id);
    } catch (e) {
      debugPrint('[Download] ${core.id} failed: $e');
      _updateCoreState(core.id, DownloadStatus.failed, 0.0, error: e.toString());
      rethrow;
    } finally {
      await subscription?.cancel();
    }
  }
  
  /// Invalidate the appropriate TTS adapter provider for a downloaded core.
  /// Uses scheduleMicrotask to defer invalidation and avoid circular dependency
  /// when called from within the download callback chain.
  /// 
  /// Also invalidates the playback controller so it picks up the new engine
  /// with the newly available voice adapter (only if not actively playing).
  /// If playback is active, sets a flag to refresh when playback stops.
  void _invalidateAdapterForCore(String coreId) {
    // Defer invalidation to break the synchronous call chain and avoid
    // CircularDependencyError. The adapter providers watch our state,
    // so invalidating them synchronously during state update causes issues.
    scheduleMicrotask(() {
      // Check if playback is active - don't interrupt ongoing playback
      final playbackAsync = ref.read(playbackControllerProvider);
      final isPlaying = playbackAsync.value?.isPlaying ?? false;
      
      if (coreId.contains('supertonic')) {
        ref.invalidate(supertonicAdapterProvider);
        ref.invalidate(ttsRoutingEngineProvider);
        ref.invalidate(routingEngineProvider);
        // Only invalidate playback controller if not currently playing
        if (!isPlaying) {
          ref.invalidate(playbackControllerProvider);
          debugPrint('[GranularDownloadManager] Invalidated Supertonic adapter, routing, and playback');
        } else {
          _pendingControllerRefresh = true;
          debugPrint('[GranularDownloadManager] Invalidated Supertonic adapter and routing (playback active, refresh deferred)');
        }
      } else if (coreId.contains('piper')) {
        ref.invalidate(piperAdapterProvider);
        ref.invalidate(ttsRoutingEngineProvider);
        ref.invalidate(routingEngineProvider);
        // Only invalidate playback controller if not currently playing
        if (!isPlaying) {
          ref.invalidate(playbackControllerProvider);
          debugPrint('[GranularDownloadManager] Invalidated Piper adapter, routing, and playback');
        } else {
          _pendingControllerRefresh = true;
          debugPrint('[GranularDownloadManager] Invalidated Piper adapter and routing (playback active, refresh deferred)');
        }
      } else if (coreId.contains('kokoro')) {
        ref.invalidate(kokoroAdapterProvider);
        ref.invalidate(ttsRoutingEngineProvider);
        ref.invalidate(routingEngineProvider);
        // Only invalidate playback controller if not currently playing
        if (!isPlaying) {
          ref.invalidate(playbackControllerProvider);
          debugPrint('[GranularDownloadManager] Invalidated Kokoro adapter, routing, and playback');
        } else {
          _pendingControllerRefresh = true;
          debugPrint('[GranularDownloadManager] Invalidated Kokoro adapter and routing (playback active, refresh deferred)');
        }
      }
    });
  }

  /// Delete a core (marks dependent voices as unavailable).
  Future<void> deleteCore(String coreId) async {
    final key = _getCoreKey(coreId);
    await _assetManager.delete(key);
    _updateCoreState(coreId, DownloadStatus.notDownloaded, 0.0);
    debugPrint('[GranularDownloadManager] Core $coreId deleted');
  }

  /// Delete all downloaded cores.
  Future<void> deleteAll() async {
    final current = state.value;
    if (current == null) return;

    final readyCores = current.cores.values.where((c) => c.isReady).toList();
    for (final core in readyCores) {
      await deleteCore(core.coreId);
    }
    debugPrint('[GranularDownloadManager] All ${readyCores.length} cores deleted');
  }

  /// Get file path for a core (for TTS engines to use).
  String? getCoreDirectory(String coreId) {
    if (!(state.value?.isCoreReady(coreId) ?? false)) return null;
    final key = _getCoreKey(coreId);
    return '${_baseDir.path}/$key';
  }

  /// Cancel a download in progress.
  void cancelDownload(String coreId) {
    _queue.cancel(coreId);
    _assetManager.cancelDownload(_getCoreKey(coreId));
    _updateCoreState(coreId, DownloadStatus.notDownloaded, 0.0);
  }

  /// Clear error state.
  void clearError() {
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(error: null));
    }
  }

  /// Retry all failed downloads.
  Future<void> retryFailed() async {
    final current = state.value;
    if (current == null) return;

    for (final core in current.cores.values) {
      if (core.isFailed) {
        await downloadCore(core.coreId);
      }
    }
  }

  /// Download all cores for a voice in batch.
  Future<void> downloadAllCoresForVoice(String voiceId) async {
    await downloadVoice(voiceId);
  }

  /// Download all voices for an engine.
  Future<void> downloadAllForEngine(String engineId) async {
    final voices = _manifestService.getVoicesForEngine(engineId);
    final uniqueCoreIds = _manifestService.getUniqueCoreIds(
      voices.map((v) => v.id).toList(),
    );

    for (final coreId in uniqueCoreIds) {
      await downloadCore(coreId);
    }
  }

  /// Get estimated download size for a voice.
  int getEstimatedSize(String voiceId) {
    final current = state.value;
    if (current == null) return 0;

    final downloadedCoreIds = current.cores.entries
        .where((e) => e.value.isReady)
        .map((e) => e.key)
        .toSet();

    return _manifestService.estimateVoiceDownloadSize(voiceId, downloadedCoreIds);
  }

  /// Check if all required cores for an engine are ready.
  bool isEngineReady(String engineId) {
    final current = state.value;
    if (current == null) return false;
    
    final engineCores = current.cores.values.where((c) => c.engineType == engineId);
    if (engineCores.isEmpty) return false;
    
    // For engines with required cores, check if all required cores are ready
    return engineCores.every((c) => c.isReady);
  }

  /// Check if a specific voice is ready (all its required cores are downloaded).
  bool isVoiceReady(String voiceId) {
    return state.value?.isVoiceReady(voiceId) ?? false;
  }

  // State update helpers
  void _updateCoreState(
    String coreId,
    DownloadStatus status,
    double progress, {
    String? error,
    int? downloadedBytes,
    DateTime? startTime,
  }) {
    final current = state.value;
    if (current == null) return;

    final core = _manifestService.getCore(coreId);
    if (core == null) return;

    // Preserve existing startTime if not provided
    final existingStartTime = current.cores[coreId]?.startTime;
    
    final newCores = Map<String, CoreDownloadState>.from(current.cores);
    newCores[coreId] = CoreDownloadState(
      coreId: coreId,
      displayName: core.displayName,
      engineType: core.engineType,
      status: status,
      progress: progress,
      sizeBytes: core.totalSize,
      downloadedBytes: downloadedBytes ?? (progress * core.totalSize).toInt(),
      startTime: startTime ?? existingStartTime,
      error: error,
    );

    // Determine currentDownload:
    // - If this item is downloading or extracting, it becomes current
    // - If this item was current but is now done (ready/failed/notDownloaded), clear it
    // - Otherwise keep existing currentDownload
    String? newCurrentDownload;
    if (status == DownloadStatus.downloading || status == DownloadStatus.extracting) {
      newCurrentDownload = coreId;
    } else if (current.currentDownload == coreId &&
        (status == DownloadStatus.ready ||
         status == DownloadStatus.failed ||
         status == DownloadStatus.notDownloaded)) {
      newCurrentDownload = null;
    } else {
      newCurrentDownload = current.currentDownload;
    }

    state = AsyncData(current.copyWith(
      cores: newCores,
      currentDownload: newCurrentDownload,
      error: error,
    ));
  }
}
