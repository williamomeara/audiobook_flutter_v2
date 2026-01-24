# tts_engines

TTS engine abstractions and routing for the audiobook_flutter application.

## Overview

This package provides a unified interface for multiple TTS engines:

- **RoutingEngine**: Intelligent engine selection and synthesis routing
- **TtsAdapter**: Abstract interface for TTS engines
- **AudioCache**: Caches synthesized audio segments
- **Voice Management**: Voice listing, selection, and validation

## Supported Engines

- **Kokoro**: High-quality neural TTS (recommended for quality)
- **Piper**: Fast ONNX-based TTS (good balance of speed/quality)
- **Supertonic**: Advanced TTS option

## Usage

```dart
import 'package:tts_engines/tts_engines.dart';

final engine = RoutingEngine(
  kokoroAdapter: kokoroAdapter,
  piperAdapter: piperAdapter,
);

final audioPath = await engine.synthesize(
  Segment(text: 'Hello, world!', index: 0),
  voice: selectedVoice,
);
```

## Part of audiobook_flutter_v2

This is an internal package for the audiobook_flutter_v2 project and is not published to pub.dev.
