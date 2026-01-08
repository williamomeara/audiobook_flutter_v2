import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Service for playing bundled voice preview audio samples.
/// 
/// Preview audio files are stored in assets/voice_previews/ and bundled
/// with the app, so users can hear voice samples without downloading.
class VoicePreviewService {
  VoicePreviewService(this._notifyChange);

  final void Function(String? voiceId) _notifyChange;
  AudioPlayer? _player;
  String? _currentlyPlayingVoiceId;

  /// Currently playing voice ID, or null if not playing.
  String? get currentlyPlayingVoiceId => _currentlyPlayingVoiceId;

  /// Check if a preview is currently playing.
  bool get isPlaying => _player?.playing ?? false;

  /// Check if a specific voice preview is currently playing.
  bool isPlayingVoice(String voiceId) => 
      _currentlyPlayingVoiceId == voiceId && isPlaying;

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
      await stop();

      final assetPath = _getAssetPath(voiceId);
      
      // Create new player and set source
      _player = AudioPlayer();
      _currentlyPlayingVoiceId = voiceId;
      _notifyChange(voiceId);
      
      await _player!.setAsset(assetPath);
      
      // Listen for completion to clean up
      _player!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _currentlyPlayingVoiceId = null;
          _notifyChange(null);
        }
      });
      
      await _player!.play();
      return true;
    } catch (e) {
      _currentlyPlayingVoiceId = null;
      _notifyChange(null);
      return false;
    }
  }

  /// Stop any currently playing preview.
  Future<void> stop() async {
    _currentlyPlayingVoiceId = null;
    _notifyChange(null);
    if (_player != null) {
      await _player!.stop();
      await _player!.dispose();
      _player = null;
    }
  }

  /// Dispose of resources.
  Future<void> dispose() async {
    await stop();
  }
}

/// Notifier that manages voice preview playback state.
class VoicePreviewNotifier extends Notifier<String?> {
  VoicePreviewService? _service;

  @override
  String? build() {
    _service = VoicePreviewService((voiceId) {
      state = voiceId;
    });
    ref.onDispose(() => _service?.dispose());
    return null;
  }

  /// Get the preview service.
  VoicePreviewService get service => _service!;

  /// Check if preview exists for a voice.
  Future<bool> hasPreview(String voiceId) => _service!.hasPreview(voiceId);

  /// Play preview for a voice.
  Future<bool> playPreview(String voiceId) => _service!.playPreview(voiceId);

  /// Stop any playing preview.
  Future<void> stop() => _service!.stop();
}

/// Provider for voice preview service and state.
/// 
/// The state is the currently playing voice ID, or null if not playing.
final voicePreviewProvider = NotifierProvider<VoicePreviewNotifier, String?>(() {
  return VoicePreviewNotifier();
});
