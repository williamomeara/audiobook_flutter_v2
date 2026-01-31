# Architecture Documentation

> 🎯 **This folder contains core state machines and system design for LLM context.**
> 
> Point LLMs here for rapid and precise understanding of the project architecture.

## Contents

| File | Description |
|------|-------------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | High-level system architecture overview |
| [playback_screen_state_machine.md](playback_screen_state_machine.md) | Playback UI states and transitions |
| [sleep_timer_state_machine.md](sleep_timer_state_machine.md) | Sleep timer with play-aware countdown |
| [tts_synthesis_state_machine.md](tts_synthesis_state_machine.md) | TTS synthesis pipeline states |
| [audio_synthesis_pipeline_state_machine.md](audio_synthesis_pipeline_state_machine.md) | Audio synthesis orchestration |
| [smart-synthesis/](smart-synthesis/) | Smart prefetch system and cold-start handling |

---

## Data Persistence (SQLite)

All app data is stored in SQLite (`eist_audiobook.db`) using WAL mode.

### Core Tables

| Table | Purpose |
|-------|---------|
| `books` | Book metadata (title, author, file_path, cover, voice_id) |
| `chapters` | Chapter metadata (book_id, title, order, content) |
| `segments` | Text segments for TTS (chapter_id, text, order) |
| `reading_progress` | Per-book progress tracking |
| `chapter_positions` | Per-chapter resume positions (is_primary marks active position) |
| `cache_entries` | Audio cache with compression_state (wav/compressing/m4a/failed) |
| `settings` | Key-value settings (JSON-encoded) |

---

## Quick Reference

### Playback States
```
IDLE → LOADING → BUFFERING → PLAYING ⇄ PAUSED → ERROR
```

### Preview Mode
- **Active Mode**: Full controls, auto-scroll, position saves
- **Preview Mode**: Mini-player, tap segment to switch

### Sleep Timer States
```
OFF → RUNNING ⇄ PAUSED (when audio paused) → EXPIRED → OFF
```

### TTS Synthesis States
```
Ready → Synthesizing → Complete/Error
```

### Cache Compression States
```
WAV → COMPRESSING → M4A (or FAILED)
```

---

## Related Documentation

- [../modules/](../modules/) - Package-level documentation
- [../archive/architecture/](../archive/architecture/) - Historical audits and improvement plans
