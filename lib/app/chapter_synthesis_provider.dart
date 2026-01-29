import 'dart:async';
import 'dart:developer' as developer;

import 'package:core_domain/core_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playback/playback.dart';

import 'playback_providers.dart';

/// State for a chapter being synthesized.
class ChapterSynthesisState {
  const ChapterSynthesisState({
    required this.bookId,
    required this.chapterIndex,
    required this.status,
    this.progress = 0.0,
    this.currentSegment = 0,
    this.totalSegments = 0,
    this.error,
    this.estimatedTimeRemaining,
  });

  final String bookId;
  final int chapterIndex;
  final ChapterSynthesisStatus status;
  final double progress;
  final int currentSegment;
  final int totalSegments;
  final String? error;
  final Duration? estimatedTimeRemaining;

  ChapterSynthesisState copyWith({
    ChapterSynthesisStatus? status,
    double? progress,
    int? currentSegment,
    int? totalSegments,
    String? error,
    Duration? estimatedTimeRemaining,
  }) {
    return ChapterSynthesisState(
      bookId: bookId,
      chapterIndex: chapterIndex,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      currentSegment: currentSegment ?? this.currentSegment,
      totalSegments: totalSegments ?? this.totalSegments,
      error: error ?? this.error,
      estimatedTimeRemaining: estimatedTimeRemaining ?? this.estimatedTimeRemaining,
    );
  }

  /// Display text for UI.
  String get displayText {
    switch (status) {
      case ChapterSynthesisStatus.idle:
        return '';
      case ChapterSynthesisStatus.estimating:
        return 'Calculating...';
      case ChapterSynthesisStatus.synthesizing:
        return '$currentSegment / $totalSegments';
      case ChapterSynthesisStatus.complete:
        return 'Ready to play';
      case ChapterSynthesisStatus.cancelled:
        return 'Cancelled';
      case ChapterSynthesisStatus.error:
        return error ?? 'Failed';
    }
  }

  /// Progress percentage (0-100).
  int get progressPercent => (progress * 100).round();
}

/// Status of chapter synthesis.
enum ChapterSynthesisStatus {
  idle,
  estimating,
  synthesizing,
  complete,
  cancelled,
  error,
}

/// Estimate for chapter synthesis.
class ChapterSynthesisEstimate {
  const ChapterSynthesisEstimate({
    required this.totalSegments,
    required this.estimatedDuration,
    required this.estimatedStorageMb,
    required this.voiceName,
    required this.rtf,
  });

  final int totalSegments;
  final Duration estimatedDuration;
  final double estimatedStorageMb;
  final String voiceName;
  final double rtf;

  /// User-friendly time display.
  String get timeDisplay {
    final minutes = estimatedDuration.inMinutes;
    if (minutes < 1) return 'Less than 1 minute';
    if (minutes == 1) return '~1 minute';
    return '~$minutes minutes';
  }

  /// User-friendly storage display.
  String get storageDisplay {
    if (estimatedStorageMb < 1) return '<1 MB';
    return '~${estimatedStorageMb.toStringAsFixed(1)} MB';
  }
}

/// Provider key for chapter synthesis state.
typedef ChapterKey = ({String bookId, int chapterIndex});

/// Combined state for all chapter synthesis jobs.
class AllChapterSynthesisState {
  const AllChapterSynthesisState({
    this.jobs = const {},
    this.lastKnownRtf = 2.0,
  });

  final Map<ChapterKey, ChapterSynthesisState> jobs;
  final double lastKnownRtf;

  AllChapterSynthesisState copyWith({
    Map<ChapterKey, ChapterSynthesisState>? jobs,
    double? lastKnownRtf,
  }) {
    return AllChapterSynthesisState(
      jobs: jobs ?? this.jobs,
      lastKnownRtf: lastKnownRtf ?? this.lastKnownRtf,
    );
  }

  /// Get state for a specific chapter.
  ChapterSynthesisState? getState(String bookId, int chapterIndex) {
    return jobs[(bookId: bookId, chapterIndex: chapterIndex)];
  }
}

