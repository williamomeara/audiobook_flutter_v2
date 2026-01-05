import 'dart:io';

import 'voice_manifest_v2.dart';

/// Service for efficient manifest queries with indexed lookups.
class ManifestService {
  ManifestService(this.manifest) {
    _buildIndices();
  }

  final VoiceManifestV2 manifest;

  // Indexed lookups (O(1))
  late final Map<String, CoreRequirement> _coresById;
  late final Map<String, VoiceSpec> _voicesById;
  late final Map<String, List<VoiceSpec>> _voicesByEngine;
  late final Map<String, List<CoreRequirement>> _coresByEngine;

  void _buildIndices() {
    _coresById = {for (var c in manifest.cores) c.id: c};
    _voicesById = {for (var v in manifest.voices) v.id: v};

    _voicesByEngine = {};
    for (final v in manifest.voices) {
      _voicesByEngine.putIfAbsent(v.engineId, () => []).add(v);
    }

    _coresByEngine = {};
    for (final c in manifest.cores) {
      _coresByEngine.putIfAbsent(c.engineType, () => []).add(c);
    }
  }

  // Core queries
  CoreRequirement? getCore(String coreId) => _coresById[coreId];

  List<CoreRequirement> getCoresForEngine(String engineId) =>
      _coresByEngine[engineId] ?? [];

  List<CoreRequirement> get allCores => manifest.cores;

  // Voice queries
  VoiceSpec? getVoice(String voiceId) => _voicesById[voiceId];

  List<VoiceSpec> getVoicesForEngine(String engineId) =>
      _voicesByEngine[engineId] ?? [];

  List<VoiceSpec> get allVoices => manifest.voices;

  // Dependency queries
  List<CoreRequirement> getRequiredCores(String voiceId) {
    final voice = getVoice(voiceId);
    if (voice == null) return [];
    return voice.coreRequirements
        .map((id) => _coresById[id])
        .whereType<CoreRequirement>()
        .toList();
  }

  /// Get unique cores required for multiple voices.
  Set<String> getUniqueCoreIds(List<String> voiceIds) {
    final coreIds = <String>{};
    for (final voiceId in voiceIds) {
      final voice = getVoice(voiceId);
      if (voice != null) {
        coreIds.addAll(voice.coreRequirements);
      }
    }
    return coreIds;
  }

  /// Estimate download size for a voice (excluding already downloaded cores).
  int estimateVoiceDownloadSize(String voiceId, Set<String> alreadyDownloaded) {
    final cores = getRequiredCores(voiceId);
    return cores
        .where((c) => !alreadyDownloaded.contains(c.id))
        .fold(0, (sum, c) => sum + c.totalSize);
  }

  /// Estimate total download size for multiple voices.
  int estimateMultiVoiceDownloadSize(
      List<String> voiceIds, Set<String> alreadyDownloaded) {
    final uniqueCoreIds = getUniqueCoreIds(voiceIds);
    var total = 0;
    for (final coreId in uniqueCoreIds) {
      if (!alreadyDownloaded.contains(coreId)) {
        final core = getCore(coreId);
        if (core != null) {
          total += core.totalSize;
        }
      }
    }
    return total;
  }

  /// Get engine IDs that have at least one voice.
  Set<String> get engineIds => _voicesByEngine.keys.toSet();

  /// Load manifest from a file.
  static Future<ManifestService> loadFromFile(File file) async {
    final jsonString = await file.readAsString();
    final manifest = VoiceManifestV2.fromJson(jsonString);
    return ManifestService(manifest);
  }

  /// Load manifest from JSON string.
  static ManifestService loadFromString(String jsonString) {
    final manifest = VoiceManifestV2.fromJson(jsonString);
    return ManifestService(manifest);
  }
}
