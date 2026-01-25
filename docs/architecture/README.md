# Architecture Documentation

This folder contains detailed architecture documentation including state machines, audits, and improvement plans.

## State Machine Documentation

Comprehensive documentation of the state machines used in the app:

| Document | Description |
|----------|-------------|
| [playback_screen_state_machine.md](playback_screen_state_machine.md) | Playback UI states, transitions, and media control integration |
| [sleep_timer_state_machine.md](sleep_timer_state_machine.md) | Sleep timer states with play-aware countdown and reset behavior |
| [tts_synthesis_state_machine.md](tts_synthesis_state_machine.md) | TTS synthesis pipeline states |
| [audio_synthesis_pipeline_state_machine.md](audio_synthesis_pipeline_state_machine.md) | Audio synthesis pipeline orchestration |

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

## Quick Reference

### Playback Screen States
- IDLE → LOADING → BUFFERING → PLAYING ⇄ PAUSED → ERROR

### Sleep Timer States
- OFF → RUNNING ⇄ PAUSED (when audio paused) → EXPIRED → OFF
- User actions reset timer to full duration (except auto-chapter-advance)

### TTS Synthesis States
- Ready → Synthesizing → Complete/Error

### Edge Case Handlers
- **RateChangeHandler** - Debounces rate slider, cancels prefetch on significant change
- **VoiceChangeHandler** - Cancels old prefetch, resynthesizes current segment
- **MemoryPressureHandler** - Reduces prefetch and pauses synthesis under pressure
- **AutoTuneRollback** - Snapshots config, rolls back if performance degrades

## Related Documentation

- [../ARCHITECTURE.md](../ARCHITECTURE.md) - High-level architecture overview
- [../features/configuration-flexibility/](../features/configuration-flexibility/) - Configuration system implementation
- [../modules/](../modules/) - Package-level documentation
