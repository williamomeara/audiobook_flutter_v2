import 'package:flutter_test/flutter_test.dart';
import 'package:downloads/downloads.dart';

void main() {
  group('CoreDownloadState', () {
    test('isReady returns true when status is ready', () {
      const state = CoreDownloadState(
        coreId: 'kokoro_core_v1',
        displayName: 'Kokoro Core',
        engineType: 'kokoro',
        status: DownloadStatus.ready,
        sizeBytes: 100000,
      );
      
      expect(state.isReady, true);
      expect(state.isDownloading, false);
      expect(state.isFailed, false);
      expect(state.isNotDownloaded, false);
    });

    test('isDownloading returns true when downloading', () {
      const state = CoreDownloadState(
        coreId: 'kokoro_core_v1',
        displayName: 'Kokoro Core',
        engineType: 'kokoro',
        status: DownloadStatus.downloading,
        progress: 0.5,
        sizeBytes: 100000,
      );
      
      expect(state.isReady, false);
      expect(state.isDownloading, true);
      expect(state.isFailed, false);
      expect(state.isNotDownloaded, false);
    });

    test('isDownloading returns true when queued', () {
      const state = CoreDownloadState(
        coreId: 'piper_core_v1',
        displayName: 'Piper Core',
        engineType: 'piper',
        status: DownloadStatus.queued,
        sizeBytes: 50000,
      );
      
      expect(state.isDownloading, true);
    });

    test('isFailed returns true when status is failed', () {
      const state = CoreDownloadState(
        coreId: 'kokoro_core_v1',
        displayName: 'Kokoro Core',
        engineType: 'kokoro',
        status: DownloadStatus.failed,
        sizeBytes: 100000,
        error: 'Network error',
      );
      
      expect(state.isFailed, true);
      expect(state.error, 'Network error');
    });

    test('isNotDownloaded returns true when not downloaded', () {
      const state = CoreDownloadState(
        coreId: 'kokoro_core_v1',
        displayName: 'Kokoro Core',
        engineType: 'kokoro',
        status: DownloadStatus.notDownloaded,
        sizeBytes: 100000,
      );
      
      expect(state.isNotDownloaded, true);
    });

    test('copyWith updates specified fields', () {
      const original = CoreDownloadState(
        coreId: 'kokoro_core_v1',
        displayName: 'Kokoro Core',
        engineType: 'kokoro',
        status: DownloadStatus.notDownloaded,
        progress: 0.0,
        sizeBytes: 100000,
      );
      
      final updated = original.copyWith(
        status: DownloadStatus.downloading,
        progress: 0.5,
      );
      
      expect(updated.coreId, 'kokoro_core_v1');
      expect(updated.status, DownloadStatus.downloading);
      expect(updated.progress, 0.5);
    });

    test('toString includes relevant info', () {
      const state = CoreDownloadState(
        coreId: 'test_core',
        displayName: 'Test',
        engineType: 'test',
        status: DownloadStatus.downloading,
        progress: 0.75,
        sizeBytes: 1000,
      );
      
      final str = state.toString();
      expect(str, contains('test_core'));
      expect(str, contains('75%'));
    });

    test('progress defaults to 0.0', () {
      const state = CoreDownloadState(
        coreId: 'test',
        displayName: 'Test',
        engineType: 'test',
        status: DownloadStatus.notDownloaded,
        sizeBytes: 1000,
      );
      
      expect(state.progress, 0.0);
    });
  });

  group('VoiceDownloadState', () {
    test('allCoresReady returns true when all cores are ready', () {
      const voice = VoiceDownloadState(
        voiceId: 'kokoro-en-us-1',
        displayName: 'Kokoro English',
        engineId: 'kokoro',
        language: 'en-us',
        requiredCoreIds: ['kokoro_core_v1'],
      );
      
      final coreStates = {
        'kokoro_core_v1': const CoreDownloadState(
          coreId: 'kokoro_core_v1',
          displayName: 'Kokoro Core',
          engineType: 'kokoro',
          status: DownloadStatus.ready,
          sizeBytes: 100000,
        ),
      };
      
      expect(voice.allCoresReady(coreStates), true);
    });

    test('allCoresReady returns false when a core is missing', () {
      const voice = VoiceDownloadState(
        voiceId: 'kokoro-en-us-1',
        displayName: 'Kokoro English',
        engineId: 'kokoro',
        language: 'en-us',
        requiredCoreIds: ['kokoro_core_v1', 'extra_core'],
      );
      
      final coreStates = {
        'kokoro_core_v1': const CoreDownloadState(
          coreId: 'kokoro_core_v1',
          displayName: 'Kokoro Core',
          engineType: 'kokoro',
          status: DownloadStatus.ready,
          sizeBytes: 100000,
        ),
      };
      
      expect(voice.allCoresReady(coreStates), false);
    });

    test('allCoresReady returns false when a core is not ready', () {
      const voice = VoiceDownloadState(
        voiceId: 'kokoro-en-us-1',
        displayName: 'Kokoro English',
        engineId: 'kokoro',
        language: 'en-us',
        requiredCoreIds: ['kokoro_core_v1'],
      );
      
      final coreStates = {
        'kokoro_core_v1': const CoreDownloadState(
          coreId: 'kokoro_core_v1',
          displayName: 'Kokoro Core',
          engineType: 'kokoro',
          status: DownloadStatus.downloading,
          sizeBytes: 100000,
        ),
      };
      
      expect(voice.allCoresReady(coreStates), false);
    });

    test('anyDownloading returns true when a core is downloading', () {
      const voice = VoiceDownloadState(
        voiceId: 'piper-voice-1',
        displayName: 'Piper Voice',
        engineId: 'piper',
        language: 'en-us',
        requiredCoreIds: ['piper_core_1', 'piper_core_2'],
      );
      
      final coreStates = {
        'piper_core_1': const CoreDownloadState(
          coreId: 'piper_core_1',
          displayName: 'Piper 1',
          engineType: 'piper',
          status: DownloadStatus.ready,
          sizeBytes: 50000,
        ),
        'piper_core_2': const CoreDownloadState(
          coreId: 'piper_core_2',
          displayName: 'Piper 2',
          engineType: 'piper',
          status: DownloadStatus.downloading,
          progress: 0.3,
          sizeBytes: 50000,
        ),
      };
      
      expect(voice.anyDownloading(coreStates), true);
    });

    test('anyQueued returns true when a core is queued', () {
      const voice = VoiceDownloadState(
        voiceId: 'test-voice',
        displayName: 'Test',
        engineId: 'test',
        language: 'en',
        requiredCoreIds: ['core_1', 'core_2'],
      );
      
      final coreStates = {
        'core_1': const CoreDownloadState(
          coreId: 'core_1',
          displayName: 'Core 1',
          engineType: 'test',
          status: DownloadStatus.ready,
          sizeBytes: 1000,
        ),
        'core_2': const CoreDownloadState(
          coreId: 'core_2',
          displayName: 'Core 2',
          engineType: 'test',
          status: DownloadStatus.queued,
          sizeBytes: 1000,
        ),
      };
      
      expect(voice.anyQueued(coreStates), true);
    });

    test('getMissingCoreIds returns list of non-ready cores', () {
      const voice = VoiceDownloadState(
        voiceId: 'test-voice',
        displayName: 'Test',
        engineId: 'test',
        language: 'en',
        requiredCoreIds: ['core_1', 'core_2', 'core_3'],
      );
      
      final coreStates = {
        'core_1': const CoreDownloadState(
          coreId: 'core_1',
          displayName: 'Core 1',
          engineType: 'test',
          status: DownloadStatus.ready,
          sizeBytes: 1000,
        ),
        'core_2': const CoreDownloadState(
          coreId: 'core_2',
          displayName: 'Core 2',
          engineType: 'test',
          status: DownloadStatus.downloading,
          sizeBytes: 1000,
        ),
        // core_3 not present at all
      };
      
      final missing = voice.getMissingCoreIds(coreStates);
      expect(missing, containsAll(['core_2', 'core_3']));
      expect(missing.length, 2);
    });

    test('speakerId and modelKey are optional', () {
      const voiceWithSpeaker = VoiceDownloadState(
        voiceId: 'kokoro-voice-1',
        displayName: 'Kokoro',
        engineId: 'kokoro',
        language: 'en-us',
        requiredCoreIds: ['kokoro_core'],
        speakerId: 5,
      );
      
      const voiceWithModel = VoiceDownloadState(
        voiceId: 'piper-voice-1',
        displayName: 'Piper',
        engineId: 'piper',
        language: 'en-us',
        requiredCoreIds: ['piper_model'],
        modelKey: 'en_US-amy-medium',
      );
      
      expect(voiceWithSpeaker.speakerId, 5);
      expect(voiceWithSpeaker.modelKey, isNull);
      expect(voiceWithModel.speakerId, isNull);
      expect(voiceWithModel.modelKey, 'en_US-amy-medium');
    });
  });

  group('GranularDownloadState', () {
    test('readyVoices filters by ready cores', () {
      const state = GranularDownloadState(
        cores: {
          'core_1': CoreDownloadState(
            coreId: 'core_1',
            displayName: 'Core 1',
            engineType: 'test',
            status: DownloadStatus.ready,
            sizeBytes: 1000,
          ),
          'core_2': CoreDownloadState(
            coreId: 'core_2',
            displayName: 'Core 2',
            engineType: 'test',
            status: DownloadStatus.notDownloaded,
            sizeBytes: 1000,
          ),
        },
        voices: {
          'voice_1': VoiceDownloadState(
            voiceId: 'voice_1',
            displayName: 'Voice 1',
            engineId: 'test',
            language: 'en',
            requiredCoreIds: ['core_1'],
          ),
          'voice_2': VoiceDownloadState(
            voiceId: 'voice_2',
            displayName: 'Voice 2',
            engineId: 'test',
            language: 'en',
            requiredCoreIds: ['core_2'],
          ),
        },
      );
      
      final available = state.readyVoices;
      expect(available.length, 1);
      expect(available.first.voiceId, 'voice_1');
    });

    test('isCoreReady delegates to core state', () {
      const state = GranularDownloadState(
        cores: {
          'ready_core': CoreDownloadState(
            coreId: 'ready_core',
            displayName: 'Ready',
            engineType: 'test',
            status: DownloadStatus.ready,
            sizeBytes: 1000,
          ),
          'pending_core': CoreDownloadState(
            coreId: 'pending_core',
            displayName: 'Pending',
            engineType: 'test',
            status: DownloadStatus.downloading,
            sizeBytes: 1000,
          ),
        },
        voices: {},
      );
      
      expect(state.isCoreReady('ready_core'), true);
      expect(state.isCoreReady('pending_core'), false);
      expect(state.isCoreReady('missing_core'), false);
    });

    test('empty state has no ready voices', () {
      const state = GranularDownloadState(cores: {}, voices: {});
      
      expect(state.readyVoices, isEmpty);
    });

    test('isVoiceReady checks all core dependencies', () {
      const state = GranularDownloadState(
        cores: {
          'core_1': CoreDownloadState(
            coreId: 'core_1',
            displayName: 'Core 1',
            engineType: 'test',
            status: DownloadStatus.ready,
            sizeBytes: 1000,
          ),
        },
        voices: {
          'voice_ready': VoiceDownloadState(
            voiceId: 'voice_ready',
            displayName: 'Ready Voice',
            engineId: 'test',
            language: 'en',
            requiredCoreIds: ['core_1'],
          ),
          'voice_missing': VoiceDownloadState(
            voiceId: 'voice_missing',
            displayName: 'Missing Voice',
            engineId: 'test',
            language: 'en',
            requiredCoreIds: ['core_missing'],
          ),
        },
      );
      
      expect(state.isVoiceReady('voice_ready'), true);
      expect(state.isVoiceReady('voice_missing'), false);
      expect(state.isVoiceReady('unknown_voice'), false);
    });

    test('isDownloading returns true when any core downloading', () {
      const stateWithDownloading = GranularDownloadState(
        cores: {
          'downloading_core': CoreDownloadState(
            coreId: 'downloading_core',
            displayName: 'Downloading',
            engineType: 'test',
            status: DownloadStatus.downloading,
            sizeBytes: 1000,
          ),
        },
        voices: {},
      );
      
      const stateAllReady = GranularDownloadState(
        cores: {
          'core_1': CoreDownloadState(
            coreId: 'core_1',
            displayName: 'Core 1',
            engineType: 'test',
            status: DownloadStatus.ready,
            sizeBytes: 1000,
          ),
        },
        voices: {},
      );
      
      expect(stateWithDownloading.isDownloading, true);
      expect(stateAllReady.isDownloading, false);
    });

    test('readyVoiceCount and totalVoiceCount', () {
      const state = GranularDownloadState(
        cores: {
          'core_1': CoreDownloadState(
            coreId: 'core_1',
            displayName: 'Core 1',
            engineType: 'test',
            status: DownloadStatus.ready,
            sizeBytes: 1000,
          ),
        },
        voices: {
          'voice_1': VoiceDownloadState(
            voiceId: 'voice_1',
            displayName: 'Voice 1',
            engineId: 'test',
            language: 'en',
            requiredCoreIds: ['core_1'],
          ),
          'voice_2': VoiceDownloadState(
            voiceId: 'voice_2',
            displayName: 'Voice 2',
            engineId: 'test',
            language: 'en',
            requiredCoreIds: ['missing_core'],
          ),
        },
      );
      
      expect(state.readyVoiceCount, 1);
      expect(state.totalVoiceCount, 2);
    });
  });

  group('DownloadStatus enum', () {
    test('has expected values', () {
      expect(DownloadStatus.values, contains(DownloadStatus.notDownloaded));
      expect(DownloadStatus.values, contains(DownloadStatus.queued));
      expect(DownloadStatus.values, contains(DownloadStatus.downloading));
      expect(DownloadStatus.values, contains(DownloadStatus.ready));
      expect(DownloadStatus.values, contains(DownloadStatus.failed));
    });
  });
}
