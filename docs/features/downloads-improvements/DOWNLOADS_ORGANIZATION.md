# Download Organization in Audiobook Flutter App

## Overview

This document analyzes how downloads are organized in the audiobook Flutter app's downloads manager and settings system.

## Architecture Overview

The app uses a modular architecture with a dedicated `downloads` package for asset download and management with atomic operations. The system supports three TTS engines: Kokoro (high-quality), Piper (fast), and Supertonic (advanced).

## Key Components

### Download Managers

- **`AtomicAssetManager`**: Provides corruption-safe downloads using the .tmp pattern with SHA256 verification
- **`FileAssetManager`**: Basic file-based asset manager for simpler use cases
- **`VoiceManifestV2`**: JSON-driven manifest system defining cores and voices

### Download Process (AtomicAssetManager)

The download process follows a 5-phase atomic pattern to ensure reliability:

1. **Download to .tmp file** (resumable downloads with progress tracking)
2. **Extract to .tmp directory** (for archives like tar.gz/zip)
3. **Verify SHA256 checksum** (best-effort verification for main model files)
4. **Atomic rename** (.tmp → final directory, with rollback capability on failure)
5. **Write manifest** (.manifest file marks successful installation)

## Manifest-Driven Organization

Downloads are organized via `packages/downloads/lib/manifests/voices_manifest.json`:

```json
{
  "version": 2,
  "lastUpdated": "2026-01-03",
  "cores": [
    {
      "id": "kokoro_model_v1",
      "engineType": "kokoro",
      "displayName": "Kokoro TTS Model (Q8)",
      "url": "https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0/kokoro-v1.0.onnx",
      "sizeBytes": 94371840,
      "sha256": "placeholder_kokoro_model_sha256",
      "quality": "q8",
      "required": true
    }
  ],
  "voices": [
    {
      "id": "kokoro_af",
      "engineId": "kokoro",
      "displayName": "Kokoro - AF (Default)",
      "language": "en",
      "gender": "female",
      "speakerId": 0,
      "coreRequirements": ["kokoro_model_v1", "kokoro_voices_v1", "espeak_ng_data_v1"],
      "estimatedSynthTimeMs": 1500
    }
  ]
}
```

## File System Organization

Assets are installed in the app's cache directory following this structure:

```
<app_cache>/voice_assets/
├── kokoro_model_v1/          # Core model directory
│   ├── model.onnx
│   └── .manifest
├── kokoro_voices_v1/         # Voice styles
│   ├── voices.bin
│   └── .manifest
├── piper_en_GB-alan-medium/  # Per-voice models
│   ├── model.onnx
│   └── model.onnx.json
└── supertonic/               # Supertonic core
    ├── autoencoder.onnx
    ├── text_encoder.onnx
    ├── duration_predictor.onnx
    └── .manifest
```

## Settings UI Organization

The Settings screen presents downloads in a dedicated "Voice Downloads" section:

- **Per-Engine Rows**: Separate rows for Kokoro, Piper, and Supertonic
- **Status Indicators**: Status badges showing current state (Not installed, Downloading, Installing, Ready, Failed)
- **Progress Tracking**: Linear progress bars during downloads/extraction
- **Action Buttons**: Download/Delete buttons with appropriate icons

## State Management

The system uses Riverpod for state management:

- **`TtsDownloadManager`**: AsyncNotifierProvider managing download operations
- **`TtsDownloadState`**: UI state class tracking per-engine status and progress
- **Stream Subscriptions**: Real-time progress updates from download managers

## Engine-Specific Organization

### Kokoro
- Single quantized core model (Q8/INT8)
- Voice styles binary file
- eSpeak-NG phoneme data
- All voices share the same core components

### Piper
- Per-voice model files (ONNX + JSON config)
- Lightweight models (~30MB each)
- Direct download from HuggingFace

### Supertonic
- Multiple ONNX components:
  - Autoencoder
  - Text encoder
  - Duration predictor
- Downloaded as tar.gz archive from GitHub releases

## Download Sources

- **GitHub Releases**: Kokoro models, Supertonic core archives
- **HuggingFace**: Piper voice models and configurations
- **Fallback System**: ResilientDownloader provides retry logic and resume capability

## Reliability Features

- **Atomic Operations**: .tmp pattern prevents corruption from interrupted downloads
- **Checksum Verification**: SHA256 verification for downloaded files
- **Resume Support**: Partial downloads can be resumed
- **Rollback Capability**: Failed installations are cleaned up automatically
- **Manifest System**: .manifest files track successful installations

## Integration Points

- **TTS Providers**: Downloads integrate with TTS engine adapters
- **Voice Selection**: UI prevents selection of voices without downloaded models
- **Background Downloads**: Downloads can run in background with progress tracking
- **Cache Management**: Automatic cleanup and space management

This organization ensures reliable, resumable downloads while providing a clean user experience for managing voice engine installations.