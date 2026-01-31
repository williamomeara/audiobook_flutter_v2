# Architecture Improvements

This folder contains audits, analysis documents, and improvement proposals for the audiobook app architecture.

## Documents

| Document | Description | Status |
|----------|-------------|--------|
| [improvement_opportunities.md](improvement_opportunities.md) | 66 potential improvements across playback and synthesis subsystems | Partially implemented |
| [tts_state_machine_audit.md](tts_state_machine_audit.md) | Review of TTS state machine implementations (Dart + Kotlin) | Completed |
| [kokoro_performance_optimization.md](kokoro_performance_optimization.md) | Kokoro TTS performance analysis and optimization strategies | Reference |

## Structure

The improvements are categorized by:

- **Race Conditions & Threading** - Concurrency issues in buffer scheduler, prefetch
- **Error Handling** - Synthesis failure recovery, retry logic
- **State Machine Edge Cases** - Voice changes, memory pressure, rate changes
- **User Experience** - Loading states, error messages, progress indicators
- **Resource Management** - Memory monitoring, cache management
- **Code Quality** - Cleanup, documentation, consistency
- **Configuration Flexibility** - Runtime configuration, auto-tuning (see `docs/features/configuration-flexibility/`)
- **Testing Gaps** - Unit test coverage, integration tests

## Related Documents

- [../audio_synthesis_pipeline_state_machine.md](../audio_synthesis_pipeline_state_machine.md) - Pipeline state machine
- [../playback_screen_state_machine.md](../playback_screen_state_machine.md) - Playback UI state machine
- [../sleep_timer_state_machine.md](../sleep_timer_state_machine.md) - Sleep timer state machine
- [../tts_synthesis_state_machine.md](../tts_synthesis_state_machine.md) - TTS synthesis state machine
