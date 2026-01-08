/// Logging utility for the playback package.
///
/// Uses dart:developer log which doesn't trigger avoid_print lint.
library;

import 'dart:developer' as developer;

/// Logger for playback package.
class PlaybackLog {
  static const String _name = 'PLAYBACK';

  static void info(String message) {
    developer.log(message, name: _name);
  }

  static void debug(String message) {
    developer.log('[DEBUG] $message', name: _name);
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log('✗ $message', name: _name, error: error, stackTrace: stackTrace);
  }

  static void progress(String message) {
    developer.log('  $message', name: _name);
  }

  static void warning(String message) {
    developer.log('⚠ $message', name: _name);
  }
}
