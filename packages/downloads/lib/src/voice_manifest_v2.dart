import 'dart:convert';

import 'package:core_domain/core_domain.dart';

import 'asset_spec.dart';

/// Core requirement specification from manifest.
class CoreRequirement {
  const CoreRequirement({
    required this.id,
    required this.engineType,
    required this.displayName,
    required this.url,
    required this.sizeBytes,
    this.sha256,
    this.quality,
    this.required = true,
  });

  final String id;
  final String engineType;
  final String displayName;
  final String url;
  final int sizeBytes;
  final String? sha256;
  final String? quality;
  final bool required;

  factory CoreRequirement.fromJson(Map<String, dynamic> json) {
    return CoreRequirement(
      id: json['id'] as String,
      engineType: json['engineType'] as String,
      displayName: json['displayName'] as String,
      url: json['url'] as String,
      sizeBytes: json['sizeBytes'] as int,
      sha256: json['sha256'] as String?,
      quality: json['quality'] as String?,
      required: json['required'] as bool? ?? true,
    );
  }

  AssetSpec toAssetSpec() {
    return AssetSpec(
      key: id,
      displayName: displayName,
      downloadUrl: url,
      installPath: id,
      sizeBytes: sizeBytes,
      checksum: sha256,
      isCore: true,
      engineType: _parseEngineType(engineType),
    );
  }

  static EngineType? _parseEngineType(String type) {
    return switch (type) {
      'kokoro' => EngineType.kokoro,
      'piper' => EngineType.piper,
      'supertonic' => EngineType.supertonic,
      _ => null,
    };
  }
}

/// Voice specification from manifest.
class VoiceSpec {
  const VoiceSpec({
    required this.id,
    required this.engineId,
    required this.displayName,
    required this.language,
    required this.coreRequirements,
    this.gender,
    this.speakerId,
    this.modelKey,
    this.modelUrl,
    this.modelSize,
    this.configUrl,
    this.previewUrl,
    this.estimatedSynthTimeMs,
  });

  final String id;
  final String engineId;
  final String displayName;
  final String language;
  final List<String> coreRequirements;
  final String? gender;
  final int? speakerId;
  final String? modelKey;
  final String? modelUrl;
  final int? modelSize;
  final String? configUrl;
  final String? previewUrl;
  final int? estimatedSynthTimeMs;

  factory VoiceSpec.fromJson(Map<String, dynamic> json) {
    return VoiceSpec(
      id: json['id'] as String,
      engineId: json['engineId'] as String,
      displayName: json['displayName'] as String,
      language: json['language'] as String,
      coreRequirements: (json['coreRequirements'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      gender: json['gender'] as String?,
      speakerId: json['speakerId'] as int?,
      modelKey: json['modelKey'] as String?,
      modelUrl: json['modelUrl'] as String?,
      modelSize: json['modelSize'] as int?,
      configUrl: json['configUrl'] as String?,
      previewUrl: json['previewUrl'] as String?,
      estimatedSynthTimeMs: json['estimatedSynthTimeMs'] as int?,
    );
  }

  Voice toVoice() {
    final engine = switch (engineId) {
      'kokoro' => EngineType.kokoro,
      'piper' => EngineType.piper,
      'supertonic' => EngineType.supertonic,
      _ => EngineType.device,
    };

    return Voice(
      id: id,
      displayName: displayName,
      engine: engine,
      languageCode: language,
      speakerId: speakerId,
    );
  }
}

/// Complete voice manifest with cores and voices.
class VoiceManifestV2 {
  const VoiceManifestV2({
    required this.version,
    required this.lastUpdated,
    required this.cores,
    required this.voices,
  });

  final int version;
  final String lastUpdated;
  final List<CoreRequirement> cores;
  final List<VoiceSpec> voices;

  factory VoiceManifestV2.fromJson(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return VoiceManifestV2(
      version: json['version'] as int,
      lastUpdated: json['lastUpdated'] as String,
      cores: (json['cores'] as List<dynamic>)
          .map((e) => CoreRequirement.fromJson(e as Map<String, dynamic>))
          .toList(),
      voices: (json['voices'] as List<dynamic>)
          .map((e) => VoiceSpec.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Get core by ID.
  CoreRequirement? getCore(String id) {
    return cores.where((c) => c.id == id).firstOrNull;
  }

  /// Get voice by ID.
  VoiceSpec? getVoice(String id) {
    return voices.where((v) => v.id == id).firstOrNull;
  }

  /// Get all cores required for a voice.
  List<CoreRequirement> getCoresForVoice(String voiceId) {
    final voice = getVoice(voiceId);
    if (voice == null) return [];

    return voice.coreRequirements
        .map((id) => getCore(id))
        .whereType<CoreRequirement>()
        .toList();
  }

  /// Get voices by engine type.
  List<VoiceSpec> getVoicesForEngine(String engineId) {
    return voices.where((v) => v.engineId == engineId).toList();
  }

  /// Get all Kokoro voices.
  List<VoiceSpec> get kokoroVoices => getVoicesForEngine('kokoro');

  /// Get all Piper voices.
  List<VoiceSpec> get piperVoices => getVoicesForEngine('piper');

  /// Get all Supertonic voices.
  List<VoiceSpec> get supertonicVoices => getVoicesForEngine('supertonic');
}
