import 'package:platform_android_tts/generated/tts_api.g.dart';

/// Handler for callbacks from native TTS services.
/// 
/// Notifies listeners when voices are unloaded, memory is low,
/// or engine state changes.
class TtsCallbackHandler implements TtsFlutterApi {
  TtsCallbackHandler();

  /// Listeners for voice unload events.
  final List<void Function(NativeEngineType, String)> _voiceUnloadListeners = [];
  
  /// Listeners for memory warning events.
  final List<void Function(NativeEngineType, int, int)> _memoryWarningListeners = [];
  
  /// Listeners for engine state change events.
  final List<void Function(NativeEngineType, NativeCoreState, String?)> _engineStateListeners = [];
  
  /// Listeners for synthesis progress events.
  final List<void Function(String, double)> _progressListeners = [];
  
  /// Listeners for core state change events.
  final List<void Function(CoreStatus)> _coreStateListeners = [];
  
  /// Listeners for engine error events.
  final List<void Function(NativeEngineType, NativeErrorCode, String)> _errorListeners = [];

  /// Add a listener for voice unload events.
  void addVoiceUnloadListener(void Function(NativeEngineType, String) listener) {
    _voiceUnloadListeners.add(listener);
  }
  
  /// Remove a voice unload listener.
  void removeVoiceUnloadListener(void Function(NativeEngineType, String) listener) {
    _voiceUnloadListeners.remove(listener);
  }
  
  /// Add a listener for memory warning events.
  void addMemoryWarningListener(void Function(NativeEngineType, int, int) listener) {
    _memoryWarningListeners.add(listener);
  }
  
  /// Remove a memory warning listener.
  void removeMemoryWarningListener(void Function(NativeEngineType, int, int) listener) {
    _memoryWarningListeners.remove(listener);
  }
  
  /// Add a listener for engine state change events.
  void addEngineStateListener(void Function(NativeEngineType, NativeCoreState, String?) listener) {
    _engineStateListeners.add(listener);
  }
  
  /// Remove an engine state listener.
  void removeEngineStateListener(void Function(NativeEngineType, NativeCoreState, String?) listener) {
    _engineStateListeners.remove(listener);
  }

  @override
  void onSynthesisProgress(String requestId, double progress) {
    for (final listener in _progressListeners) {
      listener(requestId, progress);
    }
  }

  @override
  void onCoreStateChanged(CoreStatus status) {
    for (final listener in _coreStateListeners) {
      listener(status);
    }
  }

  @override
  void onEngineError(NativeEngineType engineType, NativeErrorCode code, String message) {
    for (final listener in _errorListeners) {
      listener(engineType, code, message);
    }
  }

  @override
  void onVoiceUnloaded(NativeEngineType engineType, String voiceId) {
    for (final listener in _voiceUnloadListeners) {
      listener(engineType, voiceId);
    }
  }

  @override
  void onMemoryWarning(NativeEngineType engineType, int availableMB, int totalMB) {
    for (final listener in _memoryWarningListeners) {
      listener(engineType, availableMB, totalMB);
    }
  }

  @override
  void onEngineStateChanged(NativeEngineType engineType, NativeCoreState state, String? errorMessage) {
    for (final listener in _engineStateListeners) {
      listener(engineType, state, errorMessage);
    }
  }
}
