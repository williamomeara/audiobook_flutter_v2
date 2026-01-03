# playback (packages/playback)

Audio playback orchestration.

## Responsibilities

- Provide playback abstractions over `just_audio` and `audio_service`.
- Coordinate buffering/scheduling to produce smooth playback.

## Key files

- `lib/src/playback_controller.dart` — high-level playback state and control.
- `lib/src/buffer_scheduler.dart` — scheduling/buffering logic.
- `lib/src/playback_state.dart` — playback state model.

## Integration points

- TTS produces audio files into the `AudioCache`.
- Playback loads audio from disk and plays via `just_audio` (with background controls via `audio_service`).
