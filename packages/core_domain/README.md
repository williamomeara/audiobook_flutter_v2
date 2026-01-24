# core_domain

Shared domain models and types for the audiobook_flutter application.

## Overview

This package provides the core domain layer containing:

- **Book**: Represents an audiobook with chapters, metadata, and cover art
- **Chapter**: Individual chapter with content and reading position
- **Segment**: Text segment for TTS synthesis
- **Voice**: TTS voice configuration
- **TTS Types**: Engine types (Kokoro, Piper, Supertonic) and related enums

## Usage

```dart
import 'package:core_domain/core_domain.dart';

// Create a book
final book = Book(
  id: 'book-123',
  title: 'My Audiobook',
  author: 'Author Name',
  chapters: [chapter1, chapter2],
);

// Work with voices
final voice = Voice(
  id: 'kokoro-af',
  name: 'American Female',
  engine: TtsEngine.kokoro,
);
```

## Part of audiobook_flutter_v2

This is an internal package for the audiobook_flutter_v2 project and is not published to pub.dev.
