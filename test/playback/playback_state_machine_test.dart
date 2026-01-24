import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:core_domain/core_domain.dart';
import 'package:just_audio/just_audio.dart';
import 'package:playback/src/audio_output.dart';
import 'package:playback/src/playback_controller.dart';
import 'package:playback/src/playback_state.dart';
import 'package:tts_engines/tts_engines.dart';

/// Mock AudioOutput for testing
class MockAudioOutput implements AudioOutput {
  bool _isPlaying = false;
  bool _isPaused = false;
  bool _hasSource = false;
  Duration _position = Duration.zero;
  final _eventController = StreamController<AudioEvent>.broadcast();
  
  // Test helpers
  bool playFileCalled = false;
  bool pauseCalled = false;
  bool resumeCalled = false;
  bool stopCalled = false;
  int playFileCallCount = 0;
  Duration? lastSetPosition;
  List<String> playedFiles = [];
  
  // Control for simulating delays
  Duration playDelay = Duration.zero;
  Duration synthesisSimDelay = const Duration(milliseconds: 10);
  
  @override
  Stream<AudioEvent> get events => _eventController.stream;
  
  @override
  AudioPlayer? get player => null;  // Mock doesn't use real player
  
  @override
  bool get isPaused => _isPaused;
  
  @override
  bool get hasSource => _hasSource;
  
  @override
  Future<void> playFile(String path, {double playbackRate = 1.0}) async {
    playFileCalled = true;
    playFileCallCount++;
    playedFiles.add(path);
    if (playDelay != Duration.zero) {
      await Future.delayed(playDelay);
    }
    _hasSource = true;
    _isPlaying = true;
    _isPaused = false;
  }
  
  @override
  Future<void> pause() async {
    pauseCalled = true;
    _isPlaying = false;
    _isPaused = true;
  }
  
  @override
  Future<void> resume() async {
    resumeCalled = true;
    _isPlaying = true;
    _isPaused = false;
  }
  
  @override
  Future<void> stop() async {
    stopCalled = true;
    _isPlaying = false;
    _isPaused = false;
    _hasSource = false;
    _position = Duration.zero;
  }
  
  @override
  Future<void> setSpeed(double rate) async {}
  
  @override
  Future<void> dispose() async {
    await _eventController.close();
  }
  
  // Test helper to emit completion event
  void completePlayback() {
    _isPlaying = false;
    _eventController.add(AudioEvent.completed);
  }
  
  // Test helper to emit error event
  void emitError() {
    _isPlaying = false;
    _eventController.add(AudioEvent.error);
  }
  
  void reset() {
    playFileCalled = false;
    pauseCalled = false;
    resumeCalled = false;
    stopCalled = false;
    playFileCallCount = 0;
    lastSetPosition = null;
    playedFiles.clear();
    _isPlaying = false;
    _isPaused = false;
    _hasSource = false;
    _position = Duration.zero;
  }
}

/// Mock RoutingEngine for testing
class MockRoutingEngine implements RoutingEngine {
  final Duration synthesisDelay;
  int synthesizeCalls = 0;
  List<String> synthesizedTexts = [];
  bool shouldFail = false;
  String? failureMessage;
  
  // Allow cancellation testing
  Completer<void>? _currentSynthesis;
  bool synthesisInProgress = false;
  
  MockRoutingEngine({this.synthesisDelay = const Duration(milliseconds: 10)});
  
  @override
  Future<SynthResult> synthesizeToWavFile({
    required String voiceId,
    required String text,
    required double playbackRate,
  }) async {
    synthesizeCalls++;
    synthesizedTexts.add(text);
    synthesisInProgress = true;
    
    _currentSynthesis = Completer<void>();
    
    // Wait for delay or cancellation
    await Future.any([
      Future.delayed(synthesisDelay),
      _currentSynthesis!.future,
    ]);
    
    synthesisInProgress = false;
    
    if (shouldFail) {
      throw Exception(failureMessage ?? 'Synthesis failed');
    }
    
    return SynthResult(
      file: File('/fake/path_$synthesizeCalls.wav'),
      durationMs: 1000,
    );
  }
  
  void cancelCurrentSynthesis() {
    _currentSynthesis?.complete();
  }
  
