/// TTS engine adapters and audio caching.
library;

export 'src/interfaces/ai_voice_engine.dart';
export 'src/interfaces/synth_request.dart';
export 'src/interfaces/synth_result.dart';
export 'src/interfaces/tts_state_machines.dart';
export 'src/interfaces/segment_synth_request.dart';
export 'src/cache/audio_cache.dart';
export 'src/cache/cache_entry_metadata.dart';
export 'src/cache/intelligent_cache_manager.dart';
export 'src/cache/cache_compression.dart';
export 'src/adapters/routing_engine.dart';
export 'src/adapters/kokoro_adapter.dart';
export 'src/adapters/piper_adapter.dart';
export 'src/adapters/supertonic_adapter.dart';
export 'src/synthesis_pool.dart';

// Smart synthesis management for eliminating buffering
export 'src/smart_synthesis/smart_synthesis_manager.dart';
export 'src/smart_synthesis/supertonic_smart_synthesis.dart';
export 'src/smart_synthesis/piper_smart_synthesis.dart';
