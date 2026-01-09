// Playback management for audiobook app.

export 'src/playback_config.dart';
export 'src/playback_state.dart';
export 'src/audio_output.dart';
export 'src/buffer_scheduler.dart';
export 'src/playback_controller.dart';
export 'src/resource_monitor.dart';  // Phase 2: Battery-aware prefetch
export 'src/segment_readiness.dart'; // Segment readiness UI feedback
export 'src/engine_config.dart';     // Phase 4: Auto-tuning device tier configs
export 'src/device_profiler.dart';   // Phase 4: Device performance profiling
export 'src/engine_config_manager.dart'; // Phase 4: Config persistence

// Re-export SmartSynthesisManager for convenience
export 'package:tts_engines/tts_engines.dart' show SmartSynthesisManager;

// Re-export just_audio's AudioPlayer for audio service integration
export 'package:just_audio/just_audio.dart' show AudioPlayer;
