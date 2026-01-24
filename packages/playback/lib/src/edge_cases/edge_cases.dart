/// Edge case handlers for playback configuration changes.
///
/// These handlers coordinate graceful transitions when configuration
/// changes during active playback:
/// - Voice changes mid-prefetch
/// - Memory pressure from the OS
/// - Rapid rate changes from user scrubbing
/// - Auto-tuning rollback when performance degrades
library;

export 'auto_tune_rollback.dart';
export 'config_snapshot.dart';
export 'memory_pressure_handler.dart';
export 'rate_change_handler.dart';
export 'voice_change_handler.dart';
