import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core_domain/core_domain.dart';
import 'package:downloads/downloads.dart';
import 'package:tts_engines/tts_engines.dart';
import 'package:platform_android_tts/platform_android_tts.dart';

import 'app_paths.dart';

/// TTS download state for UI display.
class TtsDownloadState {
  const TtsDownloadState({
    this.kokoroState = DownloadStatus.notDownloaded,
    this.piperState = DownloadStatus.notDownloaded,
    this.supertonicState = DownloadStatus.notDownloaded,
    this.kokoroProgress = 0.0,
    this.piperProgress = 0.0,
    this.supertonicProgress = 0.0,
    this.currentDownload,
    this.error,
  });

  final DownloadStatus kokoroState;
  final DownloadStatus piperState;
  final DownloadStatus supertonicState;
  final double kokoroProgress;
  final double piperProgress;
  final double supertonicProgress;
  final String? currentDownload;
  final String? error;

  bool get isKokoroReady => kokoroState == DownloadStatus.ready;
  bool get isPiperReady => piperState == DownloadStatus.ready;
  bool get isSupertonicReady => supertonicState == DownloadStatus.ready;

  bool get isDownloading =>
      kokoroState == DownloadStatus.downloading ||
      piperState == DownloadStatus.downloading ||
      supertonicState == DownloadStatus.downloading;

  TtsDownloadState copyWith({
    DownloadStatus? kokoroState,
    DownloadStatus? piperState,
    DownloadStatus? supertonicState,
    double? kokoroProgress,
    double? piperProgress,
    double? supertonicProgress,
    String? currentDownload,
    String? error,
  }) {
    return TtsDownloadState(
      kokoroState: kokoroState ?? this.kokoroState,
      piperState: piperState ?? this.piperState,
      supertonicState: supertonicState ?? this.supertonicState,
      kokoroProgress: kokoroProgress ?? this.kokoroProgress,
      piperProgress: piperProgress ?? this.piperProgress,
      supertonicProgress: supertonicProgress ?? this.supertonicProgress,
      currentDownload: currentDownload,
      error: error,
    );
  }
}

/// TTS Download Manager - handles downloading voice models.
class TtsDownloadManager extends AsyncNotifier<TtsDownloadState> {
  AtomicAssetManager? _assetManager;
  StreamSubscription<DownloadState>? _kokoroSub;
  StreamSubscription<DownloadState>? _piperSub;
  StreamSubscription<DownloadState>? _supertonicSub;

  @override
  FutureOr<TtsDownloadState> build() async {
    final paths = await ref.watch(appPathsProvider.future);
    _assetManager = AtomicAssetManager(baseDir: paths.voiceAssetsDir);

    // Check initial states for each engine
    final kokoroModelState = await _assetManager!.getState('kokoro_int8_v1');
    final piperState = await _assetManager!.getState('piper/en_GB-alan-medium');
    final supertonicState = await _assetManager!.getState('supertonic');

    // Subscribe to state changes
    _kokoroSub = _assetManager!.watchState('kokoro_int8_v1').listen(_onKokoroState);
    _piperSub = _assetManager!.watchState('piper/en_GB-alan-medium').listen(_onPiperState);
    _supertonicSub = _assetManager!.watchState('supertonic').listen(_onSupertonicState);

    ref.onDispose(() {
      _kokoroSub?.cancel();
      _piperSub?.cancel();
      _supertonicSub?.cancel();
      _assetManager?.dispose();
    });

    return TtsDownloadState(
      kokoroState: kokoroModelState.status,
      piperState: piperState.status,
      supertonicState: supertonicState.status,
    );
  }

  void _onKokoroState(DownloadState ds) {
    developer.log('Kokoro state update: status=${ds.status}, progress=${ds.progress}, error=${ds.error}', name: 'TtsDownloadManager');
    state = AsyncData(state.value!.copyWith(
      kokoroState: ds.status,
      kokoroProgress: ds.progress,
      currentDownload: ds.isDownloading ? 'Kokoro' : null,
      error: ds.error,
    ));
  }

  void _onPiperState(DownloadState ds) {
    developer.log('Piper state update: status=${ds.status}, progress=${ds.progress}, error=${ds.error}', name: 'TtsDownloadManager');
    state = AsyncData(state.value!.copyWith(
      piperState: ds.status,
      piperProgress: ds.progress,
      currentDownload: ds.isDownloading ? 'Piper' : null,
      error: ds.error,
    ));
  }