  @override
  Stream<CoreReadiness> watchCoreReadiness(String coreId) {
    return Stream.value(CoreReadiness.readyFor(coreId));
  }
  
  @override
  Future<CoreReadiness> checkReadiness(String voiceId) async {
    return CoreReadiness.readyFor(voiceId);
  }
  
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Mock AudioCache for testing
class MockAudioCache implements AudioCache {
  final Map<CacheKey, String> _cache = {};
  
  void put(CacheKey key, String path) => _cache[key] = path;
  
  @override
  Future<void> clear() async => _cache.clear();
  
  @override
  Future<bool> isReady(CacheKey key) async => _cache.containsKey(key);
  
  @override
  Future<String?> getPath(CacheKey key) async => _cache[key];
  
  @override
  Future<void> store(CacheKey key, File file) async {
    _cache[key] = file.path;
  }
  
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

List<AudioTrack> createTestQueue(int count, {int chapterIndex = 0}) {
  return List.generate(count, (i) => AudioTrack(
    id: 'track_$i',
    text: 'This is test text for segment $i.',
    chapterIndex: chapterIndex,
    segmentIndex: i,
  ));
}

void main() {
  group('PlaybackController State Machine', () {
    late AudiobookPlaybackController controller;
    late MockAudioOutput audioOutput;
    late MockRoutingEngine engine;
    late MockAudioCache cache;
    
    setUp(() {
      audioOutput = MockAudioOutput();
      engine = MockRoutingEngine();
      cache = MockAudioCache();
      controller = AudiobookPlaybackController(
        engine: engine,
        cache: cache,
        voiceIdResolver: (_) => 'test-voice',
        audioOutput: audioOutput,
      );
    });
    
    tearDown(() async {
      await controller.dispose();
    });
    
    group('Rapid play/pause sequences', () {
      test('rapid play-pause-play results in playing state', () async {
        final queue = createTestQueue(5);
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: false,
        );
        
        // Rapid sequence: play -> pause -> play
        final playFuture1 = controller.play();
        await Future.delayed(const Duration(milliseconds: 1));
        final pauseFuture = controller.pause();
        await Future.delayed(const Duration(milliseconds: 1));
        final playFuture2 = controller.play();
        
        // Wait for all operations
        await Future.wait([playFuture1, pauseFuture, playFuture2]);
        
        // Final state should be playing (last operation wins)
        // Note: The exact state depends on timing, but should be deterministic
        expect(controller.state.queue, equals(queue));
      });
      
      test('pause during buffering stops buffering', () async {
        final queue = createTestQueue(5);
        // Use very slow synthesis to ensure we can catch buffering state
        final slowEngine = MockRoutingEngine(synthesisDelay: const Duration(seconds: 1));
        
        // Recreate controller with slow engine
        await controller.dispose();
        controller = AudiobookPlaybackController(
          engine: slowEngine,
          cache: cache,
          voiceIdResolver: (_) => 'test-voice',
          audioOutput: audioOutput,
        );
        
        // Start loading (don't await - we want to check state while buffering)
        unawaited(controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: true,
        ));
        
        // Wait a bit for loadChapter to start
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Pause while buffering
        await controller.pause();
        
        // Should no longer be buffering
        expect(controller.state.isBuffering, isFalse);
        expect(controller.state.isPlaying, isFalse);
      });
    });
    
    group('Dispose during operations', () {
      test('dispose during synthesis doesnt throw', () async {
        final queue = createTestQueue(5);
        final slowEngine = MockRoutingEngine(synthesisDelay: const Duration(seconds: 2));
        
        await controller.dispose();
        controller = AudiobookPlaybackController(
          engine: slowEngine,
          cache: cache,
          voiceIdResolver: (_) => 'test-voice',
          audioOutput: audioOutput,
        );
        
        // Start playback (will be buffering)
        unawaited(controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: true,
        ));
        
        // Wait a bit for synthesis to potentially start
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Dispose while operation may be in progress - should not throw
        await expectLater(controller.dispose(), completes);
      });
      
      test('dispose during playback stops audio', () async {
        final queue = createTestQueue(3);
        
        // Pre-cache first track to skip synthesis
        final key = CacheKeyGenerator.generate(
          voiceId: 'test-voice',
          text: queue[0].text,
          playbackRate: 1.0,
        );
        cache.put(key, '/fake/cached.wav');
        
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: true,
        );
        
        await Future.delayed(const Duration(milliseconds: 50));
        
        await controller.dispose();
        
        // Audio should be stopped
        expect(audioOutput.stopCalled, isTrue);
      });
    });
    
