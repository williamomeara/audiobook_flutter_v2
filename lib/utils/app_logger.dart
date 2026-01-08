/// Comprehensive logging utility for the audiobook app.
///
/// Uses dart:developer log which doesn't trigger avoid_print lint
/// and still outputs to console during flutter run and testing.
library;

import 'dart:developer' as developer;

/// Application logger that outputs to console without triggering lint warnings.
///
/// Usage:
/// ```dart
/// import 'package:audiobook_flutter_v2/utils/app_logger.dart';
///
/// AppLogger.info('Starting synthesis...');
/// AppLogger.success('Synthesis complete!');
/// AppLogger.error('Failed to download');
/// AppLogger.debug('Debug info: $value');
/// ```
class AppLogger {
  /// Log an informational message.
  static void info(String message, {String? name}) {
    developer.log(message, name: name ?? 'APP');
  }

  /// Log a success message with ✓ prefix.
  static void success(String message, {String? name}) {
    developer.log('✓ $message', name: name ?? 'APP');
  }

  /// Log an error message with ✗ prefix.
  static void error(String message, {String? name, Object? error, StackTrace? stackTrace}) {
    developer.log(
      '✗ $message',
      name: name ?? 'APP',
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Log a debug message (typically more verbose).
  static void debug(String message, {String? name}) {
    developer.log('[DEBUG] $message', name: name ?? 'APP');
  }

  /// Log a progress update.
  static void progress(String message, {String? name}) {
    developer.log('  $message', name: name ?? 'APP');
  }

  /// Log a warning message.
  static void warning(String message, {String? name}) {
    developer.log('⚠ $message', name: name ?? 'APP');
  }

  /// Log a message with a specific level indicator.
  static void log(String message, {String? name, int level = 0}) {
    developer.log(message, name: name ?? 'APP', level: level);
  }

  /// Log a separator line.
  static void separator({int length = 50, String char = '='}) {
    developer.log(char * length, name: 'APP');
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
