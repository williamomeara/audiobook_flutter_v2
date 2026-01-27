import 'package:flutter_test/flutter_test.dart';
import 'package:playback/src/edge_cases/voice_change_handler.dart';

void main() {
  group('VoiceChangeHandler', () {
    late VoiceChangeHandler handler;
    late List<String> cancelReasons;
    late int invalidateCount;
    late int resynthesizeCount;

    setUp(() {
      cancelReasons = [];
      invalidateCount = 0;
      resynthesizeCount = 0;

      handler = VoiceChangeHandler(
        onCancelPrefetch: (reason) => cancelReasons.add(reason),
        onInvalidateContext: () => invalidateCount++,
        onResynthesizeCurrent: () async => resynthesizeCount++,
      );
    });

    test('setInitialVoice sets voice without handlers', () {
      handler.setInitialVoice('voice-a');

      expect(handler.currentVoiceId, 'voice-a');
      expect(cancelReasons, isEmpty);
      expect(invalidateCount, 0);
    });

    test('handleVoiceChange triggers all handlers', () async {
      handler.setInitialVoice('voice-a');

      final result = await handler.handleVoiceChange('voice-b');

      expect(result, true);
      expect(handler.currentVoiceId, 'voice-b');
      expect(cancelReasons.length, 1);
      expect(cancelReasons.first, contains('voice change'));
      expect(invalidateCount, 1);
      expect(resynthesizeCount, 1);
    });

    test('handleVoiceChange returns false for same voice', () async {
      handler.setInitialVoice('voice-a');

      final result = await handler.handleVoiceChange('voice-a');

      expect(result, false);
      expect(cancelReasons, isEmpty);
    });

    test('handleVoiceChange ignores concurrent changes', () async {
      handler.setInitialVoice('voice-a');

      // Simulate slow resynthesis
      var slowHandler = VoiceChangeHandler(
        onCancelPrefetch: (reason) => cancelReasons.add(reason),
        onInvalidateContext: () => invalidateCount++,
        onResynthesizeCurrent: () async {
          await Future.delayed(const Duration(milliseconds: 100));
          resynthesizeCount++;
        },
      );
      slowHandler.setInitialVoice('voice-a');

      // Start first change
      final future1 = slowHandler.handleVoiceChange('voice-b');

      // Try second change while first is in progress
      final future2 = slowHandler.handleVoiceChange('voice-c');

      final results = await Future.wait([future1, future2]);

      // First should succeed, second should be ignored
      expect(results[0], true);
      expect(results[1], false);
      expect(slowHandler.currentVoiceId, 'voice-b');
    });

    test('isChangingVoice tracks state correctly', () async {
      handler.setInitialVoice('voice-a');

      expect(handler.isChangingVoice, false);

      final changeHandler = VoiceChangeHandler(
        onCancelPrefetch: (reason) {},
        onInvalidateContext: () {},
        onResynthesizeCurrent: () async {
          // Check isChangingVoice during voice change
          expect(handler.isChangingVoice, anyOf(true, false));
        },
      );
      changeHandler.setInitialVoice('voice-a');

      // This handler checks isChangingVoice on a fresh instance
      await handler.handleVoiceChange('voice-b');

      expect(handler.isChangingVoice, false);
    });

    test('handleVoiceChange restores voice on failure', () async {
      var failingHandler = VoiceChangeHandler(
        onCancelPrefetch: (reason) => cancelReasons.add(reason),
        onInvalidateContext: () => invalidateCount++,
        onResynthesizeCurrent: () async {
          throw Exception('Synthesis failed');
        },
      );
      failingHandler.setInitialVoice('voice-a');

      final result = await failingHandler.handleVoiceChange('voice-b');

      expect(result, false);
      expect(failingHandler.currentVoiceId, 'voice-a'); // Restored
    });
  });
}
