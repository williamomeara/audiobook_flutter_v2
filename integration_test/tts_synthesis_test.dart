/// Integration tests for TTS synthesis on real device.
///
/// These tests run on a connected device and verify that TTS synthesis works
/// correctly with downloaded voice models.
///
/// Run with: flutter test integration_test/tts_synthesis_test.dart
///
/// Prerequisites:
/// - A connected Android device or emulator
/// - Internet connection for model downloads (only if models not already present)
///
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:audiobook_flutter_v2/app/app_paths.dart';
import 'package:audiobook_flutter_v2/app/granular_download_manager.dart';
import 'package:audiobook_flutter_v2/app/tts_providers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('TTS Synthesis Integration Tests', () {
    late ProviderContainer container;
    late Directory testOutputDir;

    setUpAll(() async {
      // Create a test output directory for synthesized audio files
      final appDir = await getApplicationDocumentsDirectory();
      testOutputDir = Directory('${appDir.path}/tts_test_output');
      if (!await testOutputDir.exists()) {
        await testOutputDir.create(recursive: true);
      }
    });

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    tearDownAll(() async {
      // Clean up test output files
      if (await testOutputDir.exists()) {
        await testOutputDir.delete(recursive: true);
      }
    });

    group('Download Manager', () {
      test('should initialize and load manifest', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);

        expect(downloadState.cores, isNotEmpty);
        expect(downloadState.voices, isNotEmpty);

        // Check expected cores exist
        expect(downloadState.cores.containsKey('kokoro_core_v1'), isTrue);
        expect(downloadState.cores.containsKey('piper_alan_gb_v1'), isTrue);
        expect(downloadState.cores.containsKey('piper_lessac_us_v1'), isTrue);
        expect(downloadState.cores.containsKey('supertonic_core_v1'), isTrue);

        // Check expected voices exist
        expect(downloadState.voices.containsKey('kokoro_af'), isTrue);
        expect(downloadState.voices.containsKey('piper:en_GB-alan-medium'), isTrue);
        expect(downloadState.voices.containsKey('supertonic_m1'), isTrue);

        print('✓ Manifest loaded with ${downloadState.cores.length} cores and ${downloadState.voices.length} voices');
      });

      test('should report correct download status for Piper Alan', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        expect(piperAlanCore, isNotNull);
        print('Piper Alan core status: ${piperAlanCore!.status}');

        if (piperAlanCore.isReady) {
          print('✓ Piper Alan is already downloaded');
        } else {
          print('✗ Piper Alan needs to be downloaded (status: ${piperAlanCore.status})');
        }
      });
    });

    group('Piper Voice Synthesis', () {
      test('should download Piper Alan if not present and synthesize audio', () async {
        final downloadManager = container.read(granularDownloadManagerProvider.notifier);
        var downloadState = await container.read(granularDownloadManagerProvider.future);

        // Check if Piper Alan is downloaded
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];
        expect(piperAlanCore, isNotNull, reason: 'Piper Alan core should exist in manifest');

        if (!piperAlanCore!.isReady) {
          print('Downloading Piper Alan voice model...');
          await downloadManager.downloadCore('piper_alan_gb_v1');

          // Wait for download to complete (poll state)
          var attempts = 0;
          const maxAttempts = 120; // 2 minutes max
          while (attempts < maxAttempts) {
            await Future.delayed(const Duration(seconds: 1));
            downloadState = await container.read(granularDownloadManagerProvider.future);
            final core = downloadState.cores['piper_alan_gb_v1']!;

            if (core.isReady) {
              print('✓ Download complete!');
              break;
            } else if (core.isFailed) {
              fail('Download failed: ${core.error}');
            }

            if (core.progress > 0) {
              print('  Downloading: ${(core.progress * 100).toStringAsFixed(1)}%');
            }
            attempts++;
          }

          if (attempts >= maxAttempts) {
            fail('Download timed out after ${maxAttempts}s');
          }
        } else {
          print('✓ Piper Alan already downloaded, skipping download');
        }

        // Verify core directory exists with expected files
        final paths = await container.read(appPathsProvider.future);
        final coreDir = Directory('${paths.voiceAssetsDir.path}/piper/piper_alan_gb_v1');
        expect(await coreDir.exists(), isTrue, reason: 'Core directory should exist');

        final modelFile = File('${coreDir.path}/model.onnx');
        final configFile = File('${coreDir.path}/model.onnx.json');
        expect(await modelFile.exists(), isTrue, reason: 'model.onnx should exist');
        expect(await configFile.exists(), isTrue, reason: 'model.onnx.json should exist');

        print('✓ Model files verified');
        print('  - model.onnx: ${await modelFile.length()} bytes');
        print('  - model.onnx.json: ${await configFile.length()} bytes');
      }, timeout: const Timeout(Duration(minutes: 5)));

      test('should synthesize text with Piper Alan', () async {
        // First ensure the model is downloaded
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        if (!piperAlanCore!.isReady) {
          print('⚠ Skipping synthesis test - Piper Alan not downloaded');
          print('  Run the download test first or download via the app');
          return;
        }

        // Check if model files have correct names (model.onnx, not en_GB-alan-medium.onnx)
        final paths = await container.read(appPathsProvider.future);
        final coreDir = Directory('${paths.voiceAssetsDir.path}/piper/piper_alan_gb_v1');
        final modelFile = File('${coreDir.path}/model.onnx');
        final oldNameFile = File('${coreDir.path}/en_GB-alan-medium.onnx');

        if (!await modelFile.exists() && await oldNameFile.exists()) {
          print('⚠ Model files have old naming convention (en_GB-alan-medium.onnx)');
          print('  Please delete and re-download Piper Alan to fix:');
          print('  1. Go to Settings → Voice Downloads');
          print('  2. Delete the Piper Alan voice');
          print('  3. Re-download it');
          print('  The new download will use the correct filename (model.onnx)');
          fail('Model files need to be re-downloaded with correct naming');
        }

        // Get the TTS routing engine
        final routingEngine = await container.read(ttsRoutingEngineProvider.future);

        // Verify Piper adapter is available
        final piperAdapter = await container.read(piperAdapterProvider.future);
        expect(piperAdapter, isNotNull, reason: 'Piper adapter should be available');

        // Synthesize test text
        const testText = 'Hello, this is a test of the Piper text to speech engine.';
        const voiceId = 'piper:en_GB-alan-medium';

        print('Synthesizing: "$testText"');
        print('Voice: $voiceId');

        final startTime = DateTime.now();

        final result = await routingEngine.synthesizeToWavFile(
          voiceId: voiceId,
          text: testText,
          playbackRate: 1.0,
        );

        final elapsed = DateTime.now().difference(startTime);

        expect(result.file.existsSync(), isTrue, reason: 'Output file should exist');
        expect(result.durationMs, greaterThan(0), reason: 'Duration should be positive');

        final fileSize = await result.file.length();
        print('✓ Synthesis complete!');
        print('  - Duration: ${result.durationMs}ms');
        print('  - File size: ${(fileSize / 1024).toStringAsFixed(1)} KB');
        print('  - Processing time: ${elapsed.inMilliseconds}ms');
        print('  - Real-time factor: ${(elapsed.inMilliseconds / result.durationMs).toStringAsFixed(2)}x');
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('should synthesize multiple segments sequentially', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        if (!piperAlanCore!.isReady) {
          print('⚠ Skipping multi-segment test - Piper Alan not downloaded');
          return;
        }

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);
        const voiceId = 'piper:en_GB-alan-medium';

        final segments = [
          'First segment. This is the beginning of the audiobook.',
          'Second segment. The story continues with more content.',
          'Third segment. And finally, the conclusion.',
        ];

        print('Synthesizing ${segments.length} segments...');

        var totalDuration = 0;
        final startTime = DateTime.now();

        for (var i = 0; i < segments.length; i++) {
          final result = await routingEngine.synthesizeToWavFile(
            voiceId: voiceId,
            text: segments[i],
            playbackRate: 1.0,
          );

          expect(result.file.existsSync(), isTrue);
          totalDuration += result.durationMs;
          print('  Segment ${i + 1}: ${result.durationMs}ms');
        }

        final elapsed = DateTime.now().difference(startTime);
        print('✓ All segments synthesized');
        print('  - Total audio duration: ${totalDuration}ms');
        print('  - Total processing time: ${elapsed.inMilliseconds}ms');
      }, timeout: const Timeout(Duration(minutes: 3)));
    });

    group('Kokoro Voice Synthesis', () {
      test('should report Kokoro download status', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final kokoroCore = downloadState.cores['kokoro_core_v1'];

        expect(kokoroCore, isNotNull);
        print('Kokoro core status: ${kokoroCore!.status}');

        if (kokoroCore.isReady) {
          print('✓ Kokoro is downloaded');
        } else {
          print('✗ Kokoro needs to be downloaded (status: ${kokoroCore.status})');
        }
      });

      test('should synthesize text with Kokoro if available', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final kokoroCore = downloadState.cores['kokoro_core_v1'];

        if (!kokoroCore!.isReady) {
          print('⚠ Skipping Kokoro synthesis test - core not downloaded');
          return;
        }

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);
        final kokoroAdapter = await container.read(kokoroAdapterProvider.future);
        expect(kokoroAdapter, isNotNull, reason: 'Kokoro adapter should be available');

        const testText = 'Hello, this is a test of the Kokoro text to speech engine.';
        const voiceId = 'kokoro_af';

        print('Synthesizing with Kokoro: "$testText"');

        final startTime = DateTime.now();

        final result = await routingEngine.synthesizeToWavFile(
          voiceId: voiceId,
          text: testText,
          playbackRate: 1.0,
        );

        final elapsed = DateTime.now().difference(startTime);

        expect(result.file.existsSync(), isTrue);
        print('✓ Kokoro synthesis complete!');
        print('  - Duration: ${result.durationMs}ms');
        print('  - Processing time: ${elapsed.inMilliseconds}ms');
      }, timeout: const Timeout(Duration(minutes: 2)));
    });

    group('Supertonic Voice Synthesis', () {
      test('should report Supertonic download status', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final supertonicCore = downloadState.cores['supertonic_core_v1'];

        expect(supertonicCore, isNotNull);
        print('Supertonic core status: ${supertonicCore!.status}');

        if (supertonicCore.isReady) {
          print('✓ Supertonic is downloaded');
        } else {
          print('✗ Supertonic needs to be downloaded (status: ${supertonicCore.status})');
        }
      });

      test('should synthesize text with Supertonic if available', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final supertonicCore = downloadState.cores['supertonic_core_v1'];

        if (!supertonicCore!.isReady) {
          print('⚠ Skipping Supertonic synthesis test - core not downloaded');
          return;
        }

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);
        final supertonicAdapter = await container.read(supertonicAdapterProvider.future);
        expect(supertonicAdapter, isNotNull, reason: 'Supertonic adapter should be available');

        const testText = 'Hello, this is a test of the Supertonic text to speech engine.';
        const voiceId = 'supertonic_m1';

        print('Synthesizing with Supertonic: "$testText"');

        final startTime = DateTime.now();

        final result = await routingEngine.synthesizeToWavFile(
          voiceId: voiceId,
          text: testText,
          playbackRate: 1.0,
        );

        final elapsed = DateTime.now().difference(startTime);

        expect(result.file.existsSync(), isTrue);
        print('✓ Supertonic synthesis complete!');
        print('  - Duration: ${result.durationMs}ms');
        print('  - Processing time: ${elapsed.inMilliseconds}ms');
      }, timeout: const Timeout(Duration(minutes: 2)));
    });

    group('Voice Readiness Checks', () {
      test('should correctly report voice readiness for all voices', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);

        print('\nVoice Readiness Report:');
        print('=' * 50);

        for (final voice in downloadState.voices.values) {
          final isReady = voice.allCoresReady(downloadState.cores);
          final status = isReady ? '✓ Ready' : '✗ Not ready';
          print('  ${voice.displayName}: $status');

          if (!isReady) {
            final missingCores = voice.getMissingCoreIds(downloadState.cores);
            print('    Missing: ${missingCores.join(', ')}');
          }
        }

        print('=' * 50);
        print('Ready voices: ${downloadState.readyVoiceCount}/${downloadState.totalVoiceCount}');
      });
    });

    group('Edge Cases', () {
      test('should handle empty text gracefully', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        if (!piperAlanCore!.isReady) {
          print('⚠ Skipping edge case test - Piper Alan not downloaded');
          return;
        }

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);

        // Empty text should either succeed with minimal audio or throw gracefully
        try {
          final result = await routingEngine.synthesizeToWavFile(
            voiceId: 'piper:en_GB-alan-medium',
            text: '',
            playbackRate: 1.0,
          );
          print('Empty text synthesis returned: ${result.durationMs}ms');
        } catch (e) {
          print('Empty text threw expected error: $e');
          // This is acceptable behavior
        }
      });

      test('should handle very long text', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        if (!piperAlanCore!.isReady) {
          print('⚠ Skipping long text test - Piper Alan not downloaded');
          return;
        }

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);

        // Generate long text
        final longText = List.generate(20, (i) =>
            'This is sentence number ${i + 1} in a very long paragraph. '
        ).join();

        print('Synthesizing long text (${longText.length} chars)...');

        final startTime = DateTime.now();
        final result = await routingEngine.synthesizeToWavFile(
          voiceId: 'piper:en_GB-alan-medium',
          text: longText,
          playbackRate: 1.0,
        );
        final elapsed = DateTime.now().difference(startTime);

        expect(result.file.existsSync(), isTrue);
        print('✓ Long text synthesis complete');
        print('  - Duration: ${result.durationMs}ms');
        print('  - Processing time: ${elapsed.inMilliseconds}ms');
      }, timeout: const Timeout(Duration(minutes: 5)));

      test('should handle special characters', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        if (!piperAlanCore!.isReady) {
          print('⚠ Skipping special chars test - Piper Alan not downloaded');
          return;
        }

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);

        const specialText = 'Hello! How are you? I\'m fine, thanks. "Quoted text" and numbers: 123.';

        final result = await routingEngine.synthesizeToWavFile(
          voiceId: 'piper:en_GB-alan-medium',
          text: specialText,
          playbackRate: 1.0,
        );

        expect(result.file.existsSync(), isTrue);
        print('✓ Special characters handled correctly');
      });
    });

    group('Performance', () {
      test('should benchmark synthesis speed', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        if (!piperAlanCore!.isReady) {
          print('⚠ Skipping benchmark - Piper Alan not downloaded');
          return;
        }

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);
        const voiceId = 'piper:en_GB-alan-medium';

        // Warm up run
        await routingEngine.synthesizeToWavFile(
          voiceId: voiceId,
          text: 'Warm up synthesis.',
          playbackRate: 1.0,
        );

        // Benchmark runs
        final times = <int>[];
        final durations = <int>[];
        const iterations = 5;

        for (var i = 0; i < iterations; i++) {
          final text = 'Benchmark test number ${i + 1}. Testing synthesis speed.';

          final start = DateTime.now();
          final result = await routingEngine.synthesizeToWavFile(
            voiceId: voiceId,
            text: text,
            playbackRate: 1.0,
          );
          final elapsed = DateTime.now().difference(start).inMilliseconds;

          times.add(elapsed);
          durations.add(result.durationMs);
        }

        final avgTime = times.reduce((a, b) => a + b) / times.length;
        final avgDuration = durations.reduce((a, b) => a + b) / durations.length;
        final rtf = avgTime / avgDuration;

        print('\nBenchmark Results ($iterations iterations):');
        print('=' * 50);
        print('  Average processing time: ${avgTime.toStringAsFixed(1)}ms');
        print('  Average audio duration: ${avgDuration.toStringAsFixed(1)}ms');
        print('  Real-time factor: ${rtf.toStringAsFixed(2)}x');
        print('  ${rtf < 1.0 ? '✓ Faster than real-time!' : '✗ Slower than real-time'}');
        print('=' * 50);
      }, timeout: const Timeout(Duration(minutes: 3)));
    });
  });
}
