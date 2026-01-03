# Architecture

This repository contains a Flutter audiobook reader with a modular, multi-engine, on-device TTS system.

## High-level goals

- **Local-first**: books are imported from local files (EPUB/PDF) and processed on-device.
- **Reliable large downloads**: voice model downloads are atomic and resumable.
- **Pluggable TTS engines**: Kokoro, Piper, Supertonic (plus device TTS fallback).
- **Background playback**: audio playback via `just_audio` + `audio_service`.

## Project layout

- `lib/` — Flutter app (UI + providers + app services)
- `packages/core_domain/` — shared domain models + text utilities
- `packages/downloads/` — download + install primitives + voice manifest
- `packages/tts_engines/` — engine interfaces, routing, cache, and adapters
- `packages/playback/` — playback orchestration abstractions
- `packages/platform_android_tts/` — Android native plugin (Pigeon API + Kotlin services)

## Architecture diagram (end-to-end)

```mermaid
flowchart TB
  subgraph UI[Flutter UI]
    Library[LibraryScreen]
    BookDetails[BookDetailsScreen]
    Playback[PlaybackScreen]
    Settings[SettingsScreen]
    VoiceMgr[VoiceDownloadManager widget]
  end

  subgraph App[App Layer (lib/app)]
    Providers[Riverpod providers]
    SettingsCtl[SettingsController]
    TtsDlMgr[TtsDownloadManager]
    RoutingProv[ttsRoutingEngineProvider]
    Paths[AppPaths]
  end

  subgraph Infra[Infra (lib/infra)]
    Epub[EpubParser]
    Pdf[PDF parsing (pdfrx)]
  end

  subgraph Domain[Domain (packages/core_domain)]
    Models[Book/Chapter/Segment/Voice]
    TextUtils[TextSegmenter/TextNormalizer]
    CacheKey[CacheKeyGenerator]
  end

  subgraph Downloads[Downloads (packages/downloads)]
    Atomic[AtomicAssetManager]
    Manifest[voices_manifest.json + parsers]
  end

  subgraph TTS[TTS (packages/tts_engines)]
    Router[RoutingEngine]
    Cache[AudioCache]
    Kokoro[KokoroAdapter]
    Piper[PiperAdapter]
    Supertonic[SupertonicAdapter]
  end

  subgraph Native[Native (packages/platform_android_tts)]
    Pigeon[Pigeon API]
    Kotlin[Kotlin services per engine]
  end

  subgraph PlaybackPkg[Playback (packages/playback)]
    Just[just_audio]
    Service[audio_service]
  end

  Library --> Providers
  BookDetails --> Providers
  Playback --> Providers
  Settings --> VoiceMgr --> TtsDlMgr

  Providers --> Paths
  Providers --> SettingsCtl
  Providers --> Epub
  Providers --> Pdf

  TtsDlMgr --> Atomic
  Atomic --> Manifest

  RoutingProv --> Router
  Router --> Cache
  Router --> Kokoro
  Router --> Piper
  Router --> Supertonic

  Kokoro --> Pigeon --> Kotlin
  Piper --> Pigeon --> Kotlin
  Supertonic --> Pigeon --> Kotlin

  Playback --> PlaybackPkg
  PlaybackPkg --> Just
  PlaybackPkg --> Service

  Epub --> Models
  Pdf --> Models
  Router --> CacheKey
  Router --> TextUtils
```

## Key flows

### 1) Import book (EPUB)

1. UI picks a file (via `file_picker`).
2. `EpubParser` parses and normalizes chapters, extracting a cover image when possible.
3. Results are mapped into domain models (`Book`, `Chapter`).

### 2) Download voice models

1. User initiates downloads from Settings → `VoiceDownloadManager`.
2. `TtsDownloadManager` delegates to `AtomicAssetManager`.
3. `AtomicAssetManager` downloads to a temp file (`.tmp`), optionally extracts archives, then atomically renames into the final install directory.

### 3) Synthesize + play

1. Playback/UI requests audio for text with a selected voice.
2. `RoutingEngine` computes a stable cache key and checks `AudioCache`.
3. On cache miss, the request is routed to the correct engine adapter.
4. Adapter calls Android native via Pigeon; output audio is written to the cache.
5. Playback uses `just_audio`/`audio_service` to play cached audio.

## Detailed docs

- `docs/modules/APP_LAYER.md`
- `docs/modules/UI.md`
- `docs/modules/CORE_DOMAIN.md`
- `docs/modules/DOWNLOADS.md`
- `docs/modules/TTS_ENGINES.md`
- `docs/modules/PLATFORM_ANDROID_TTS.md`
- `docs/modules/PLAYBACK.md`
