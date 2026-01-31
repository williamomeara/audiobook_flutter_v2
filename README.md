# Eist

**AI-powered audiobook reader** that transforms any EPUB or PDF into natural-sounding audio.

> *Eist* (pronounced "esht") is Irish for "listen"

## What is Eist?

Eist is a Flutter app that lets you listen to any book. Import an EPUB or PDF, select an AI voice, and Eist reads it aloud with natural-sounding speech. Works offline after downloading voice models.

### Key Features

- 📚 **Read any book** — Import EPUB and PDF files
- 🎙️ **Multiple AI voices** — Kokoro, Piper, Supertonic engines + device TTS fallback
- ⚡ **Smart synthesis** — Pre-generates audio ahead of playback
- 🔇 **Offline capable** — Works without internet after voice download
- 🎛️ **Playback controls** — Variable speed, sleep timer, background playback
- 📑 **Chapter navigation** — Jump between chapters, segments, and positions

---

## Quick Start

### Prerequisites

- Flutter SDK (see `pubspec.yaml` for version)
- Android Studio or Xcode (macOS)

### Run

```bash
flutter pub get
flutter run
```

### Download Voices

1. Open app → **Settings** → **Voice Downloads**
2. Download one or more voice models (~100-500MB each)
3. Select your preferred voice and start listening

---

## Project Architecture

```
lib/                  # Main app code (Riverpod providers, UI, state machines)
├── app/              # Business logic and state management
├── ui/               # Screens and widgets
└── utils/            # Helpers

packages/             # Modular packages
├── core_domain/      # Domain models and text utilities
├── downloads/        # Atomic downloads and voice manifests
├── tts_engines/      # TTS engine abstractions and routing
├── playback/         # Audio playback orchestration
└── platform_android_tts/  # Android Kotlin plugin for TTS inference
```

### Core Technologies

| Layer | Technology |
|-------|------------|
| UI Framework | Flutter |
| State Management | Riverpod |
| Navigation | Go Router |
| Audio Playback | just_audio + audio_service |
| Database | SQLite (drift) with WAL mode |
| TTS Inference | ONNX Runtime (Android native) |

---

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture Overview](docs/architecture/README.md) | System design and state machines |
| [Playback State Machine](docs/architecture/playback_screen_state_machine.md) | Core playback logic |
| [TTS Synthesis](docs/architecture/tts_synthesis_state_machine.md) | Text-to-speech pipeline |
| [Audio Pipeline](docs/architecture/audio_synthesis_pipeline_state_machine.md) | Synthesis and caching |

---

## Development

### Common Commands

```bash
flutter analyze          # Static analysis
flutter test            # Run tests
flutter format .        # Format code
flutter run --release   # Release build
```

### Pre-loading Voice Assets (optional)

For development, you can pre-fetch voice models:

```bash
python3 scripts/fetch_supertonic_assets.py --dest assets/supertonic
```

Set `HF_TOKEN` or `HUGGINGFACE_TOKEN` if Hugging Face repo is gated.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **401 Unauthorized** from HuggingFace | Export `HF_TOKEN` environment variable |
| **Downloads fail** | Check device has ~500MB+ free space |
| **Audio not playing** | Ensure voice model is fully downloaded |
| **App crashes on playback** | Check logcat for ONNX runtime errors |

---

## License

See [LICENSE](LICENSE) file.