/// Provider for managing chapter synthesis.
final chapterSynthesisProvider = NotifierProvider<ChapterSynthesisNotifier, 
    AllChapterSynthesisState>(() => ChapterSynthesisNotifier());

/// Provider for getting synthesis state for a specific chapter.
final chapterSynthesisStateProvider = Provider.family<ChapterSynthesisState?, ChapterKey>((ref, key) {
  final allState = ref.watch(chapterSynthesisProvider);
  return allState.jobs[key];
});

/// Notifier for chapter synthesis state.
class ChapterSynthesisNotifier extends Notifier<AllChapterSynthesisState> {
  OptionalPreSynthesis? _preSynthesis;

  @override
  AllChapterSynthesisState build() => const AllChapterSynthesisState();

  /// Start synthesizing a chapter.
  Future<void> startSynthesis({
    required String bookId,
    required int chapterIndex,
    required List<AudioTrack> tracks,
    required String voiceId,
  }) async {
    final key = (bookId: bookId, chapterIndex: chapterIndex);
    
    // Check if already running
    if (state.jobs[key]?.status == ChapterSynthesisStatus.synthesizing) {
      return;
    }

    // Get the playback controller notifier
    final notifier = ref.read(playbackControllerProvider.notifier);
    final coordinator = notifier.controller?.synthesisCoordinator;
    if (coordinator == null) return;

    developer.log('[ChapterSynth] Starting synthesis for chapter $chapterIndex, ${tracks.length} tracks');

    // Create pre-synthesis instance
    _preSynthesis = OptionalPreSynthesis(
      segmentSynthesizer: (index) async {
        // First check if already cached (fast path)
        final track = tracks[index];
        final isReady = await coordinator.isSegmentReady(
          voiceId: voiceId,
          text: track.text,
          playbackRate: 1.0,
        );
        
        if (isReady) {
          // Already cached, no need to wait
          developer.log('[ChapterSynth] seg $index: already cached');
          return;
        }
        
        developer.log('[ChapterSynth] seg $index: queueing for synthesis');
        
        // Start listening BEFORE queueing to avoid race condition
        final completer = Completer<void>();
        late final StreamSubscription<SegmentReadyEvent> sub;
        sub = coordinator.onSegmentReady.listen((event) {
          if (event.segmentIndex == index) {
            developer.log('[ChapterSynth] seg $index: ready event received');
            completer.complete();
            sub.cancel();
          }
        });
        
        // Queue the segment for synthesis
        await coordinator.queueImmediate(
          track: track,
          voiceId: voiceId,
          playbackRate: 1.0, // Always synth at 1.0x
          segmentIndex: index,
          bookId: bookId,
          chapterIndex: chapterIndex,
        );
        
        // Wait for completion (with timeout)
        try {
          await completer.future.timeout(
            const Duration(minutes: 5),
            onTimeout: () {
              developer.log('[ChapterSynth] seg $index: TIMEOUT');
              sub.cancel();
              throw TimeoutException('Segment synthesis timed out');
            },
          );
        } finally {
          sub.cancel();
        }
        developer.log('[ChapterSynth] seg $index: complete');
      },
      maxConcurrency: 1, // Low priority, sequential
    );

    // Update state to synthesizing
    final newJobs = Map<ChapterKey, ChapterSynthesisState>.from(state.jobs);
    newJobs[key] = ChapterSynthesisState(
      bookId: bookId,
      chapterIndex: chapterIndex,
      status: ChapterSynthesisStatus.synthesizing,
      totalSegments: tracks.length,
    );
    state = state.copyWith(jobs: newJobs);

    // Start synthesis
    final result = await _preSynthesis!.preSynthesizeChapter(
      bookId: bookId,
      chapterIndex: chapterIndex,
      totalSegments: tracks.length,
      onProgress: (progress) {
        _updateProgress(key, progress);
      },
    );

    // Update final state
    final finalStatus = switch (result) {
      PreSynthesisResult.complete => ChapterSynthesisStatus.complete,
      PreSynthesisResult.cancelled => ChapterSynthesisStatus.cancelled,
      PreSynthesisResult.error => ChapterSynthesisStatus.error,
      PreSynthesisResult.alreadyRunning => ChapterSynthesisStatus.synthesizing,
    };

    final finalJobs = Map<ChapterKey, ChapterSynthesisState>.from(state.jobs);
    final currentState = finalJobs[key];
    if (currentState != null) {
      finalJobs[key] = currentState.copyWith(
        status: finalStatus,
        progress: result == PreSynthesisResult.complete ? 1.0 : currentState.progress,
      );
    }
    state = state.copyWith(jobs: finalJobs);
  }

