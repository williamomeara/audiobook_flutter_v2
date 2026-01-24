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
export 'src/adaptive_prefetch.dart'; // Configuration flexibility: Adaptive prefetch
export 'src/prefetch_resume_controller.dart'; // Configuration flexibility: Resume control
export 'src/strategies/synthesis_strategy.dart'; // Phase 3: Synthesis strategies
export 'src/synthesis/synthesis.dart'; // Phase 4: Parallel synthesis
export 'src/strategies/synthesis_strategy_manager.dart'; // Phase 3: Strategy management
export 'src/calibration/calibration.dart'; // Phase 2: Engine calibration

// Re-export SmartSynthesisManager for convenience
export 'package:tts_engines/tts_engines.dart' show SmartSynthesisManager;

// Re-export just_audio's AudioPlayer for audio service integration
export 'package:just_audio/just_audio.dart' show AudioPlayer;
