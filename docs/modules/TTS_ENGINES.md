# tts_engines (packages/tts_engines)

Engine interfaces, routing, caching, and engine adapters.

## Responsibilities

- Define engine contracts (`AiVoiceEngine`) and request/response types.
- Implement a **routing engine** that:
  - checks the cache
  - dispatches to the correct engine adapter by `voiceId`
  - supports cancellation and model unloading
- Provide `AudioCache` interface for storing synthesized audio.

## Key files

- `lib/src/adapters/routing_engine.dart` — main entry point for synthesis.
- `lib/src/adapters/*.dart` — engine-specific adapters (Kokoro/Piper/Supertonic).
- `lib/src/cache/audio_cache.dart` — cache abstraction.

## Data flow (synthesis)

1. Compute cache key from `(voiceId, text, playbackRate)`.
2. Cache hit → return file.
3. Cache miss → route to engine adapter.
4. Adapter uses platform plugin (Android) to synthesize and write output.
5. Mark cache entry as used.

## Extension points

- Add a new adapter implementing `AiVoiceEngine`.
- Extend routing decision logic (e.g., language-based routing).
- Add richer caching policies (LRU/size limits).
