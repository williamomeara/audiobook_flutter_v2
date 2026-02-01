/// Logging utility for the tts_engines package.
///
/// Uses debugPrint for output to flutter logs (adb logcat).
///
/// Log levels can be configured via [TtsLog.setLogLevel()]:
/// - [TtsLogLevel.verbose] - All logs including debug
/// - [TtsLogLevel.info] - Info, warning, error
/// - [TtsLogLevel.warning] - Warning and error only (default)
/// - [TtsLogLevel.error] - Error only
/// - [TtsLogLevel.none] - No logs
library;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Log levels for the TTS engines package.
enum TtsLogLevel {
  /// All logs including verbose debug output
  verbose,
  /// Standard info, warning, error
  info,
  /// Warning and error only (default)
  warning,
  /// Error only
  error,
  /// No logs
  none,
}

/// Logger for TTS engines package.
class TtsLog {
  static const String _name = 'TTS';
  
  /// Current log level. Default is [TtsLogLevel.warning] for reduced verbosity.
  static TtsLogLevel _logLevel = TtsLogLevel.warning;

  /// Set the global log level.
  static void setLogLevel(TtsLogLevel level) {
    _logLevel = level;
  }

  /// Get the current log level.
  static TtsLogLevel get logLevel => _logLevel;

  static void info(String message) {
    if (_logLevel.index <= TtsLogLevel.info.index) {
      _log('[$_name] $message');
    }
  }

  static void debug(String message) {
    if (_logLevel == TtsLogLevel.verbose) {
      _log('[$_name] [DEBUG] $message');
    }
  }
  
  static void warning(String message) {
    if (_logLevel.index <= TtsLogLevel.warning.index) {
      _log('[$_name] ⚠️ $message');
    }
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    if (_logLevel.index <= TtsLogLevel.error.index) {
      _log('[$_name] ✗ $message');
      if (error != null) {
        _log('[$_name] Error: $error');
      }
      if (stackTrace != null) {
        _log('[$_name] StackTrace: $stackTrace');
      }
    }
  }

  static void _log(String message) {
    if (kDebugMode) {
      final timestamp = DateTime.now().toIso8601String();
      debugPrint('$timestamp $message');
    }
  }
}
