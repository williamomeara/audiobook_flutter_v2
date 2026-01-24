import 'dart:io' show Platform;

import 'package:core_domain/core_domain.dart';

import '../tts_log.dart';

/// Manages memory for multiple TTS engines.
/// 
/// Implements the "Active Engine Pattern" - only keeps one engine
/// fully loaded at a time on memory-constrained platforms (iOS).
/// When switching between engines, unloads the previous engine first.
class EngineMemoryManager {
  EngineMemoryManager({
    int? maxLoadedEngines,
  }) : _maxLoadedEngines = maxLoadedEngines ?? _platformDefault();

  /// Maximum number of engines to keep loaded simultaneously.
  /// Default: 1 on iOS (aggressive), 2 on Android (lazy).
  final int _maxLoadedEngines;
  
  /// Currently loaded engines in LRU order (most recent at end).
  final List<EngineType> _loadedEngines = [];
  
  /// Engines that failed to unload - may still be using memory.
  final Set<EngineType> _failedUnloads = {};
  
  /// The currently active engine (last used for synthesis).
  EngineType? get activeEngine => _loadedEngines.isNotEmpty ? _loadedEngines.last : null;
  
  /// All currently loaded engines.
  List<EngineType> get loadedEngines => List.unmodifiable(_loadedEngines);
  
  /// Engines that failed to unload (may still hold memory).
  Set<EngineType> get failedUnloads => Set.unmodifiable(_failedUnloads);
  
  /// Platform-aware default for max loaded engines.
  static int _platformDefault() {
    if (Platform.isIOS) {
      return 1; // Aggressive on iOS due to memory limits
    }
    return 2; // Allow 2 on Android for faster switching
  }
  
  /// Prepare to use an engine.
  /// 
  /// If switching to a different engine and we're at capacity,
  /// unloads the least recently used engine first.
  /// 
  /// [engineType] - The engine type to prepare.
  /// [unloadCallback] - Called to unload an engine when needed.
  /// 
  /// Returns true if an engine was unloaded, false otherwise.
  Future<bool> prepareForEngine(
    EngineType engineType, {
    required Future<void> Function(EngineType) unloadCallback,
  }) async {
    // Already using this engine - just bump to most recent
    if (_loadedEngines.contains(engineType)) {
      _loadedEngines.remove(engineType);
      _loadedEngines.add(engineType);
      TtsLog.debug('EngineMemoryManager: ${engineType.name} is already loaded, bumped to MRU');
      return false;
    }
    
    // Need to load a new engine
    bool unloadedAny = false;
    
    // On iOS, try to retry unloading any engines that previously failed
    if (Platform.isIOS && _failedUnloads.isNotEmpty) {
      TtsLog.info('EngineMemoryManager: Retrying ${_failedUnloads.length} failed unloads');
      for (final engine in _failedUnloads.toList()) {
        try {
          await unloadCallback(engine);
          _failedUnloads.remove(engine);
          TtsLog.info('EngineMemoryManager: Successfully unloaded previously failed ${engine.name}');
        } catch (e) {
          TtsLog.error('EngineMemoryManager: Retry unload of ${engine.name} still failing: $e');
        }
      }
    }
    
    // Unload engines if we're at or over capacity
    while (_loadedEngines.length >= _maxLoadedEngines && _loadedEngines.isNotEmpty) {
      final engineToUnload = _loadedEngines.removeAt(0); // LRU at front
      TtsLog.info('EngineMemoryManager: Unloading ${engineToUnload.name} to make room for ${engineType.name}');
      
      try {
        await unloadCallback(engineToUnload);
        _failedUnloads.remove(engineToUnload); // Clear any previous failure
        unloadedAny = true;
      } catch (e) {
        TtsLog.error('EngineMemoryManager: Failed to unload ${engineToUnload.name}: $e');
        // Track the failure but continue - we need to make room
        _failedUnloads.add(engineToUnload);
        // Still count as "unloaded" from manager perspective to prevent infinite loop
        unloadedAny = true;
      }
    }
    
    // Mark new engine as loaded
    _loadedEngines.add(engineType);
    final status = _failedUnloads.isEmpty 
        ? '' 
        : ' (warning: ${_failedUnloads.length} engines failed to unload)';
    TtsLog.info('EngineMemoryManager: Prepared ${engineType.name} (loaded: ${_loadedEngines.map((e) => e.name).join(", ")})$status');
    
    return unloadedAny;
  }
  
  /// Mark an engine as unloaded (external unload).
  void markUnloaded(EngineType engineType) {
    _loadedEngines.remove(engineType);
    _failedUnloads.remove(engineType); // Clear any failure tracking
    TtsLog.debug('EngineMemoryManager: Marked ${engineType.name} as unloaded');
  }
  
  /// Unload all engines except the active one.
  Future<void> unloadInactive({
    required Future<void> Function(EngineType) unloadCallback,
  }) async {
    if (_loadedEngines.length <= 1) return;
    
    final active = activeEngine;
    final toUnload = _loadedEngines.where((e) => e != active).toList();
    
    for (final engine in toUnload) {
      TtsLog.info('EngineMemoryManager: Unloading inactive ${engine.name}');
      try {
        await unloadCallback(engine);
        _loadedEngines.remove(engine);
      } catch (e) {
        TtsLog.error('EngineMemoryManager: Failed to unload ${engine.name}: $e');
      }
    }
  }
  
  /// Force unload all engines (e.g., low memory warning).
  Future<void> unloadAll({
    required Future<void> Function(EngineType) unloadCallback,
  }) async {
    final toUnload = List<EngineType>.from(_loadedEngines);
    _loadedEngines.clear();
    
    for (final engine in toUnload) {
      TtsLog.info('EngineMemoryManager: Force unloading ${engine.name}');
      try {
        await unloadCallback(engine);
      } catch (e) {
        TtsLog.error('EngineMemoryManager: Failed to unload ${engine.name}: $e');
      }
    }
  }
}
