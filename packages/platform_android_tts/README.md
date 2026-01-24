# platform_android_tts

Android-specific TTS implementations for the audiobook_flutter application.

## Overview

This Flutter plugin provides native Android TTS functionality using:

- **ONNX Runtime**: Neural network inference for Kokoro and Piper models
- **JNI Integration**: Efficient Dart-to-Kotlin communication via Pigeon
- **Model Management**: Loading and caching of voice models

## Key Features

- Native ONNX model inference for high-performance TTS
- GPU acceleration support where available
- Memory-efficient model loading
- Streaming audio output

## Platform Support

| Platform | Support |
|----------|---------|
| Android  | ✅       |
| iOS      | ❌       |

## Part of audiobook_flutter_v2

This is an internal package for the audiobook_flutter_v2 project and is not published to pub.dev.

