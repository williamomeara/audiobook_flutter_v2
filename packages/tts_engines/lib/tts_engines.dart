/// TTS engine adapters and audio caching.
library;

export 'src/interfaces/ai_voice_engine.dart';
export 'src/interfaces/synth_request.dart';
export 'src/interfaces/synth_result.dart';
export 'src/interfaces/tts_state_machines.dart';
export 'src/interfaces/segment_synth_request.dart';
export 'src/cache/audio_cache.dart';
export 'src/adapters/routing_engine.dart';
export 'src/adapters/kokoro_adapter.dart';
export 'src/adapters/piper_adapter.dart';
export 'src/adapters/supertonic_adapter.dart';
export 'src/synthesis_pool.dart';
