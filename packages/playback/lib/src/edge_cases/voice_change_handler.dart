import 'dart:async';
import 'dart:developer' as developer;

/// Handles graceful voice changes during active playback.
///
/// When the user changes voices mid-playback:
/// 1. Cancels in-progress prefetch for the old voice
/// 2. Preserves current playback position
/// 3. Invalidates cache entries for the old voice
/// 4. Triggers immediate synthesis for current segment with new voice
///
/// This handler coordinates with BufferScheduler via context changes.
class VoiceChangeHandler {
  VoiceChangeHandler({
    required void Function(String reason) onCancelPrefetch,
    required void Function() onInvalidateContext,
    required Future<void> Function() onResynthesizeCurrent,
  }) : _onCancelPrefetch = onCancelPrefetch,
       _onInvalidateContext = onInvalidateContext,
       _onResynthesizeCurrent = onResynthesizeCurrent;

  final void Function(String reason) _onCancelPrefetch;
  final void Function() _onInvalidateContext;
  final Future<void> Function() _onResynthesizeCurrent;

  String? _currentVoiceId;
  bool _isChangingVoice = false;

  /// Whether a voice change is currently in progress.
  bool get isChangingVoice => _isChangingVoice;

  /// Current voice ID.
  String? get currentVoiceId => _currentVoiceId;

  /// Handle a voice change request.
  ///
  /// [newVoiceId] is the new voice to switch to.
  /// [preservePosition] if true, maintains current playback position.
  ///
  /// Returns true if the voice change was processed.
  Future<bool> handleVoiceChange(
    String newVoiceId, {
    bool preservePosition = true,
  }) async {
    // No change needed
    if (_currentVoiceId == newVoiceId) return false;
    
    if (_isChangingVoice) {
      developer.log(
        '[VoiceChangeHandler] Voice change already in progress, ignoring',
        name: 'VoiceChangeHandler',
      );
      return false;
    }

    _isChangingVoice = true;
    final oldVoiceId = _currentVoiceId;

    try {
      developer.log(
        '[VoiceChangeHandler] Voice change: $oldVoiceId -> $newVoiceId',
        name: 'VoiceChangeHandler',
      );

      // Step 1: Cancel any in-progress prefetch
      _onCancelPrefetch('voice change from $oldVoiceId to $newVoiceId');

      // Step 2: Invalidate context (triggers scheduler to reset)
      _onInvalidateContext();

      // Step 3: Update current voice
      _currentVoiceId = newVoiceId;

      // Step 4: Resynthesize current segment with new voice
      await _onResynthesizeCurrent();

      developer.log(
        '[VoiceChangeHandler] Voice change complete',
        name: 'VoiceChangeHandler',
      );

      return true;
    } catch (e, stackTrace) {
      developer.log(
        '[VoiceChangeHandler] Voice change failed: $e',
        name: 'VoiceChangeHandler',
        error: e,
        stackTrace: stackTrace,
      );
      // Restore old voice on failure
      _currentVoiceId = oldVoiceId;
      return false;
    } finally {
      _isChangingVoice = false;
    }
  }

  /// Set the current voice ID without triggering change handlers.
  /// Used during initialization.
  void setInitialVoice(String voiceId) {
    _currentVoiceId = voiceId;
    developer.log(
      '[VoiceChangeHandler] Initial voice set: $voiceId',
      name: 'VoiceChangeHandler',
    );
  }
}
