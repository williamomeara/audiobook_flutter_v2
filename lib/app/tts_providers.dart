import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core_domain/core_domain.dart';
import 'package:tts_engines/tts_engines.dart';
import 'package:platform_android_tts/platform_android_tts.dart';

import 'app_paths.dart';
import 'granular_download_manager.dart';

/// Provider for TTS Native API (Pigeon-generated).
final ttsNativeApiProvider = Provider<TtsNativeApi>((ref) {
  return TtsNativeApi();
});

/// Provider for Kokoro adapter.
/// Checks granular download state to see if required cores are ready.
final kokoroAdapterProvider = FutureProvider<KokoroAdapter?>((ref) async {
  final paths = await ref.read(appPathsProvider.future);
  final granularState = await ref.read(granularDownloadManagerProvider.future);
  
  // Check if Kokoro core is ready via granular system
  final isReady = granularState.cores['kokoro_core_v1']?.isReady ?? false;
  
  if (!isReady) return null;

  final nativeApi = ref.read(ttsNativeApiProvider);
  return KokoroAdapter(
    nativeApi: nativeApi,
    coreDir: paths.voiceAssetsDir,
  );
});

/// Provider for Piper adapter.
/// Piper voices are per-model cores, check if any Piper core is ready.
final piperAdapterProvider = FutureProvider<PiperAdapter?>((ref) async {
  final paths = await ref.read(appPathsProvider.future);
  final granularState = await ref.read(granularDownloadManagerProvider.future);
  
  // Check if any Piper core is ready
  final piperCores = granularState.cores.values.where((c) => c.engineType == 'piper');
  final isReady = piperCores.any((c) => c.isReady);
  
  if (!isReady) return null;

  final nativeApi = ref.read(ttsNativeApiProvider);
  return PiperAdapter(
    nativeApi: nativeApi,
    coreDir: paths.voiceAssetsDir,
  );
});

/// Provider for Supertonic adapter.
/// Checks granular download state to see if required cores are ready.
final supertonicAdapterProvider = FutureProvider<SupertonicAdapter?>((ref) async {
  final paths = await ref.read(appPathsProvider.future);
  final granularState = await ref.read(granularDownloadManagerProvider.future);
  
  // Check if Supertonic core is ready via granular system
  final isReady = granularState.cores['supertonic_core_v1']?.isReady ?? false;
  
  if (!isReady) return null;

  final nativeApi = ref.read(ttsNativeApiProvider);
  return SupertonicAdapter(
    nativeApi: nativeApi,
    coreDir: paths.voiceAssetsDir,
  );
});

/// Provider for the routing engine with all adapters.
final ttsRoutingEngineProvider = FutureProvider<RoutingEngine>((ref) async {
  final cache = await ref.read(_ttsAudioCacheProvider.future);
  final kokoro = await ref.read(kokoroAdapterProvider.future);
  final piper = await ref.read(piperAdapterProvider.future);
  final supertonic = await ref.read(supertonicAdapterProvider.future);

  return RoutingEngine(
    cache: cache,
    kokoroEngine: kokoro,
    piperEngine: piper,
    supertonicEngine: supertonic,
  );
});

/// Private provider for the audio cache (used internally by TTS).
final _ttsAudioCacheProvider = FutureProvider<AudioCache>((ref) async {
  final paths = await ref.read(appPathsProvider.future);
  return FileAudioCache(cacheDir: paths.audioCacheDir);
});

/// Get the engine ID for a voice.
String? engineIdForVoice(String voiceId) {
  if (VoiceIds.isKokoro(voiceId)) return 'kokoro';
  if (VoiceIds.isPiper(voiceId)) return 'piper';
  if (VoiceIds.isSupertonic(voiceId)) return 'supertonic';
  return null;
}
