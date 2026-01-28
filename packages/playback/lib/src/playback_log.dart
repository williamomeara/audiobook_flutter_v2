/// Logging utility for the playback package.
///
/// Uses debugPrint for output to flutter logs (adb logcat).
///
/// Log levels can be configured via [PlaybackLog.setLogLevel()]:
/// - [PlaybackLogLevel.verbose] - All logs including debug
/// - [PlaybackLogLevel.info] - Info, warning, error (default)  
/// - [PlaybackLogLevel.warning] - Warning and error only
/// - [PlaybackLogLevel.error] - Error only
/// - [PlaybackLogLevel.none] - No logs
library;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Log levels for controlling playback package verbosity.
enum PlaybackLogLevel {
  /// All logs including debug
  verbose,
  /// Info, warning, error
  info,
  /// Warning and error only
  warning,
  /// Error only
  error,
  /// No logs
  none,
}

/// Logger for playback package.
class PlaybackLog {
  static const String _name = 'PLAYBACK';
  
  /// Current log level. Default is [PlaybackLogLevel.warning] for reduced verbosity.
  static PlaybackLogLevel _logLevel = PlaybackLogLevel.warning;

  /// Set the global log level for playback logging.
  static void setLogLevel(PlaybackLogLevel level) {
    _logLevel = level;
  }

  /// Get the current log level.
  static PlaybackLogLevel get logLevel => _logLevel;

  static void info(String message) {
    if (_logLevel.index <= PlaybackLogLevel.info.index) {
      _log('[$_name] $message');
    }
  }

  static void debug(String message) {
    if (_logLevel == PlaybackLogLevel.verbose) {
      _log('[$_name] [DEBUG] $message');
    }
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    if (_logLevel.index <= PlaybackLogLevel.error.index) {
      _log('[$_name] ✗ $message');
      if (error != null) {
        _log('[$_name] Error: $error');
      }
      if (stackTrace != null) {
        _log('[$_name] StackTrace: $stackTrace');
      }
    }
  }

  static void progress(String message) {
    if (_logLevel.index <= PlaybackLogLevel.info.index) {
      _log('[$_name]   $message');
    }
  }

  static void warning(String message) {
    if (_logLevel.index <= PlaybackLogLevel.warning.index) {
      _log('[$_name] ⚠ $message');
    }
  }

  static void _log(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
