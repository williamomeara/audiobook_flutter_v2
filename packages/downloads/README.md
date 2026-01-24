# downloads

Asset download and management system for the audiobook_flutter application.

## Overview

This package handles downloading and managing TTS voice models and other assets:

- **AtomicAssetManager**: Corruption-safe downloads with .tmp pattern and atomic moves
- **ResilientDownloader**: Retry logic, resume support, and SHA256 verification
- **Voice Manifests**: JSON-driven voice model specifications

## Key Features

- Atomic downloads prevent corruption from interrupted transfers
- SHA256 verification ensures file integrity
- Resume support for large model downloads
- Progress tracking via streams

## Usage

```dart
import 'package:downloads/downloads.dart';

final manager = AtomicAssetManager(
  targetDir: voiceDir,
);

await manager.downloadAndExtract(
  url: modelUrl,
  sha256: expectedHash,
  onProgress: (progress) => print('$progress%'),
);
```

## Part of audiobook_flutter_v2

This is an internal package for the audiobook_flutter_v2 project and is not published to pub.dev.
