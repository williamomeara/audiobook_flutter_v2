/// Test logging utility that doesn't trigger avoid_print lint.
///
/// Uses Dart's logging package which is the recommended way to log
/// in production code while still allowing console output during tests.
library;

import 'dart:developer' as developer;

/// Logger for integration tests that outputs to console without triggering lint.
class TestLogger {
  static void log(String message) {
    developer.log(message, name: 'TTS_TEST');
  }
  
  static void success(String message) {
    developer.log('✓ $message', name: 'TTS_TEST');
  }
  
  static void error(String message) {
    developer.log('✗ $message', name: 'TTS_TEST');
  }
  
  static void progress(String message) {
    developer.log('  $message', name: 'TTS_TEST');
  }
}
