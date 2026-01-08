/// Playback controller with buffering and prefetch for audiobook TTS.
library playback;

export 'src/playback_config.dart';
export 'src/playback_state.dart';
export 'src/audio_output.dart';
export 'src/buffer_scheduler.dart';
export 'src/playback_controller.dart';
export 'src/resource_monitor.dart';  // Phase 2: Battery-aware prefetch
export 'src/segment_readiness.dart'; // Segment readiness UI feedback

// Re-export SmartSynthesisManager for convenience
export 'package:tts_engines/tts_engines.dart' show SmartSynthesisManager;
