import 'package:core_domain/core_domain.dart';

import 'asset_spec.dart';

/// Voice manifest containing all available voices and cores.
class VoiceManifest {
  VoiceManifest._();

  /// Base URL for voice downloads.
  static const _baseUrl = 'https://huggingface.co/rhasspy/piper-voices/resolve/main';

  /// Kokoro core variants.
  static final kokoroInt8Core = AssetSpec(
    key: 'kokoro_int8_core',
    displayName: 'Kokoro INT8 Core',
    downloadUrl: '', // Placeholder - actual URL needed
    installPath: 'kokoro/int8',
    sizeBytes: 350 * 1024 * 1024, // ~350MB
    isCore: true,
    engineType: EngineType.kokoro,
  );

  static final kokoroFp32Core = AssetSpec(
    key: 'kokoro_fp32_core',
    displayName: 'Kokoro FP32 Core',
    downloadUrl: '', // Placeholder
    installPath: 'kokoro/fp32',
    sizeBytes: 700 * 1024 * 1024, // ~700MB
    isCore: true,
    engineType: EngineType.kokoro,
  );

  /// Supertonic core.
  static final supertonicCore = AssetSpec(
    key: 'supertonic_core',
    displayName: 'Supertonic Core',
    downloadUrl: '', // Placeholder
    installPath: 'supertonic',
    sizeBytes: 200 * 1024 * 1024,
    isCore: true,
    engineType: EngineType.supertonic,
  );

  /// Piper voice specs (dynamically generated).
  static AssetSpec piperVoice(String modelKey) {
    final parts = modelKey.split('-');
    final lang = parts.isNotEmpty ? parts[0] : 'en_US';
    final name = parts.length > 1 ? parts[1] : modelKey;
    final quality = parts.length > 2 ? parts[2] : 'medium';

    return AssetSpec(
      key: 'piper_$modelKey',
      displayName: _formatPiperName(name, quality),
      downloadUrl: '$_baseUrl/$lang/$name/$quality/$lang-$name-$quality.onnx.json',
      installPath: 'piper/$modelKey',
      engineType: EngineType.piper,
    );
  }

  static String _formatPiperName(String name, String quality) {
    final formatted = name
        .split('_')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w)
        .join(' ');
    return '$formatted ($quality)';
  }

  /// All Kokoro voices (no per-voice assets, just display info).
  static final kokoroVoices = VoiceIds.kokoroVoices.map((id) => Voice(
        id: id,
        displayName: _kokoroDisplayName(id),
        engine: EngineType.kokoro,
        speakerId: VoiceIds.kokoroSpeakerId(id),
      )).toList();

  static String _kokoroDisplayName(String id) {
    // kokoro_af_bella -> AF Bella
    final parts = id.replaceFirst('kokoro_', '').split('_');
    if (parts.isEmpty) return id;
    final prefix = parts[0].toUpperCase();
    final name = parts.length > 1
        ? parts.sublist(1).map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w).join(' ')
        : 'Default';
    return '$prefix $name';
  }

  /// All Supertonic voices.
  static final supertonicVoices = VoiceIds.supertonicVoices.map((id) => Voice(
        id: id,
        displayName: _supertonicDisplayName(id),
        engine: EngineType.supertonic,
      )).toList();

  static String _supertonicDisplayName(String id) {
    // supertonic_m1 -> Male 1, supertonic_f1 -> Female 1
    final suffix = id.replaceFirst('supertonic_', '');
    final isMale = suffix.startsWith('m');
    final num = suffix.substring(1);
    return '${isMale ? 'Male' : 'Female'} $num';
  }

  /// All available voices.
  static List<Voice> get allVoices => [
        ...kokoroVoices,
        ...supertonicVoices,
      ];

  /// Get required core for a voice.
  static AssetSpec? coreForVoice(String voiceId, {bool preferInt8 = true}) {
    if (VoiceIds.isKokoro(voiceId)) {
      return preferInt8 ? kokoroInt8Core : kokoroFp32Core;
    }
    if (VoiceIds.isSupertonic(voiceId)) {
      return supertonicCore;
    }
    return null;
  }
}