  void _onSupertonicState(DownloadState ds) {
    developer.log('Supertonic state update: status=${ds.status}, progress=${ds.progress}, error=${ds.error}', name: 'TtsDownloadManager');
    state = AsyncData(state.value!.copyWith(
      supertonicState: ds.status,
      supertonicProgress: ds.progress,
      currentDownload: ds.isDownloading ? 'Supertonic' : null,
      error: ds.error,
    ));
  }


  /// Download Kokoro model.
  Future<void> downloadKokoro() async {
    if (_assetManager == null) return;

    try {
      final modelSpec = AssetSpec(
        key: 'kokoro_int8_v1',
        displayName: 'Kokoro TTS Model (INT8)',
        downloadUrl: 'https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0/kokoro-v1.0.onnx',
        installPath: 'kokoro_int8_v1',
        sizeBytes: 94371840,
        isCore: true,
        engineType: EngineType.kokoro,
      );

      developer.log('Starting Kokoro download: ${modelSpec.downloadUrl}', name: 'TtsDownloadManager');
      await _assetManager!.download(modelSpec);
      developer.log('Kokoro download completed', name: 'TtsDownloadManager');

      state = AsyncData(state.value!.copyWith(
        kokoroState: DownloadStatus.ready,
        kokoroProgress: 1.0,
      ));
    } catch (e, s) {
      developer.log('Kokoro download failed', name: 'TtsDownloadManager', error: e, stackTrace: s);
      state = AsyncData(state.value!.copyWith(
        kokoroState: DownloadStatus.failed,
        error: 'Kokoro download failed: $e',
      ));
    }
  }

  /// Download Piper models.
  Future<void> downloadPiper() async {
    if (_assetManager == null) return;

    try {
      // Per-voice directories expected by native service:
      //   <coreDir>/piper/<modelKey>/model.onnx
      final alanModelSpec = AssetSpec(
        key: 'piper/en_GB-alan-medium',
        displayName: 'Piper - Alan (British) Model',
        downloadUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alan/medium/en_GB-alan-medium.onnx',
        installPath: 'piper/en_GB-alan-medium',
        sizeBytes: 31457280,
        isCore: true,
        engineType: EngineType.piper,
      );

      developer.log('Starting Piper download (Alan): ${alanModelSpec.downloadUrl}', name: 'TtsDownloadManager');
      await _assetManager!.download(alanModelSpec);
      developer.log('Piper Alan download completed', name: 'TtsDownloadManager');

      final lessacModelSpec = AssetSpec(
        key: 'piper/en_US-lessac-medium',
        displayName: 'Piper - Lessac (American) Model',
        downloadUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx',
        installPath: 'piper/en_US-lessac-medium',
        sizeBytes: 31457280,
        isCore: true,
        engineType: EngineType.piper,
      );

      developer.log('Starting Piper download (Lessac): ${lessacModelSpec.downloadUrl}', name: 'TtsDownloadManager');
      await _assetManager!.download(lessacModelSpec);
      developer.log('Piper Lessac download completed', name: 'TtsDownloadManager');

      state = AsyncData(state.value!.copyWith(
        piperState: DownloadStatus.ready,
        piperProgress: 1.0,
      ));
    } catch (e, s) {
      developer.log('Piper download failed', name: 'TtsDownloadManager', error: e, stackTrace: s);
      state = AsyncData(state.value!.copyWith(
        piperState: DownloadStatus.failed,
        error: 'Piper download failed: $e',
      ));
    }
  }

  /// Download Supertonic model.
  Future<void> downloadSupertonic() async {
    if (_assetManager == null) return;

    try {
      // Native service currently expects <coreDir>/supertonic/model.onnx.
      final modelSpec = AssetSpec(
        key: 'supertonic',
        displayName: 'Supertonic Model',
        downloadUrl: 'https://huggingface.co/Supertone/supertonic/resolve/main/models/autoencoder.onnx',
        installPath: 'supertonic',
        sizeBytes: 94371840,
        isCore: true,
        engineType: EngineType.supertonic,
      );

      developer.log('Starting Supertonic download: ${modelSpec.downloadUrl}', name: 'TtsDownloadManager');
      await _assetManager!.download(modelSpec);
      developer.log('Supertonic download completed', name: 'TtsDownloadManager');

      state = AsyncData(state.value!.copyWith(
        supertonicState: DownloadStatus.ready,
        supertonicProgress: 1.0,
      ));
    } catch (e, s) {
      developer.log('Supertonic download failed', name: 'TtsDownloadManager', error: e, stackTrace: s);
      state = AsyncData(state.value!.copyWith(
        supertonicState: DownloadStatus.failed,
        error: 'Supertonic download failed: $e',
      ));
    }
  }