  /// Cancel synthesis for a chapter.
  void cancelSynthesis(String bookId, int chapterIndex) {
    _preSynthesis?.cancel(bookId, chapterIndex);
    final key = (bookId: bookId, chapterIndex: chapterIndex);
    if (state.jobs.containsKey(key)) {
      final newJobs = Map<ChapterKey, ChapterSynthesisState>.from(state.jobs);
      newJobs[key] = state.jobs[key]!.copyWith(status: ChapterSynthesisStatus.cancelled);
      state = state.copyWith(jobs: newJobs);
    }
  }

  /// Get estimate for chapter synthesis.
  ChapterSynthesisEstimate? getEstimate({
    required List<AudioTrack> tracks,
    required String voiceId,
  }) {
    if (tracks.isEmpty) return null;

    // Calculate average segment duration (estimate)
    const avgSegmentDuration = 15.0; // ~15 seconds per segment average
    final totalAudioSeconds = tracks.length * avgSegmentDuration;
    
    // Use last known RTF
    final voiceName = voiceId.split('_').skip(1).join(' ');
    
    // Estimate synthesis time
    final synthesisSeconds = totalAudioSeconds * state.lastKnownRtf;
    
    // Estimate storage (~48KB per second of audio)
    final storageMb = (totalAudioSeconds * 48 * 1024) / (1024 * 1024);

    return ChapterSynthesisEstimate(
      totalSegments: tracks.length,
      estimatedDuration: Duration(seconds: synthesisSeconds.round()),
      estimatedStorageMb: storageMb,
      voiceName: voiceName,
      rtf: state.lastKnownRtf,
    );
  }

  /// Update RTF from observed synthesis.
  void updateRtf(double rtf) {
    state = state.copyWith(lastKnownRtf: rtf);
  }

  /// Check if chapter is ready (all segments cached).
  Future<bool> isChapterReady({
    required String bookId,
    required int chapterIndex,
    required List<AudioTrack> tracks,
    required String voiceId,
  }) async {
    final notifier = ref.read(playbackControllerProvider.notifier);
    final coordinator = notifier.controller?.synthesisCoordinator;
    if (coordinator == null) return false;

    for (var i = 0; i < tracks.length; i++) {
      final isReady = await coordinator.isSegmentReady(
        voiceId: voiceId,
        text: tracks[i].text,
        playbackRate: 1.0,
      );
      if (!isReady) return false;
    }
    return true;
  }

  /// Clear completed/cancelled states.
  void clearState(String bookId, int chapterIndex) {
    final key = (bookId: bookId, chapterIndex: chapterIndex);
    final newJobs = Map<ChapterKey, ChapterSynthesisState>.from(state.jobs);
    newJobs.remove(key);
    state = state.copyWith(jobs: newJobs);
  }

  void _updateProgress(ChapterKey key, PreSynthesisProgress progress) {
    final newJobs = Map<ChapterKey, ChapterSynthesisState>.from(state.jobs);
    newJobs[key] = ChapterSynthesisState(
      bookId: progress.bookId,
      chapterIndex: progress.chapterIndex,
      status: progress.isComplete 
          ? ChapterSynthesisStatus.complete 
          : progress.isCancelled 
              ? ChapterSynthesisStatus.cancelled
              : progress.error != null
                  ? ChapterSynthesisStatus.error
                  : ChapterSynthesisStatus.synthesizing,
      progress: progress.progress,
      currentSegment: progress.completedSegments,
      totalSegments: progress.totalSegments,
      error: progress.error,
    );
    state = state.copyWith(jobs: newJobs);
  }
}
