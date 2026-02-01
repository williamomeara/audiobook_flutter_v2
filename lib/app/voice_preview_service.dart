import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// State of the voice preview player.
enum PreviewState {
  idle,
  loading,
  playing,
  error,
}

/// Combined state for voice preview including loading and error states.
class VoicePreviewState {
  const VoicePreviewState({
    this.voiceId,
    this.state = PreviewState.idle,
    this.errorMessage,
  });
  
  final String? voiceId;
  final PreviewState state;
  final String? errorMessage;
  
  bool get isLoading => state == PreviewState.loading;
  bool get isPlaying => state == PreviewState.playing;
  bool get isError => state == PreviewState.error;
  bool get isIdle => state == PreviewState.idle;
  
  bool isLoadingVoice(String id) => voiceId == id && isLoading;
  bool isPlayingVoice(String id) => voiceId == id && isPlaying;
  
  VoicePreviewState copyWith({
    String? voiceId,
    PreviewState? state,
    String? errorMessage,
  }) {
    return VoicePreviewState(
      voiceId: voiceId ?? this.voiceId,
      state: state ?? this.state,
      errorMessage: errorMessage,
    );
  }
  
  static const idle = VoicePreviewState();
}

/// Service for playing bundled voice preview audio samples.
/// 
/// Preview audio files are stored in assets/voice_previews/ and bundled
/// with the app, so users can hear voice samples without downloading.
class VoicePreviewService {
  VoicePreviewService(this._notifyChange);

  final void Function(VoicePreviewState) _notifyChange;
  AudioPlayer? _player;
  VoicePreviewState _state = VoicePreviewState.idle;

  /// Current preview state.
  VoicePreviewState get currentState => _state;

  /// Currently playing voice ID, or null if not playing.
  String? get currentlyPlayingVoiceId => 
      _state.isPlaying ? _state.voiceId : null;

  /// Check if a preview is currently playing.
  bool get isPlaying => _state.isPlaying;

  /// Check if a specific voice preview is currently playing.
  bool isPlayingVoice(String voiceId) => _state.isPlayingVoice(voiceId);
  
  /// Check if a specific voice preview is loading.
  bool isLoadingVoice(String voiceId) => _state.isLoadingVoice(voiceId);

  /// Get the asset path for a voice preview.
  /// 
  /// Returns the asset path if the preview exists, null otherwise.
  String _getAssetPath(String voiceId) {
    // Normalize voice ID to safe filename (replace : with _)
    final safeId = voiceId.replaceAll(':', '_');
    return 'assets/voice_previews/$safeId.wav';
  }

  /// Check if a preview audio file exists for the given voice.
  Future<bool> hasPreview(String voiceId) async {
    try {
      final assetPath = _getAssetPath(voiceId);
      await rootBundle.load(assetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Play the preview audio for the given voice ID.
  /// 
  /// Stops any currently playing preview before starting the new one.
  /// Returns true if playback started successfully.
  Future<bool> playPreview(String voiceId) async {
    try {
      // Stop any existing playback
      await stop(notifyState: false);

      final assetPath = _getAssetPath(voiceId);
      
      // Set loading state
      _state = VoicePreviewState(voiceId: voiceId, state: PreviewState.loading);
      _notifyChange(_state);
      
      // Create new player and set source
      _player = AudioPlayer();
      
      await _player!.setAsset(assetPath);
      
      // Update to playing state
      _state = VoicePreviewState(voiceId: voiceId, state: PreviewState.playing);
      _notifyChange(_state);
      
      // Listen for completion to clean up
      _player!.playerStateStream.listen((playerState) {
        if (playerState.processingState == ProcessingState.completed) {
          _state = VoicePreviewState.idle;
          _notifyChange(_state);
        }
      });
      
      await _player!.play();
      return true;
    } catch (e) {
      _state = VoicePreviewState(
        voiceId: voiceId, 
        state: PreviewState.error,
        errorMessage: 'Preview not available',
      );
      _notifyChange(_state);
      
      // Reset to idle after a short delay
      Future.delayed(const Duration(seconds: 2), () {
        if (_state.voiceId == voiceId && _state.isError) {
          _state = VoicePreviewState.idle;
          _notifyChange(_state);
        }
      });
      return false;
    }
  }

  /// Stop any currently playing preview.
  Future<void> stop({bool notifyState = true}) async {
    _state = VoicePreviewState.idle;
    if (notifyState) {
      _notifyChange(_state);
    }
    if (_player != null) {
      await _player!.stop();
      await _player!.dispose();
      _player = null;
    }
  }

  /// Dispose of resources.
  Future<void> dispose() async {
    // Don't notify state changes during disposal - provider is being torn down
    await stop(notifyState: false);
  }
}

/// Notifier that manages voice preview playback state.
class VoicePreviewNotifier extends Notifier<VoicePreviewState> {
  VoicePreviewService? _service;

  @override
  VoicePreviewState build() {
    _service = VoicePreviewService((newState) {
      state = newState;
    });
    ref.onDispose(() => _service?.dispose());
    return VoicePreviewState.idle;
  }

  /// Get the preview service.
  VoicePreviewService get service => _service!;

  /// Check if preview exists for a voice.
  Future<bool> hasPreview(String voiceId) => _service!.hasPreview(voiceId);

  /// Play preview for a voice.
  Future<bool> playPreview(String voiceId) => _service!.playPreview(voiceId);

  /// Stop any playing preview.
  Future<void> stop() => _service!.stop();
  
  /// Check if a voice is currently loading.
  bool isLoading(String voiceId) => _service!.isLoadingVoice(voiceId);
  
  /// Check if a voice is currently playing.
  bool isPlayingVoice(String voiceId) => _service!.isPlayingVoice(voiceId);
}

/// Provider for voice preview service and state.
/// 
/// The state contains the current preview status including loading and error states.
final voicePreviewProvider = NotifierProvider<VoicePreviewNotifier, VoicePreviewState>(() {
  return VoicePreviewNotifier();
});
