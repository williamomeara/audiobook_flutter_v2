# core_domain (packages/core_domain)

Shared, dependency-light domain models and text utilities.

## Responsibilities

- Domain entities:
  - `Book`, `Chapter`, `Segment`
  - `Voice` (and voice IDs / helpers)
- Deterministic IDs and cache keys:
  - `IdGenerator`
  - `CacheKeyGenerator`
- Text processing helpers:
  - `TextNormalizer`
  - `TextSegmenter`
  - Duration estimation

## Why it’s a separate package

Keeping domain + core utilities isolated reduces coupling:

- UI and platform code can evolve independently.
- `downloads` and `tts_engines` can share the same `VoiceIds`/models without importing Flutter.

## Extension points

- Add new voice IDs or metadata in `src/models/voice.dart`.
- Add new segmentation strategies in `src/utils/text_segmenter.dart`.