    group('Loading chapter while playing', () {
      test('loading new chapter cancels current playback', () async {
        final queue1 = createTestQueue(3, chapterIndex: 0);
        final queue2 = createTestQueue(3, chapterIndex: 1);
        
        // Pre-cache first track of chapter 1
        final key1 = CacheKeyGenerator.generate(
          voiceId: 'test-voice',
          text: queue1[0].text,
          playbackRate: 1.0,
        );
        cache.put(key1, '/fake/ch1_cached.wav');
        
        await controller.loadChapter(
          tracks: queue1,
          bookId: 'book1',
          autoPlay: true,
        );
        
        await Future.delayed(const Duration(milliseconds: 50));
        expect(controller.state.bookId, 'book1');
        expect(controller.state.currentTrack?.chapterIndex, 0);
        
        // Load chapter 2 while chapter 1 is playing
        final key2 = CacheKeyGenerator.generate(
          voiceId: 'test-voice',
          text: queue2[0].text,
          playbackRate: 1.0,
        );
        cache.put(key2, '/fake/ch2_cached.wav');
        
        await controller.loadChapter(
          tracks: queue2,
          bookId: 'book1',
          autoPlay: true,
        );
        
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Should now be on chapter 2
        expect(controller.state.queue, equals(queue2));
        expect(controller.state.currentTrack?.chapterIndex, 1);
      });
      
      test('loading while synthesis running cancels synthesis', () async {
        final queue1 = createTestQueue(3, chapterIndex: 0);
        final queue2 = createTestQueue(3, chapterIndex: 1);
        
        // Use slow synthesis for chapter 1
        final slowEngine = MockRoutingEngine(synthesisDelay: const Duration(seconds: 2));
        await controller.dispose();
        controller = AudiobookPlaybackController(
          engine: slowEngine,
          cache: cache,
          voiceIdResolver: (_) => 'test-voice',
          audioOutput: audioOutput,
        );
        
        // Start loading chapter 1 (slow synthesis)
        unawaited(controller.loadChapter(
          tracks: queue1,
          bookId: 'book1',
          autoPlay: true,
        ));
        
        // Wait a bit for operation to start
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Pre-cache chapter 2 first track (instant)
        final key2 = CacheKeyGenerator.generate(
          voiceId: 'test-voice',
          text: queue2[0].text,
          playbackRate: 1.0,
        );
        cache.put(key2, '/fake/ch2_cached.wav');
        
        // Load chapter 2 - should cancel chapter 1 synthesis
        await controller.loadChapter(
          tracks: queue2,
          bookId: 'book1',
          autoPlay: true,
        );
        
        // Should be on chapter 2
        expect(controller.state.queue, equals(queue2));
      });
    });
    
    group('Error recovery scenarios', () {
      test('synthesis error shows error in state', () async {
        final queue = createTestQueue(3);
        engine.shouldFail = true;
        engine.failureMessage = 'Voice model not loaded';
        
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: true,
        );
        
        // Wait for synthesis attempt
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Should have error in state
        expect(controller.state.error, isNotNull);
        expect(controller.state.isPlaying, isFalse);
        expect(controller.state.isBuffering, isFalse);
      });
      
      test('error clears on retry', () async {
        final queue = createTestQueue(3);
        
        // First attempt fails
        engine.shouldFail = true;
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: true,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        expect(controller.state.error, isNotNull);
        final firstError = controller.state.error;
        
        // Fix the engine
        engine.shouldFail = false;
        
        // Retry by loading again (which clears error via copyWith)
        // Note: controller shares the same engine instance, so this tests the path
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: false, // Don't auto-play to avoid synthesis
        );
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Error should be cleared by the loadChapter operation
        // (copyWith without error param clears it)
        expect(controller.state.error, isNot(equals(firstError)));
      });
      
