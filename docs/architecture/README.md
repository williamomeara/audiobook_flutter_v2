# Architecture Documentation

> 🎯 **This folder is the Single Source of Truth for all architecture documentation.**

This folder contains detailed architecture documentation including system design, state machines, audits, and improvement plans.

## Data Persistence (SQLite)

All app data is stored in SQLite (`eist_audiobook.db`) using WAL mode for performance. The database schema is version 6.

### Core Tables

| Table | Purpose | DAO |
|-------|---------|-----|
| `books` | Book metadata (id, title, author, file_path, cover, voice_id, timestamps) | `BookDao` |
| `chapters` | Chapter metadata (id, book_id, title, order, content) | `ChapterDao` |
| `segments` | Text segments for TTS (id, chapter_id, text, order) | `SegmentDao` |
| `reading_progress` | Per-book progress tracking | `ProgressDao` |
| `chapter_positions` | Per-chapter resume positions with primary position tracking | `ChapterPositionDao` |
| `cache_entries` | Audio cache metadata with compression state tracking | `CacheDao` |
| `settings` | Key-value settings (JSON-encoded values) | `SettingsDao` |
| `completed_chapters` | Completion timestamps per chapter | `CompletedChaptersDao` |
| `downloaded_voices` | Installed voice model metadata | `DownloadedVoicesDao` |
| `model_metrics` | Engine performance metrics for auto-tuning | `ModelMetricsDao` |

### Key Persistence Patterns

- **Single Source of Truth**: SQLite is the authoritative store for all structured data
- **Compression State Tracking**: Cache entries track `compression_state` (wav, compressing, m4a, failed) in DB
- **Primary Position**: `chapter_positions.is_primary = true` marks the "Continue Listening" position
- **SharedPreferences**: Only used for `dark_mode` (instant startup theme loading)

---

## State Machine Documentation

Comprehensive documentation of the state machines used in the app:

| Document | Description |
|----------|-------------|
| [playback_screen_state_machine.md](playback_screen_state_machine.md) | Playback UI states, transitions, and media control integration |
| [sleep_timer_state_machine.md](sleep_timer_state_machine.md) | Sleep timer states with play-aware countdown and reset behavior |
| [tts_synthesis_state_machine.md](tts_synthesis_state_machine.md) | TTS synthesis pipeline states |
| [audio_synthesis_pipeline_state_machine.md](audio_synthesis_pipeline_state_machine.md) | Audio synthesis pipeline orchestration |

## Navigation & Position Tracking

| Document | Description |
|----------|-------------|
| [../features/completed/last-listened-location/NAVIGATION_STATE_MACHINE.md](../features/completed/last-listened-location/NAVIGATION_STATE_MACHINE.md) | Preview mode, mini-player, and position tracking |

## System Design Documentation

| Document | Description |
|----------|-------------|
| [smart-synthesis/](smart-synthesis/) | Smart synthesis prefetch system (cold-start, strategies) |
| [edge_case_handlers.md](edge_case_handlers.md) | Rate/voice/memory change handlers with rollback |

## Improvements & Audits

Analysis documents, audits, and optimization plans are in the [improvements/](improvements/) subfolder:

| Document | Description |
|----------|-------------|
| [improvements/improvement_opportunities.md](improvements/improvement_opportunities.md) | 66 identified improvements across playback and synthesis |
| [improvements/tts_state_machine_audit.md](improvements/tts_state_machine_audit.md) | TTS state machine audit (Dart + Kotlin layers) |
| [improvements/kokoro_performance_optimization.md](improvements/kokoro_performance_optimization.md) | Kokoro TTS performance analysis |

---

## Quick Reference

### Playback Screen States
- IDLE → LOADING → BUFFERING → PLAYING ⇄ PAUSED → ERROR

### Preview Mode (Browsing other chapters while audio plays)
- Active Mode: Full controls, auto-scroll, position saves
- Preview Mode: Mini-player, tap segment to switch, no auto-save

### Sleep Timer States
- OFF → RUNNING ⇄ PAUSED (when audio paused) → EXPIRED → OFF
- User actions reset timer to full duration (except auto-chapter-advance)

### TTS Synthesis States
- Ready → Synthesizing → Complete/Error

### Cache Compression States
- WAV → COMPRESSING → M4A (or FAILED)
- Tracked in `cache_entries.compression_state` column (not file extension)

### Edge Case Handlers
- **RateChangeHandler** - Debounces rate slider, cancels prefetch on significant change
- **VoiceChangeHandler** - Cancels old prefetch, resynthesizes current segment
- **MemoryPressureHandler** - Reduces prefetch and pauses synthesis under pressure
- **AutoTuneRollback** - Snapshots config, rolls back if performance degrades

---

## Related Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) - High-level architecture overview
- [../features/completed/sqlite-migration/PLAN.md](../features/completed/sqlite-migration/PLAN.md) - SQLite migration plan (historical reference)
- [../features/completed/last-listened-location/NAVIGATION_STATE_MACHINE.md](../features/completed/last-listened-location/NAVIGATION_STATE_MACHINE.md) - Navigation state machine
- [../modules/](../modules/) - Package-level documentation
