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

  /// Current platform name for filtering
  static String get _currentPlatform =>
      Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other');

  void _buildIndices() {
    // Filter cores to only include those available on this platform
    final platformCores = manifest.cores.where(_isPlatformMatch).toList();
    _coresById = {for (var c in platformCores) c.id: c};
    _voicesById = {for (var v in manifest.voices) v.id: v};

    _voicesByEngine = {};
    for (final v in manifest.voices) {
      _voicesByEngine.putIfAbsent(v.engineId, () => []).add(v);
    }

    _coresByEngine = {};
    for (final c in platformCores) {
      _coresByEngine.putIfAbsent(c.engineType, () => []).add(c);
    }
  }

  /// Check if a core matches the current platform
  bool _isPlatformMatch(CoreRequirement core) {
    if (core.platform == null) return true;
    return core.platform == _currentPlatform;
  }

  // Core queries
  CoreRequirement? getCore(String coreId) => _coresById[coreId];

  List<CoreRequirement> getCoresForEngine(String engineId) =>
      _coresByEngine[engineId] ?? [];

  List<CoreRequirement> get allCores => _coresById.values.toList();

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
        .map((id) => _resolvePlatformCore(id))
        .whereType<CoreRequirement>()
        .toList();
  }

  /// Resolve a core ID to the platform-specific version if available.
  /// For example, 'kokoro_core_v1' on Android becomes 'kokoro_core_android_v1'
  CoreRequirement? _resolvePlatformCore(String coreId) {
    // First, try exact match in platform-filtered cores
    if (_coresById.containsKey(coreId)) {
      return _coresById[coreId];
    }
    
    // For kokoro, resolve to platform-specific cores
    if (coreId == 'kokoro_core_v1') {
      if (_currentPlatform == 'android') {
        return _coresById['kokoro_core_android_v1'];
      } else if (_currentPlatform == 'ios') {
        return _coresById['kokoro_core_ios_v1'];
      }
    }
    
    return null;
  }

  /// Get unique cores required for multiple voices.
  Set<String> getUniqueCoreIds(List<String> voiceIds) {
    final coreIds = <String>{};
    for (final voiceId in voiceIds) {
      final cores = getRequiredCores(voiceId);
      for (final core in cores) {
        coreIds.add(core.id);
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