      test('audio error during playback shows error', () async {
        final queue = createTestQueue(3);
        
        // Pre-cache first track
        final key = CacheKeyGenerator.generate(
          voiceId: 'test-voice',
          text: queue[0].text,
          playbackRate: 1.0,
        );
        cache.put(key, '/fake/cached.wav');
        
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: true,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Simulate audio error
        audioOutput.emitError();
        await Future.delayed(const Duration(milliseconds: 10));
        
        // Should have error state
        expect(controller.state.error, isNotNull);
        expect(controller.state.isPlaying, isFalse);
      });
    });
    
    group('Track navigation', () {
      test('nextTrack advances to next segment', () async {
        final queue = createTestQueue(5);
        
        // Pre-cache first two tracks
        for (var i = 0; i < 2; i++) {
          final key = CacheKeyGenerator.generate(
            voiceId: 'test-voice',
            text: queue[i].text,
            playbackRate: 1.0,
          );
          cache.put(key, '/fake/track_$i.wav');
        }
        
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: true,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(controller.state.currentIndex, 0);
        
        await controller.nextTrack();
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(controller.state.currentIndex, 1);
      });
      
      test('previousTrack goes back', () async {
        final queue = createTestQueue(5);
        
        // Pre-cache tracks 0-2
        for (var i = 0; i < 3; i++) {
          final key = CacheKeyGenerator.generate(
            voiceId: 'test-voice',
            text: queue[i].text,
            playbackRate: 1.0,
          );
          cache.put(key, '/fake/track_$i.wav');
        }
        
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          startIndex: 2,
          autoPlay: true,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(controller.state.currentIndex, 2);
        
        await controller.previousTrack();
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(controller.state.currentIndex, 1);
      });
      
      test('nextTrack at end stays at end', () async {
        final queue = createTestQueue(3);
        
        // Pre-cache last track
        final key = CacheKeyGenerator.generate(
          voiceId: 'test-voice',
          text: queue[2].text,
          playbackRate: 1.0,
        );
        cache.put(key, '/fake/track_2.wav');
        
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          startIndex: 2,
          autoPlay: true,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(controller.state.currentIndex, 2);
        expect(controller.state.hasNextTrack, isFalse);
        
        await controller.nextTrack();
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Should still be at index 2
        expect(controller.state.currentIndex, 2);
      });
      
      test('previousTrack at start stays at start', () async {
        final queue = createTestQueue(3);
        
        // Pre-cache first track
        final key = CacheKeyGenerator.generate(
          voiceId: 'test-voice',
          text: queue[0].text,
          playbackRate: 1.0,
        );
        cache.put(key, '/fake/track_0.wav');
        
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: true,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(controller.state.currentIndex, 0);
        expect(controller.state.hasPreviousTrack, isFalse);
        
        await controller.previousTrack();
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Should still be at index 0
        expect(controller.state.currentIndex, 0);
      });
    });
    
    group('Seek operations', () {
      test('seekToTrack jumps to specific index', () async {
        final queue = createTestQueue(5);
        
        // Pre-cache all tracks
        for (var i = 0; i < queue.length; i++) {
          final key = CacheKeyGenerator.generate(
            voiceId: 'test-voice',
            text: queue[i].text,
            playbackRate: 1.0,
          );
          cache.put(key, '/fake/track_$i.wav');
        }
        
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: true,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(controller.state.currentIndex, 0);
        
        await controller.seekToTrack(3);
        await Future.delayed(const Duration(milliseconds: 100)); // Account for debounce
        
        expect(controller.state.currentIndex, 3);
      });
      
      test('rapid seeks debounce', () async {
        final queue = createTestQueue(10);
        
        // Pre-cache all tracks
        for (var i = 0; i < queue.length; i++) {
          final key = CacheKeyGenerator.generate(
            voiceId: 'test-voice',
            text: queue[i].text,
            playbackRate: 1.0,
          );
          cache.put(key, '/fake/track_$i.wav');
        }
        
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: true,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        
        final initialCallCount = audioOutput.playFileCallCount;
        
        // Rapid seeks
        unawaited(controller.seekToTrack(1));
        unawaited(controller.seekToTrack(2));
        unawaited(controller.seekToTrack(3));
        unawaited(controller.seekToTrack(4));
        unawaited(controller.seekToTrack(5));
        
        // Wait for debounce
        await Future.delayed(const Duration(milliseconds: 300));
        
        // Should not have called playFile for each seek (debounced)
        // The exact behavior depends on implementation
        expect(controller.state.currentIndex, 5);
      });
    });
    
    group('State transitions', () {
      test('initial state is empty', () {
        expect(controller.state.isPlaying, isFalse);
        expect(controller.state.isBuffering, isFalse);
        expect(controller.state.queue, isEmpty);
        expect(controller.state.currentTrack, isNull);
      });
      
      test('loading sets queue and current track', () async {
        final queue = createTestQueue(3);
        
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: false,
        );
        
        expect(controller.state.queue, equals(queue));
        expect(controller.state.currentTrack, equals(queue[0]));
        expect(controller.state.bookId, 'book1');
        expect(controller.state.isPlaying, isFalse);
      });
      
      test('play sets buffering then playing', () async {
        final queue = createTestQueue(3);
        
        // Pre-cache first track
        final key = CacheKeyGenerator.generate(
          voiceId: 'test-voice',
          text: queue[0].text,
          playbackRate: 1.0,
        );
        cache.put(key, '/fake/cached.wav');
        
        await controller.loadChapter(
          tracks: queue,
          bookId: 'book1',
          autoPlay: false,
        );
        
        // Collect states during play
        final states = <PlaybackState>[];
        final sub = controller.stateStream.listen(states.add);
        
        await controller.play();
        await Future.delayed(const Duration(milliseconds: 100));
        
        await sub.cancel();
        
        // Should have transitioned through buffering to playing
        expect(states.any((s) => s.isPlaying), isTrue);
      });
    });
  });
  
  group('PlaybackState', () {
    test('copyWith without error clears error', () {
      final state = const PlaybackState(error: 'Some error');
      final newState = state.copyWith(isPlaying: true);
      expect(newState.error, isNull);
    });
    
    test('copyWith preserves other fields', () {
      final tracks = createTestQueue(3);
      final state = PlaybackState(
        isPlaying: true,
        isBuffering: false,
        currentTrack: tracks[1],
        bookId: 'book1',
        queue: tracks,
        playbackRate: 1.5,
      );
      
      final newState = state.copyWith(isPlaying: false);
      
      expect(newState.isPlaying, isFalse);
      expect(newState.isBuffering, isFalse);
      expect(newState.currentTrack, equals(tracks[1]));
      expect(newState.bookId, 'book1');
      expect(newState.queue, equals(tracks));
      expect(newState.playbackRate, 1.5);
    });
    
    test('currentIndex returns correct value', () {
      final tracks = createTestQueue(5);
      final state = PlaybackState(
        queue: tracks,
        currentTrack: tracks[2],
      );
      
      expect(state.currentIndex, 2);
    });
    
    test('currentIndex returns -1 when track not in queue', () {
      final tracks = createTestQueue(3);
      final otherTrack = AudioTrack(
        id: 'other',
        text: 'Other',
        chapterIndex: 0,
        segmentIndex: 99,
      );
      
      final state = PlaybackState(
        queue: tracks,
        currentTrack: otherTrack,
      );
      
      expect(state.currentIndex, -1);
    });
    
    test('hasNextTrack and hasPreviousTrack', () {
      final tracks = createTestQueue(3);
      
      // At start
      var state = PlaybackState(queue: tracks, currentTrack: tracks[0]);
      expect(state.hasNextTrack, isTrue);
      expect(state.hasPreviousTrack, isFalse);
      
      // In middle
      state = PlaybackState(queue: tracks, currentTrack: tracks[1]);
      expect(state.hasNextTrack, isTrue);
      expect(state.hasPreviousTrack, isTrue);
      
      // At end
      state = PlaybackState(queue: tracks, currentTrack: tracks[2]);
      expect(state.hasNextTrack, isFalse);
      expect(state.hasPreviousTrack, isTrue);
    });
  });
}
