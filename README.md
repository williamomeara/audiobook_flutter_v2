# Audiobook Flutter v2

Flutter audiobook reader with multi-engine AI text-to-speech (TTS), robust model downloads, and background playback.

## Features

- Import and parse **EPUB** (and PDF support via `pdfrx`).
- Multi-engine TTS routing:
  - **Kokoro**, **Piper**, **Supertonic** (plus device TTS fallback).
- Reliable large downloads with atomic install + progress UI.
- Playback via `just_audio` + `audio_service`.

## Quickstart

### Prerequisites

- Flutter SDK + Dart (see `pubspec.yaml` for minimum Dart SDK)
- Android Studio (or Xcode on macOS for iOS)

### Run

```bash
flutter pub get
flutter run
```

## TTS model assets

You can download voice models from inside the app:

- Settings → **Voice Downloads**

### Optional: fetch Supertonic assets via script

This repo includes a helper script (useful for pre-loading assets during development):

```bash
python3 scripts/fetch_supertonic_assets.py --dest assets/supertonic
```

Notes:

- The script **prefers a GitHub release archive** if `SUPERSONIC_RELEASE_URL` is set (or `--supertonic-release-url`).
- It falls back to per-file downloads from Hugging Face.
- If the Hugging Face repo is gated you must set `HF_TOKEN` (or `HUGGINGFACE_TOKEN`).

Useful flags:

```bash
python3 scripts/fetch_supertonic_assets.py --revision main --style f1,m1 --force
```

## Project structure

- `lib/` — app code (Riverpod providers, UI, parsers)
- `packages/` — local packages:
  - `core_domain/` — domain models + text utilities
  - `downloads/` — atomic downloads + voice manifest
  - `tts_engines/` — engine interfaces + routing + cache
  - `playback/` — playback orchestration
  - `platform_android_tts/` — Android plugin + Kotlin services

## Docs

- High-level architecture: `docs/ARCHITECTURE.md`
- Module deep dives: `docs/modules/README.md`
- TTS implementation notes: `docs/TTS_IMPLEMENTATION_COMPLETE.md`

## Common dev commands

```bash
flutter analyze
flutter test
flutter format .
```

## Troubleshooting

- **Hugging Face 401 Unauthorized**: export `HF_TOKEN` / `HUGGINGFACE_TOKEN` and retry.
- **Large downloads**: ensure the device has sufficient free space (several hundred MB for all engines).
