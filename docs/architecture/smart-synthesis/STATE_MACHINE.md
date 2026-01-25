# Smart Synthesis State Machine

## High-Level State Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SMART SYNTHESIS STATE MACHINE                     │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌─────────────┐
                              │    IDLE     │
                              │  (Initial)  │
                              └──────┬──────┘
                                     │
                           openBook()/openChapter()
                                     │
                                     ▼
                        ┌────────────────────────┐
                        │   PREPARING_COLD_START │
                        │   (Sync first segment) │
                        └───────────┬────────────┘
                                    │
                           firstSegmentReady()
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
                    ▼               ▼               ▼
           ┌────────────┐  ┌────────────┐  ┌────────────┐
           │CONSERVATIVE│  │  ADAPTIVE  │  │ AGGRESSIVE │
           │   MODE     │  │   MODE     │  │   MODE     │
           └─────┬──────┘  └─────┬──────┘  └─────┬──────┘
                 │               │               │
                 │    ◄──────────┴───────────►   │
                 │      (Strategy switching)     │
                 │               │               │
                 └───────────────┼───────────────┘
                                 │
                                 ▼
                        ┌────────────────┐
                        │    PLAYING     │
                        │  (Prefetching) │◄─────────────────────┐
                        └───────┬────────┘                      │
                                │                               │
            ┌───────────────────┼───────────────────┐           │
            │                   │                   │           │
   bufferLow()          segmentComplete()     bufferFull()      │
            │                   │                   │           │
            ▼                   ▼                   ▼           │
   ┌────────────────┐  ┌────────────────┐  ┌────────────┐       │
   │  PREFETCHING   │  │   ADVANCING    │  │  BUFFERED  │───────┘
   │ (Synthesizing) │  │  (Next seg.)   │  │ (Waiting)  │  bufferLow()
   └────────┬───────┘  └───────┬────────┘  └────────────┘
            │                  │
            └─────────┬────────┘
                      │
            synthesisComplete()
                      │
                      ▼
             Back to PLAYING
                      │
                      │
       ┌──────────────┴──────────────┐
       │                             │
  chapterEnd()                  cancel()/
       │                       bookChange()
       ▼                             │
┌─────────────────┐                  ▼
│ CHAPTER_COMPLETE│           ┌────────────┐
│  (Auto-advance?)│           │ CANCELLING │
└────────┬────────┘           └──────┬─────┘
         │                           │
    autoAdvance?                     │
    ┌────┴────┐                      │
    │         │                      ▼
    ▼         ▼               ┌────────────┐
  IDLE   nextChapter()        │    IDLE    │
              │               └────────────┘
              ▼
     PREPARING_COLD_START
```

## Strategy Selection State Machine

```
                    ┌───────────────────────────────────────┐
                    │         STRATEGY SELECTION            │
                    └───────────────────────────────────────┘

                              ┌─────────────┐
                              │   CHECK     │
                              │   STATE     │
                              └──────┬──────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
            isLowPowerMode?    isCharging?      (default)
                    │                │                │
                    ▼                ▼                ▼
           ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
           │  CONSERVATIVE  │ │   AGGRESSIVE   │ │    ADAPTIVE    │
           │                │ │                │ │                │
           │ • Min prefetch │ │ • Max prefetch │ │ • RTF-based    │
           │ • Save battery │ │ • No limits    │ │ • Balanced     │
           │ • 1-2 segments │ │ • 5+ segments  │ │ • 2-4 segments │
           └────────────────┘ └────────────────┘ └────────────────┘
                    │                │                │
                    └────────────────┴────────────────┘
                                     │
                              Re-evaluate on:
                              • Battery change
                              • Power mode change
                              • Performance metrics
```

## BufferScheduler State Machine

```
                    ┌───────────────────────────────────────┐
                    │          BUFFER SCHEDULER             │
                    └───────────────────────────────────────┘

                              ┌─────────────┐
                              │   IDLE      │
                              │             │
                              └──────┬──────┘
                                     │
                              startPrefetch()
                                     │
                                     ▼
                        ┌────────────────────────┐
                        │  CHECK_BUFFER_LEVEL    │
                        └───────────┬────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
        buffer < low          low ≤ buffer         buffer ≥ target
        watermark              < target                   │
              │                     │                     │
              ▼                     ▼                     ▼
     ┌────────────────┐   ┌────────────────┐    ┌────────────────┐
     │  URGENT_FETCH  │   │ NORMAL_FETCH   │    │   BUFFERED     │
     │                │   │                │    │   (Wait)       │
     │ • Immediate    │   │ • Sequential   │    │                │
     │ • Next segment │   │ • To target    │    │ • Monitor      │
     │ • Block if     │   │ • Background   │    │ • Re-check     │
     │   needed       │   │                │    │   periodically │
     └───────┬────────┘   └───────┬────────┘    └───────┬────────┘
             │                    │                     │
             └────────────────────┴─────────────────────┘
                                  │
                           synthesisComplete()
                                  │
                                  ▼
                          ┌────────────────┐
                          │ UPDATE_INDEX   │
                          │ _prefetchedIdx │
                          └───────┬────────┘
                                  │
                           Loop back to
                        CHECK_BUFFER_LEVEL
