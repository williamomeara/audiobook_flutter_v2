/// Logging utility for the tts_engines package.
///
/// Uses dart:developer log which doesn't trigger avoid_print lint.
library;

import 'dart:developer' as developer;

/// Logger for TTS engines package.
class TtsLog {
  static const String _name = 'TTS';

  static void info(String message) {
    developer.log(message, name: _name);
  }

  static void debug(String message) {
    developer.log('[DEBUG] $message', name: _name);
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log('✗ $message', name: _name, error: error, stackTrace: stackTrace);
  }
}