  /// Delete a downloaded model.
  Future<void> deleteModel(String engineId) async {
    if (_assetManager == null) return;

    final keys = switch (engineId) {
      'kokoro' => ['kokoro_int8_v1'],
      'piper' => ['piper/en_GB-alan-medium', 'piper/en_US-lessac-medium'],
      'supertonic' => ['supertonic'],
      _ => <String>[],
    };

    for (final key in keys) {
      await _assetManager!.delete(key);
    }
  }

  /// Get the asset directory for an engine.
  Directory? getAssetDir(String engineId) {
    if (_assetManager == null) return null;

    final key = switch (engineId) {
      'kokoro' => 'kokoro_int8_v1',
      'piper' => 'piper/en_GB-alan-medium',
      'supertonic' => 'supertonic',
      _ => null,
    };

    if (key == null) return null;
    return Directory('${_assetManager!.baseDir.path}/$key');
  }
}

/// Provider for TTS download manager.
final ttsDownloadManagerProvider =
    AsyncNotifierProvider<TtsDownloadManager, TtsDownloadState>(
  TtsDownloadManager.new,
);

/// Provider for TTS Native API (Pigeon-generated).
final ttsNativeApiProvider = Provider<TtsNativeApi>((ref) {
  return TtsNativeApi();
});

/// Provider for Kokoro adapter.
final kokoroAdapterProvider = FutureProvider<KokoroAdapter?>((ref) async {
  final paths = await ref.watch(appPathsProvider.future);
  final downloadState = await ref.watch(ttsDownloadManagerProvider.future);

  if (!downloadState.isKokoroReady) return null;

  final nativeApi = ref.watch(ttsNativeApiProvider);
  return KokoroAdapter(
    nativeApi: nativeApi,
    coreDir: paths.voiceAssetsDir,
  );
});

/// Provider for Piper adapter.
final piperAdapterProvider = FutureProvider<PiperAdapter?>((ref) async {
  final paths = await ref.watch(appPathsProvider.future);
  final downloadState = await ref.watch(ttsDownloadManagerProvider.future);

  if (!downloadState.isPiperReady) return null;

  final nativeApi = ref.watch(ttsNativeApiProvider);
  return PiperAdapter(
    nativeApi: nativeApi,
    coreDir: paths.voiceAssetsDir,
  );
});

/// Provider for Supertonic adapter.
final supertonicAdapterProvider = FutureProvider<SupertonicAdapter?>((ref) async {
  final paths = await ref.watch(appPathsProvider.future);
  final downloadState = await ref.watch(ttsDownloadManagerProvider.future);

  if (!downloadState.isSupertonicReady) return null;

  final nativeApi = ref.watch(ttsNativeApiProvider);
  return SupertonicAdapter(
    nativeApi: nativeApi,
    coreDir: paths.voiceAssetsDir,
  );
});

/// Provider for the routing engine with all adapters.
final ttsRoutingEngineProvider = FutureProvider<RoutingEngine>((ref) async {
  final cache = await ref.watch(_ttsAudioCacheProvider.future);
  final kokoro = await ref.watch(kokoroAdapterProvider.future);
  final piper = await ref.watch(piperAdapterProvider.future);
  final supertonic = await ref.watch(supertonicAdapterProvider.future);

  return RoutingEngine(
    cache: cache,
    kokoroEngine: kokoro,
    piperEngine: piper,
    supertonicEngine: supertonic,
  );
});

/// Private provider for the audio cache (used internally by TTS).
final _ttsAudioCacheProvider = FutureProvider<AudioCache>((ref) async {
  final paths = await ref.watch(appPathsProvider.future);
  return FileAudioCache(cacheDir: paths.audioCacheDir);
});

/// Check if a voice ID is available (model downloaded).
bool isVoiceAvailable(String voiceId, TtsDownloadState downloadState) {
  if (voiceId == VoiceIds.device) return true;
  if (VoiceIds.isKokoro(voiceId)) return downloadState.isKokoroReady;
  if (VoiceIds.isPiper(voiceId)) return downloadState.isPiperReady;
  if (VoiceIds.isSupertonic(voiceId)) return downloadState.isSupertonicReady;
  return false;
}

/// Get the engine ID for a voice.
String? engineIdForVoice(String voiceId) {
  if (VoiceIds.isKokoro(voiceId)) return 'kokoro';
  if (VoiceIds.isPiper(voiceId)) return 'piper';
  if (VoiceIds.isSupertonic(voiceId)) return 'supertonic';
  return null;
}
