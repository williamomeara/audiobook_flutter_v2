/// Comprehensive logging utility for the audiobook app.
///
/// Uses debugPrint for output to flutter logs (adb logcat).
/// debugPrint throttles output to avoid dropped messages.
///
/// Log levels can be configured via [AppLogger.setLogLevel()]:
/// - [LogLevel.verbose] - All logs including debug
/// - [LogLevel.info] - Info, success, warning, error (default)
/// - [LogLevel.warning] - Warning and error only
/// - [LogLevel.error] - Error only
/// - [LogLevel.none] - No logs
library;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Log levels for controlling verbosity.
enum LogLevel {
  /// All logs including debug
  verbose,
  /// Info, success, warning, error
  info,
  /// Warning and error only
  warning,
  /// Error only
  error,
  /// No logs
  none,
}

/// Application logger that outputs to console and flutter logs.
///
/// Usage:
/// ```dart
/// import 'package:audiobook_flutter_v2/utils/app_logger.dart';
///
/// // Configure log level (default: LogLevel.info)
/// AppLogger.setLogLevel(LogLevel.warning); // Less verbose
/// AppLogger.setLogLevel(LogLevel.verbose); // Most verbose
///
/// AppLogger.info('Starting synthesis...');
/// AppLogger.success('Synthesis complete!');
/// AppLogger.error('Failed to download');
/// AppLogger.debug('Debug info: $value');
/// ```
class AppLogger {
  /// Current log level. Default is [LogLevel.info].
  static LogLevel _logLevel = LogLevel.info;

  /// Set the global log level.
  static void setLogLevel(LogLevel level) {
    _logLevel = level;
  }

  /// Get the current log level.
  static LogLevel get logLevel => _logLevel;

  /// Log an informational message.
  static void info(String message, {String? name}) {
    if (_logLevel.index <= LogLevel.info.index) {
      _log('[${name ?? 'APP'}] INFO: $message');
    }
  }

  /// Log a success message with ✓ prefix.
  static void success(String message, {String? name}) {
    if (_logLevel.index <= LogLevel.info.index) {
      _log('[${name ?? 'APP'}] ✓ $message');
    }
  }

  /// Log an error message with ✗ prefix.
  static void error(String message, {String? name, Object? error, StackTrace? stackTrace}) {
    if (_logLevel.index <= LogLevel.error.index) {
      _log('[${name ?? 'APP'}] ✗ $message');
      if (error != null) {
        _log('[${name ?? 'APP'}] Error: $error');
      }
      if (stackTrace != null) {
        _log('[${name ?? 'APP'}] StackTrace: $stackTrace');
      }
    }
  }

  /// Log a debug message (typically more verbose).
  static void debug(String message, {String? name}) {
    if (_logLevel == LogLevel.verbose) {
      _log('[${name ?? 'APP'}] [DEBUG] $message');
    }
  }

  /// Log a progress update.
  static void progress(String message, {String? name}) {
    if (_logLevel.index <= LogLevel.info.index) {
      _log('[${name ?? 'APP'}]   $message');
    }
  }

  /// Log a warning message.
  static void warning(String message, {String? name}) {
    if (_logLevel.index <= LogLevel.warning.index) {
      _log('[${name ?? 'APP'}] ⚠ $message');
    }
  }

  /// Log a message with a specific level indicator.
  static void log(String message, {String? name, int level = 0}) {
    if (_logLevel.index <= LogLevel.info.index) {
      _log('[${name ?? 'APP'}] $message');
    }
  }

  /// Log a separator line.
  static void separator({int length = 50, String char = '='}) {
    if (_logLevel.index <= LogLevel.info.index) {
      _log('[APP] ${char * length}');
    }
  }

  /// Internal logging method - uses debugPrint in debug mode.
  static void _log(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}

/// Shorthand logger for playback-related logs.
class PlaybackLogger {
  static const String _name = 'PLAYBACK';

  static void info(String message) => AppLogger.info(message, name: _name);
  static void debug(String message) => AppLogger.debug(message, name: _name);
  static void error(String message, {Object? error}) =>
      AppLogger.error(message, name: _name, error: error);
}

/// Shorthand logger for TTS-related logs.
class TtsLogger {
  static const String _name = 'TTS';

  static void info(String message) => AppLogger.info(message, name: _name);
  static void debug(String message) => AppLogger.debug(message, name: _name);
  static void error(String message, {Object? error}) =>
      AppLogger.error(message, name: _name, error: error);
}

/// Shorthand logger for download-related logs.
class DownloadLogger {
  static const String _name = 'DOWNLOAD';

  static void info(String message) => AppLogger.info(message, name: _name);
  static void progress(String message) => AppLogger.progress(message, name: _name);
  static void error(String message, {Object? error}) =>
      AppLogger.error(message, name: _name, error: error);
}

/// Shorthand logger for developer screen.
class DevLogger {
  static const String _name = 'DEV';

  static void info(String message) => AppLogger.info(message, name: _name);
  static void debug(String message) => AppLogger.debug(message, name: _name);
  static void error(String message, {Object? error}) =>
      AppLogger.error(message, name: _name, error: error);
}
