# platform_android_tts (packages/platform_android_tts)

Flutter plugin providing Android-native TTS engine execution (via Kotlin).

## Responsibilities

- Define a typed platform API using **Pigeon** (`lib/generated/tts_api.g.dart`).
- Implement Kotlin services that load models and produce audio output.
- Bridge Dart adapters in `tts_engines` to native execution.

## Key pieces

- Dart:
  - `lib/platform_android_tts.dart` (plugin entry)
  - `lib/generated/tts_api.g.dart` (generated)
- Android:
  - `android/src/main/kotlin/.../services/*` (engine services)

## Notes

- This plugin is the natural place to integrate ONNX Runtime and platform-optimized inference.
- Keep model file layout expectations documented (folder names + required files), because `downloads` writes those files and the Kotlin services read them.
