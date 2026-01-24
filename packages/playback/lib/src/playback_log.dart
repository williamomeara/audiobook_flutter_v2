/// Logging utility for the playback package.
///
/// Uses debugPrint for output to flutter logs (adb logcat).
library;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Logger for playback package.
class PlaybackLog {
  static const String _name = 'PLAYBACK';

  static void info(String message) {
    _log('[$_name] $message');
  }

  static void debug(String message) {
    _log('[$_name] [DEBUG] $message');
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log('[$_name] ✗ $message');
    if (error != null) {
      _log('[$_name] Error: $error');
    }
    if (stackTrace != null) {
      _log('[$_name] StackTrace: $stackTrace');
    }
  }

  static void progress(String message) {
    _log('[$_name]   $message');
  }

  static void warning(String message) {
    _log('[$_name] ⚠ $message');
  }

  static void _log(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