```

## Cancellation Flow

```
                    ┌───────────────────────────────────────┐
                    │         CANCELLATION FLOW             │
                    └───────────────────────────────────────┘

              [Any State]
                   │
                   │  bookChange() / chapterChange() / voiceChange()
                   │
                   ▼
          ┌────────────────┐
          │ CANCEL_PENDING │
          │                │
          │ • Set cancel   │
          │   token        │
          │ • Abort active │
          │   synthesis    │
          │ • Clear buffer │
          └───────┬────────┘
                  │
                  ▼
          ┌────────────────┐
          │  AWAIT_ABORT   │
          │                │
          │ • Wait for     │
          │   active ops   │
          │ • Timeout:     │
          │   500ms        │
          └───────┬────────┘
                  │
                  ▼
          ┌────────────────┐
          │   CLEANUP      │
          │                │
          │ • Reset state  │
          │ • Clear tokens │
          │ • Ready for    │
          │   new content  │
          └───────┬────────┘
                  │
                  ▼
               [IDLE]
```

## Parallel Synthesis Orchestration

```
                    ┌───────────────────────────────────────┐
                    │     PARALLEL SYNTHESIS STATES         │
                    └───────────────────────────────────────┘

                              ┌─────────────┐
                              │ SEQUENTIAL  │
                              │  (Default)  │
                              └──────┬──────┘
                                     │
                        parallelEnabled && fastDevice?
                                     │
                    ┌────────────────┴────────────────┐
                    │                                 │
                    No                               Yes
                    │                                 │
                    ▼                                 ▼
           ┌────────────────┐              ┌────────────────┐
           │  SEQUENTIAL    │              │   PARALLEL     │
           │   PREFETCH     │              │   PREFETCH     │
           │                │              │                │
           │ for i in       │              │ • Semaphore(3) │
           │   range:       │              │ • Concurrent   │
           │   synthesize(i)│              │   segments     │
           │   await        │              │ • Incremental  │
           └────────────────┘              │   index update │
                                           └───────┬────────┘
                                                   │
                                      ┌────────────┼────────────┐
                                      │            │            │
                                    Slot 1      Slot 2      Slot 3
                                      │            │            │
                                      ▼            ▼            ▼
                                   ┌─────┐     ┌─────┐     ┌─────┐
                                   │Seg N│     │Seg  │     │Seg  │
                                   │     │     │N+1  │     │N+2  │
                                   └──┬──┘     └──┬──┘     └──┬──┘
                                      │           │           │
                                      └───────────┴───────────┘
                                                  │
                                           allComplete()
                                                  │
                                                  ▼
                                         Update prefetchedIdx
```

## State Transitions Summary

| Current State | Event | Next State | Action |
|---------------|-------|------------|--------|
| IDLE | openBook | PREPARING_COLD_START | Begin sync synthesis |
| PREPARING_COLD_START | firstSegmentReady | PLAYING | Start audio, async prefetch |
| PLAYING | bufferLow | PREFETCHING | Trigger prefetch |
| PLAYING | segmentComplete | ADVANCING | Move to next segment |
| PLAYING | bufferFull | BUFFERED | Pause prefetch |
| PREFETCHING | synthesisComplete | PLAYING | Update buffer index |
| BUFFERED | bufferLow | PREFETCHING | Resume prefetch |
| ANY | cancel | CANCELLING | Abort all operations |
| CANCELLING | complete | IDLE | Ready for new content |
| PLAYING | chapterEnd | CHAPTER_COMPLETE | Check auto-advance |
| CHAPTER_COMPLETE | autoAdvance | PREPARING_COLD_START | Start next chapter |

## Implementation Notes

### Thread Safety
- All state transitions protected by `_AsyncLock`
- Buffer updates are atomic
- Cancellation tokens are checked before each operation

### Performance Considerations
- Cold-start blocks UI briefly (~100-500ms)
- Parallel synthesis limited to 3 concurrent to avoid OOM
- Strategy re-evaluation happens on battery/power events only

### Error Recovery
- Synthesis timeout: 30 seconds per segment
- Failed synthesis: Retry once, then skip segment
- Network errors (if applicable): Exponential backoff
