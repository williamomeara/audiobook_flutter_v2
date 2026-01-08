import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'engine_config.dart';
import 'playback_log.dart';

/// Manages engine configurations with persistence.
///
/// Stores per-engine, per-device configurations that are determined
/// by the auto-tuning profiler. Also tracks when each engine was last
/// profiled to enable periodic re-tuning.
class DeviceEngineConfigManager {
  DeviceEngineConfigManager({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;
  
  /// In-memory cache of loaded configs.
  final Map<String, DeviceEngineConfig> _cache = {};

  /// Key prefix for stored configs.
  static const _keyPrefix = 'engine_config_';
  
  /// Key prefix for last tuned timestamps.
  static const _tunedPrefix = 'engine_tuned_';

  /// Days after which re-tuning is recommended.
  static const retuneDays = 30;

  /// Initialize with SharedPreferences.
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Ensure initialized before operations.
  Future<void> _ensureInitialized() async {
    if (_prefs == null) {
      await initialize();
    }
  }

  /// Save configuration for an engine.
  Future<void> saveConfig(DeviceEngineConfig config) async {
    await _ensureInitialized();
    
    _cache[config.engineId] = config;
    
    final json = jsonEncode(config.toJson());
    await _prefs?.setString('$_keyPrefix${config.engineId}', json);
    await _prefs?.setString(
      '$_tunedPrefix${config.engineId}',
      DateTime.now().toIso8601String(),
    );
    
    PlaybackLog.info('Saved config for ${config.engineId}: ${config.deviceTier}');
  }

  /// Load configuration for an engine.
  ///
  /// Returns null if no configuration has been saved.
  Future<DeviceEngineConfig?> loadConfig(String engineId) async {
    await _ensureInitialized();

    // Check cache first
    if (_cache.containsKey(engineId)) {
      return _cache[engineId];
    }

    // Load from storage
    final json = _prefs?.getString('$_keyPrefix$engineId');
    if (json == null) {
      return null;
    }

    try {
      final config = DeviceEngineConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
      _cache[engineId] = config;
      return config;
    } catch (e) {
      PlaybackLog.error('Failed to parse config for $engineId: $e');
      return null;
    }
  }

  /// Get configuration, falling back to default if not profiled.
  Future<DeviceEngineConfig> getConfigOrDefault(String engineId) async {
    final saved = await loadConfig(engineId);
    if (saved != null) {
      return saved;
    }
    return DeviceEngineConfig.defaultConfig(engineId);
  }

  /// Check if an engine needs re-tuning.
  Future<bool> needsRetuning(String engineId) async {
    await _ensureInitialized();

    final tunedAtStr = _prefs?.getString('$_tunedPrefix$engineId');
    if (tunedAtStr == null) {
      return true; // Never tuned
    }

    try {
      final tunedAt = DateTime.parse(tunedAtStr);
      final daysSince = DateTime.now().difference(tunedAt).inDays;
      return daysSince > retuneDays;
    } catch (e) {
      return true; // Invalid date, needs retuning
    }
  }

  /// Get when engine was last tuned.
  Future<DateTime?> getLastTunedDate(String engineId) async {
    await _ensureInitialized();

    final tunedAtStr = _prefs?.getString('$_tunedPrefix$engineId');
    if (tunedAtStr == null) {
      return null;
    }

    try {
      return DateTime.parse(tunedAtStr);
    } catch (e) {
      return null;
    }
  }

  /// Check if engine has been profiled.
  Future<bool> hasBeenProfiled(String engineId) async {
    final config = await loadConfig(engineId);
    return config?.tunedAt != null;
  }

  /// Delete configuration for an engine.
  Future<void> deleteConfig(String engineId) async {
    await _ensureInitialized();
    
    _cache.remove(engineId);
    await _prefs?.remove('$_keyPrefix$engineId');
    await _prefs?.remove('$_tunedPrefix$engineId');
    
    PlaybackLog.info('Deleted config for $engineId');
  }

  /// Delete all configurations.
  Future<void> deleteAllConfigs() async {
    await _ensureInitialized();
    
    _cache.clear();
    
    final keys = _prefs?.getKeys() ?? {};
    for (final key in keys) {
      if (key.startsWith(_keyPrefix) || key.startsWith(_tunedPrefix)) {
        await _prefs?.remove(key);
      }
    }
    
    PlaybackLog.info('Deleted all engine configs');
  }

  /// Get all saved engine IDs.
  Future<List<String>> getSavedEngineIds() async {
    await _ensureInitialized();

    final engineIds = <String>[];
    final keys = _prefs?.getKeys() ?? {};
    
    for (final key in keys) {
      if (key.startsWith(_keyPrefix)) {
        engineIds.add(key.substring(_keyPrefix.length));
      }
    }
    
    return engineIds;
  }

  /// Get summary of all configurations.
  Future<Map<String, DevicePerformanceTier>> getConfigSummary() async {
    final summary = <String, DevicePerformanceTier>{};
    final engineIds = await getSavedEngineIds();
    
    for (final engineId in engineIds) {
      final config = await loadConfig(engineId);
      if (config != null) {
        summary[engineId] = config.deviceTier;
      }
    }
    
    return summary;
  }
}
