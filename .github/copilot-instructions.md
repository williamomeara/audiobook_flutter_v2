# Audiobook Flutter App - AI Coding Agent Instructions

## Architecture Overview

This is a Flutter audiobook reader application with AI-powered text-to-speech (TTS) synthesis. The app features a modular architecture with local packages for separation of concerns:

- **core_domain**: Shared domain models and business logic
- **downloads**: Asset download and management system with atomic operations
- **playback**: Audio playback services using just_audio and audio_service
- **tts_engines**: TTS engine abstractions and routing
- **platform_android_tts**: Native Android TTS implementations

## Key Components

### State Management
- Uses **Riverpod** for dependency injection and state management
- Providers defined in `lib/app/` (e.g., `tts_providers.dart`, `playback_providers.dart`)
- Follow the pattern: `final provider = Provider<T>((ref) => ...)` or `AsyncNotifier` for async state

### Navigation
- **Go Router** for declarative routing
- Routes defined in `main.dart`: `/` (library), `/book/:id`, `/playback/:bookId`, `/settings`
- Use `context.go('/path')` or `context.push('/path')` for navigation

### TTS System
- Supports 3 engines: Kokoro (high-quality), Piper (fast), Supertonic (advanced)
- Downloads managed by `TtsDownloadManager` in `lib/app/tts_providers.dart`
- Uses `AtomicAssetManager` for reliable downloads with fallback to `ResilientDownloader`
- Models downloaded from GitHub releases (Kokoro) and HuggingFace (Piper/Supertonic)

### File Handling
- EPUB parsing via `epubx` package
- PDF parsing via `pdfrx` package
- File picker for local book selection
- Archive extraction for downloaded models

### Audio Playback
- **just_audio** for core playback
- **audio_service** for background playback and controls
- Audio cache system for synthesized speech

## Development Workflows

### Building and Running
```bash
flutter pub get
flutter run  # Runs on connected device/emulator
flutter build apk  # Android APK
flutter build ios  # iOS (on macOS)
```

### Testing
```bash
flutter test  # Unit and widget tests
flutter test --coverage  # With coverage
```

### Code Quality
- Uses `flutter_lints` for static analysis
- Run `flutter analyze` to check for issues
- Format code with `flutter format .`

## Project-Specific Patterns

### Download Management
- Use `AtomicAssetManager` for downloads requiring integrity
- Fallback to `ResilientDownloader` for robustness (retries, checksums, resume)
- Example in `tts_providers.dart`: sequential downloads with progress tracking

### Provider Patterns
- Async operations use `AsyncNotifier<T>`
- State updates via `state = AsyncData(newState)`
- Watch providers with `ref.watch(provider)`

### Error Handling
- Wrap async operations in try-catch with user-friendly messages
- Use `AsyncValue.guard()` for provider error handling
- Log errors with `developer.log()` for debugging

### File Organization
- `lib/app/`: Providers and controllers
- `lib/ui/screens/`: Main screens (Library, BookDetails, Playback, Settings)
- `lib/ui/widgets/`: Reusable UI components
- `lib/utils/`: Helper utilities like `ResilientDownloader`
- `packages/`: Modular packages for domain separation

### Asset Management
- Voice models stored in app cache directory
- Manifest-driven downloads from `packages/downloads/lib/manifests/voices_manifest.json`
- Atomic moves prevent corruption during downloads

## Integration Points

### External Dependencies
- **HuggingFace**: Model downloads for Piper/Supertonic
- **GitHub Releases**: Kokoro model downloads
- **Native Platforms**: Android ONNX Runtime for TTS inference

### Cross-Package Communication
- `core_domain` provides shared types
- `downloads` handles all asset acquisition
- `tts_engines` abstracts engine implementations
- `platform_android_tts` provides native bindings

## Common Tasks

### Adding a New TTS Engine
1. Add engine type to `core_domain`
2. Create adapter in `tts_engines`
3. Add download logic in `tts_providers.dart`
4. Update manifest and UI

### Adding UI Features
1. Create widget in `lib/ui/widgets/`
2. Add to appropriate screen in `lib/ui/screens/`
3. Use Riverpod providers for state
4. Follow Material Design via `lib/ui/theme/`

### Testing Downloads
- Use Android device for real network testing
- Check progress in Settings > Voice Downloads
- Verify files in app cache after download

Remember: This app prioritizes reliable downloads and modular architecture. Always test downloads on real devices, as emulators may not reflect network behavior accurately.