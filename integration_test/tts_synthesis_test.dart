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

import 'test_logger.dart';

// ignore_for_file: avoid_print (using TestLogger instead)

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

        TestLogger.success(' Manifest loaded with ${downloadState.cores.length} cores and ${downloadState.voices.length} voices');
      });

      test('should report correct download status for Piper Alan', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        expect(piperAlanCore, isNotNull);
        TestLogger.log('Piper Alan core status: ${piperAlanCore!.status}');

        if (piperAlanCore.isReady) {
          TestLogger.success(' Piper Alan is already downloaded');
        } else {
          TestLogger.error(' Piper Alan needs to be downloaded (status: ${piperAlanCore.status})');
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
          TestLogger.log('Downloading Piper Alan voice model...');
          await downloadManager.downloadCore('piper_alan_gb_v1');

          // Wait for download to complete (poll state)
          var attempts = 0;
          const maxAttempts = 120; // 2 minutes max
          while (attempts < maxAttempts) {
            await Future.delayed(const Duration(seconds: 1));
            downloadState = await container.read(granularDownloadManagerProvider.future);
            final core = downloadState.cores['piper_alan_gb_v1']!;

            if (core.isReady) {
              TestLogger.success(' Download complete!');
              break;
            } else if (core.isFailed) {
              fail('Download failed: ${core.error}');
            }

            if (core.progress > 0) {
              TestLogger.progress('Downloading: ${(core.progress * 100).toStringAsFixed(1)}%');
            }
            attempts++;
          }

          if (attempts >= maxAttempts) {
            fail('Download timed out after ${maxAttempts}s');
          }
        } else {
          TestLogger.success(' Piper Alan already downloaded, skipping download');
        }

        // Verify core directory exists with expected files (sherpa-onnx format)
        final paths = await container.read(appPathsProvider.future);
        final coreDir = Directory('${paths.voiceAssetsDir.path}/piper/piper_alan_gb_v1');
        expect(await coreDir.exists(), isTrue, reason: 'Core directory should exist');

        // sherpa-onnx Piper models have: {modelKey}.onnx, tokens.txt, espeak-ng-data/
        // The model file may be named model.onnx (old format) or en_GB-alan-medium.onnx (sherpa-onnx format)
        final modelFile = File('${coreDir.path}/model.onnx');
        final sherpaModelFile = File('${coreDir.path}/en_GB-alan-medium.onnx');
        final tokensFile = File('${coreDir.path}/tokens.txt');
        
        final hasModel = await modelFile.exists() || await sherpaModelFile.exists();
        expect(hasModel, isTrue, reason: 'ONNX model file should exist (model.onnx or en_GB-alan-medium.onnx)');
        expect(await tokensFile.exists(), isTrue, reason: 'tokens.txt should exist');

        final activeModel = await modelFile.exists() ? modelFile : sherpaModelFile;
        TestLogger.success(' Model files verified (sherpa-onnx format)');
        TestLogger.progress('- ${activeModel.path.split('/').last}: ${await activeModel.length()} bytes');
        TestLogger.progress('- tokens.txt: ${await tokensFile.length()} bytes');
      }, timeout: const Timeout(Duration(minutes: 5)));

      test('should synthesize text with Piper Alan', () async {
        // First ensure the model is downloaded
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        if (!piperAlanCore!.isReady) {
          TestLogger.log('⚠ Skipping synthesis test - Piper Alan not downloaded');
          TestLogger.progress('Run the download test first or download via the app');
          return;
        }

        // Verify model directory exists
        final paths = await container.read(appPathsProvider.future);
        final coreDir = Directory('${paths.voiceAssetsDir.path}/piper/piper_alan_gb_v1');
        expect(await coreDir.exists(), isTrue, reason: 'Core directory should exist');

        // Get the TTS routing engine
        final routingEngine = await container.read(ttsRoutingEngineProvider.future);

        // Verify Piper adapter is available
        final piperAdapter = await container.read(piperAdapterProvider.future);
        expect(piperAdapter, isNotNull, reason: 'Piper adapter should be available');

        // Synthesize test text
        const testText = 'Hello, this is a test of the Piper text to speech engine.';
        const voiceId = 'piper:en_GB-alan-medium';

        TestLogger.log('Synthesizing: "$testText"');
        TestLogger.log('Voice: $voiceId');

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
        TestLogger.success(' Synthesis complete!');
        TestLogger.progress('- Duration: ${result.durationMs}ms');
        TestLogger.progress('- File size: ${(fileSize / 1024).toStringAsFixed(1)} KB');
        TestLogger.progress('- Processing time: ${elapsed.inMilliseconds}ms');
        TestLogger.progress('- Real-time factor: ${(elapsed.inMilliseconds / result.durationMs).toStringAsFixed(2)}x');
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('should synthesize multiple segments sequentially', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        if (!piperAlanCore!.isReady) {
          TestLogger.log('⚠ Skipping multi-segment test - Piper Alan not downloaded');
          return;
        }

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);
        const voiceId = 'piper:en_GB-alan-medium';

        final segments = [
          'First segment. This is the beginning of the audiobook.',
          'Second segment. The story continues with more content.',
          'Third segment. And finally, the conclusion.',
        ];

        TestLogger.log('Synthesizing ${segments.length} segments...');

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
          TestLogger.progress('Segment ${i + 1}: ${result.durationMs}ms');
        }

        final elapsed = DateTime.now().difference(startTime);
        TestLogger.success(' All segments synthesized');
        TestLogger.progress('- Total audio duration: ${totalDuration}ms');
        TestLogger.progress('- Total processing time: ${elapsed.inMilliseconds}ms');
      }, timeout: const Timeout(Duration(minutes: 3)));
    });

    group('Kokoro Voice Synthesis', () {
      test('should report Kokoro download status', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final kokoroCore = downloadState.cores['kokoro_core_v1'];

        expect(kokoroCore, isNotNull);
        TestLogger.log('Kokoro core status: ${kokoroCore!.status}');

        if (kokoroCore.isReady) {
          TestLogger.success(' Kokoro is downloaded');
        } else {
          TestLogger.error(' Kokoro needs to be downloaded (status: ${kokoroCore.status})');
        }
      });

      test('should download and verify Kokoro core files', () async {
        final downloadManager = container.read(granularDownloadManagerProvider.notifier);
        var downloadState = await container.read(granularDownloadManagerProvider.future);
        final kokoroCore = downloadState.cores['kokoro_core_v1'];

        if (!kokoroCore!.isReady) {
          TestLogger.log('Downloading Kokoro core model...');
          await downloadManager.downloadCore('kokoro_core_v1');

          // Wait for download to complete (poll state)
          var attempts = 0;
          const maxAttempts = 180; // 3 minutes max
          while (attempts < maxAttempts) {
            await Future.delayed(const Duration(seconds: 1));
            downloadState = await container.read(granularDownloadManagerProvider.future);
            final core = downloadState.cores['kokoro_core_v1']!;

            if (core.isReady) {
              TestLogger.success(' Download complete!');
              break;
            } else if (core.isFailed) {
              fail('Download failed: ${core.error}');
            }

            if (core.progress > 0) {
              TestLogger.progress('Downloading: ${(core.progress * 100).toStringAsFixed(1)}%');
            }
            attempts++;
          }

          if (attempts >= maxAttempts) {
            fail('Download timed out after ${maxAttempts}s');
          }
        } else {
          TestLogger.success(' Kokoro already downloaded, skipping download');
        }

        // Verify core directory exists with expected files (sherpa-onnx format)
        final paths = await container.read(appPathsProvider.future);
        final coreDir = Directory('${paths.voiceAssetsDir.path}/kokoro/kokoro_core_v1');
        expect(await coreDir.exists(), isTrue, reason: 'Core directory should exist');

        // sherpa-onnx Kokoro models have: model.int8.onnx, tokens.txt, voices.bin, espeak-ng-data/
        final modelFile = File('${coreDir.path}/model.onnx');
        final int8ModelFile = File('${coreDir.path}/model.int8.onnx');
        final tokensFile = File('${coreDir.path}/tokens.txt');
        final voicesFile = File('${coreDir.path}/voices.bin');
        final espeakDir = Directory('${coreDir.path}/espeak-ng-data');

        final hasModel = await modelFile.exists() || await int8ModelFile.exists();
        expect(hasModel, isTrue, reason: 'ONNX model file should exist (model.onnx or model.int8.onnx)');
        expect(await tokensFile.exists(), isTrue, reason: 'tokens.txt should exist');
        expect(await voicesFile.exists(), isTrue, reason: 'voices.bin should exist');
        expect(await espeakDir.exists(), isTrue, reason: 'espeak-ng-data directory should exist');

        final activeModel = await modelFile.exists() ? modelFile : int8ModelFile;
        TestLogger.success(' Model files verified (sherpa-onnx format)');
        TestLogger.progress('- ${activeModel.path.split('/').last}: ${await activeModel.length()} bytes');
        TestLogger.progress('- tokens.txt: ${await tokensFile.length()} bytes');
        TestLogger.progress('- voices.bin: ${await voicesFile.length()} bytes');
      }, timeout: const Timeout(Duration(minutes: 5)));

      test('should synthesize text with Kokoro', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final kokoroCore = downloadState.cores['kokoro_core_v1'];

        if (!kokoroCore!.isReady) {
          TestLogger.log('⚠ Skipping Kokoro synthesis test - core not downloaded');
          TestLogger.progress('Run the download test first or download via the app');
          return;
        }

        // Verify model directory exists
        final paths = await container.read(appPathsProvider.future);
        final coreDir = Directory('${paths.voiceAssetsDir.path}/kokoro/kokoro_core_v1');
        expect(await coreDir.exists(), isTrue, reason: 'Core directory should exist');

        // Get the TTS routing engine
        final routingEngine = await container.read(ttsRoutingEngineProvider.future);

        // Verify Kokoro adapter is available
        final kokoroAdapter = await container.read(kokoroAdapterProvider.future);
        expect(kokoroAdapter, isNotNull, reason: 'Kokoro adapter should be available');

        // Synthesize test text
        const testText = 'Hello, this is a test of the Kokoro text to speech engine.';
        const voiceId = 'kokoro_af';

        TestLogger.log('Synthesizing: "$testText"');
        TestLogger.log('Voice: $voiceId');

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
        final rtf = elapsed.inMilliseconds / result.durationMs;
        TestLogger.success(' Kokoro synthesis complete!');
        TestLogger.progress('- Duration: ${result.durationMs}ms');
        TestLogger.progress('- File size: ${(fileSize / 1024).toStringAsFixed(1)} KB');
        TestLogger.progress('- Processing time: ${elapsed.inMilliseconds}ms');
        TestLogger.progress('- Real-time factor: ${rtf.toStringAsFixed(2)}x');
        
        // Kokoro should be reasonably fast (< 2x real-time)
        expect(rtf, lessThan(2.0), reason: 'Kokoro RTF should be less than 2x');
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('should synthesize with multiple Kokoro voices', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final kokoroCore = downloadState.cores['kokoro_core_v1'];

        if (!kokoroCore!.isReady) {
          TestLogger.log('⚠ Skipping multi-voice test - Kokoro core not downloaded');
          return;
        }

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);

        // Test different Kokoro voices (they all use the same core)
        final voices = [
          ('kokoro_af', 'American Female'),
          ('kokoro_am_adam', 'American Male (Adam)'),
          ('kokoro_bf_emma', 'British Female (Emma)'),
        ];

        TestLogger.log('Testing ${voices.length} Kokoro voices...');

        for (final (voiceId, voiceName) in voices) {
          final result = await routingEngine.synthesizeToWavFile(
            voiceId: voiceId,
            text: 'Hello, this is $voiceName speaking.',
            playbackRate: 1.0,
          );

          expect(result.file.existsSync(), isTrue);
          TestLogger.progress('✓ $voiceName ($voiceId): ${result.durationMs}ms');
        }

        TestLogger.success(' All Kokoro voices synthesized successfully');
      }, timeout: const Timeout(Duration(minutes: 3)));

      test('should benchmark Kokoro performance', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final kokoroCore = downloadState.cores['kokoro_core_v1'];

        if (!kokoroCore!.isReady) {
          TestLogger.log('⚠ Skipping benchmark test - Kokoro core not downloaded');
          return;
        }

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);
        const voiceId = 'kokoro_af';

        // Benchmark text of varying lengths
        final benchmarks = [
          ('short', 'Hello world.'),
          ('medium', 'This is a medium length sentence that should take a bit longer to synthesize.'),
          ('long', 'In a distant land, there lived a young adventurer who dreamed of exploring the uncharted territories beyond the great mountains. Each day, they would gaze at the peaks and wonder what mysteries awaited.'),
        ];

        TestLogger.log('Kokoro Performance Benchmark');
        TestLogger.log('=' * 50);

        for (final (label, text) in benchmarks) {
          final startTime = DateTime.now();
          
          final result = await routingEngine.synthesizeToWavFile(
            voiceId: voiceId,
            text: text,
            playbackRate: 1.0,
          );

          final elapsed = DateTime.now().difference(startTime);
          final rtf = elapsed.inMilliseconds / result.durationMs;
          final charsPerSecond = (text.length * 1000) / elapsed.inMilliseconds;

          TestLogger.log('$label (${text.length} chars):');
          TestLogger.progress('- Audio: ${result.durationMs}ms');
          TestLogger.progress('- Synth: ${elapsed.inMilliseconds}ms');
          TestLogger.progress('- RTF: ${rtf.toStringAsFixed(2)}x');
          TestLogger.progress('- Speed: ${charsPerSecond.toStringAsFixed(0)} chars/sec');
        }
      }, timeout: const Timeout(Duration(minutes: 5)));
    });

    group('Supertonic Voice Synthesis', () {
      test('should report Supertonic download status', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final supertonicCore = downloadState.cores['supertonic_core_v1'];

        expect(supertonicCore, isNotNull);
        TestLogger.log('Supertonic core status: ${supertonicCore!.status}');

        if (supertonicCore.isReady) {
          TestLogger.success(' Supertonic is downloaded');
        } else {
          TestLogger.error(' Supertonic needs to be downloaded (status: ${supertonicCore.status})');
        }
      });

      test('should download Supertonic core if not present', () async {
        final downloadManager = container.read(granularDownloadManagerProvider.notifier);
        var downloadState = await container.read(granularDownloadManagerProvider.future);
        final supertonicCore = downloadState.cores['supertonic_core_v1'];

        if (!supertonicCore!.isReady) {
          TestLogger.log('Downloading Supertonic core model...');
          await downloadManager.downloadCore('supertonic_core_v1');

          // Wait for download to complete (poll state)
          var attempts = 0;
          const maxAttempts = 300; // 5 minutes max
          while (attempts < maxAttempts) {
            await Future.delayed(const Duration(seconds: 1));
            downloadState = await container.read(granularDownloadManagerProvider.future);
            final core = downloadState.cores['supertonic_core_v1']!;

            if (core.isReady) {
              TestLogger.success(' Download complete!');
              break;
            } else if (core.isFailed) {
              fail('Download failed: ${core.error}');
            }

            if (core.progress > 0) {
              TestLogger.progress('Downloading: ${(core.progress * 100).toStringAsFixed(1)}%');
            }
            attempts++;
          }

          if (attempts >= maxAttempts) {
            fail('Download timed out after ${maxAttempts}s');
          }
        } else {
          TestLogger.success(' Supertonic already downloaded, skipping download');
        }

        // Verify core directory exists with expected files
        final paths = await container.read(appPathsProvider.future);
        final coreDir = Directory('${paths.voiceAssetsDir.path}/supertonic/supertonic_core_v1/supertonic/onnx');
        expect(await coreDir.exists(), isTrue, reason: 'Core ONNX directory should exist');

        // Supertonic models have: text_encoder.onnx, duration_predictor.onnx, vector_estimator.onnx, vocoder.onnx, unicode_indexer.json
        final textEncoderFile = File('${coreDir.path}/text_encoder.onnx');
        final durationPredictorFile = File('${coreDir.path}/duration_predictor.onnx');
        final vectorEstimatorFile = File('${coreDir.path}/vector_estimator.onnx');
        final vocoderFile = File('${coreDir.path}/vocoder.onnx');
        final unicodeIndexerFile = File('${coreDir.path}/unicode_indexer.json');

        expect(await textEncoderFile.exists(), isTrue, reason: 'text_encoder.onnx should exist');
        expect(await durationPredictorFile.exists(), isTrue, reason: 'duration_predictor.onnx should exist');
        expect(await vectorEstimatorFile.exists(), isTrue, reason: 'vector_estimator.onnx should exist');
        expect(await vocoderFile.exists(), isTrue, reason: 'vocoder.onnx should exist');
        expect(await unicodeIndexerFile.exists(), isTrue, reason: 'unicode_indexer.json should exist');

        TestLogger.success(' Supertonic model files verified');
        TestLogger.progress('- text_encoder.onnx: ${await textEncoderFile.length()} bytes');
        TestLogger.progress('- duration_predictor.onnx: ${await durationPredictorFile.length()} bytes');
        TestLogger.progress('- vector_estimator.onnx: ${await vectorEstimatorFile.length()} bytes');
        TestLogger.progress('- vocoder.onnx: ${await vocoderFile.length()} bytes');
        TestLogger.progress('- unicode_indexer.json: ${await unicodeIndexerFile.length()} bytes');
      }, timeout: const Timeout(Duration(minutes: 10)));

      test('should synthesize text with Supertonic', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final supertonicCore = downloadState.cores['supertonic_core_v1'];

        if (!supertonicCore!.isReady) {
          TestLogger.log('⚠ Skipping Supertonic synthesis test - core not downloaded');
          TestLogger.progress('Run the download test first or download via the app');
          return;
        }

        // Verify model directory exists
        final paths = await container.read(appPathsProvider.future);
        final coreDir = Directory('${paths.voiceAssetsDir.path}/supertonic/supertonic_core_v1/supertonic/onnx');
        expect(await coreDir.exists(), isTrue, reason: 'Core directory should exist');

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);
        final supertonicAdapter = await container.read(supertonicAdapterProvider.future);
        expect(supertonicAdapter, isNotNull, reason: 'Supertonic adapter should be available');

        const testText = 'Hello, this is a test of the Supertonic text to speech engine.';
        const voiceId = 'supertonic_m1';

        TestLogger.log('Synthesizing with Supertonic: "$testText"');
        TestLogger.log('Voice: $voiceId');

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
        final rtf = elapsed.inMilliseconds / result.durationMs;
        TestLogger.success(' Supertonic synthesis complete!');
        TestLogger.progress('- Duration: ${result.durationMs}ms');
        TestLogger.progress('- File size: ${(fileSize / 1024).toStringAsFixed(1)} KB');
        TestLogger.progress('- Processing time: ${elapsed.inMilliseconds}ms');
        TestLogger.progress('- Real-time factor: ${rtf.toStringAsFixed(2)}x');
      }, timeout: const Timeout(Duration(minutes: 5)));

      test('should synthesize with multiple Supertonic voices', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final supertonicCore = downloadState.cores['supertonic_core_v1'];

        if (!supertonicCore!.isReady) {
          TestLogger.log('⚠ Skipping multi-voice test - Supertonic core not downloaded');
          return;
        }

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);

        // Test different Supertonic voices
        final voices = [
          ('supertonic_m1', 'Male 1'),
          ('supertonic_m2', 'Male 2'),
          ('supertonic_f1', 'Female 1'),
        ];

        TestLogger.log('Testing ${voices.length} Supertonic voices...');

        for (final (voiceId, voiceName) in voices) {
          final result = await routingEngine.synthesizeToWavFile(
            voiceId: voiceId,
            text: 'Hello, this is $voiceName speaking.',
            playbackRate: 1.0,
          );

          expect(result.file.existsSync(), isTrue);
          TestLogger.progress('✓ $voiceName ($voiceId): ${result.durationMs}ms');
        }

        TestLogger.success(' All Supertonic voices synthesized successfully');
      }, timeout: const Timeout(Duration(minutes: 5)));

      test('should benchmark Supertonic performance', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final supertonicCore = downloadState.cores['supertonic_core_v1'];

        if (!supertonicCore!.isReady) {
          TestLogger.log('⚠ Skipping benchmark test - Supertonic core not downloaded');
          return;
        }

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);
        const voiceId = 'supertonic_m1';

        // Benchmark text of varying lengths
        final benchmarks = [
          ('short', 'Hello world.'),
          ('medium', 'This is a medium length sentence that should take a bit longer to synthesize.'),
          ('long', 'In a distant land, there lived a young adventurer who dreamed of exploring the uncharted territories beyond the great mountains. Each day, they would gaze at the peaks and wonder what mysteries awaited.'),
        ];

        TestLogger.log('Supertonic Performance Benchmark');
        TestLogger.log('=' * 50);

        for (final (label, text) in benchmarks) {
          final startTime = DateTime.now();
          
          final result = await routingEngine.synthesizeToWavFile(
            voiceId: voiceId,
            text: text,
            playbackRate: 1.0,
          );

          final elapsed = DateTime.now().difference(startTime);
          final rtf = elapsed.inMilliseconds / result.durationMs;
          final charsPerSecond = (text.length * 1000) / elapsed.inMilliseconds;

          TestLogger.log('$label (${text.length} chars):');
          TestLogger.progress('- Audio: ${result.durationMs}ms');
          TestLogger.progress('- Synth: ${elapsed.inMilliseconds}ms');
          TestLogger.progress('- RTF: ${rtf.toStringAsFixed(2)}x');
          TestLogger.progress('- Speed: ${charsPerSecond.toStringAsFixed(0)} chars/sec');
        }
      }, timeout: const Timeout(Duration(minutes: 10)));
    });

    group('Voice Readiness Checks', () {
      test('should correctly report voice readiness for all voices', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);

        TestLogger.log('\nVoice Readiness Report:');
        TestLogger.log('=' * 50);

        for (final voice in downloadState.voices.values) {
          final isReady = voice.allCoresReady(downloadState.cores);
          final status = isReady ? '✓ Ready' : '✗ Not ready';
          TestLogger.progress('${voice.displayName}: $status');

          if (!isReady) {
            final missingCores = voice.getMissingCoreIds(downloadState.cores);
            TestLogger.progress('  Missing: ${missingCores.join(', ')}');
          }
        }

        TestLogger.log('=' * 50);
        TestLogger.log('Ready voices: ${downloadState.readyVoiceCount}/${downloadState.totalVoiceCount}');
      });
    });

    group('Edge Cases', () {
      test('should handle empty text gracefully', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        if (!piperAlanCore!.isReady) {
          TestLogger.log('⚠ Skipping edge case test - Piper Alan not downloaded');
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
          TestLogger.log('Empty text synthesis returned: ${result.durationMs}ms');
        } catch (e) {
          TestLogger.log('Empty text threw expected error: $e');
          // This is acceptable behavior
        }
      });

      test('should handle very long text', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        if (!piperAlanCore!.isReady) {
          TestLogger.log('⚠ Skipping long text test - Piper Alan not downloaded');
          return;
        }

        final routingEngine = await container.read(ttsRoutingEngineProvider.future);

        // Generate long text
        final longText = List.generate(20, (i) =>
            'This is sentence number ${i + 1} in a very long paragraph. '
        ).join();

        TestLogger.log('Synthesizing long text (${longText.length} chars)...');

        final startTime = DateTime.now();
        final result = await routingEngine.synthesizeToWavFile(
          voiceId: 'piper:en_GB-alan-medium',
          text: longText,
          playbackRate: 1.0,
        );
        final elapsed = DateTime.now().difference(startTime);

        expect(result.file.existsSync(), isTrue);
        TestLogger.success(' Long text synthesis complete');
        TestLogger.progress('- Duration: ${result.durationMs}ms');
        TestLogger.progress('- Processing time: ${elapsed.inMilliseconds}ms');
      }, timeout: const Timeout(Duration(minutes: 5)));

      test('should handle special characters', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        if (!piperAlanCore!.isReady) {
          TestLogger.log('⚠ Skipping special chars test - Piper Alan not downloaded');
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
        TestLogger.success(' Special characters handled correctly');
      });
    });

    group('Performance', () {
      test('should benchmark synthesis speed', () async {
        final downloadState = await container.read(granularDownloadManagerProvider.future);
        final piperAlanCore = downloadState.cores['piper_alan_gb_v1'];

        if (!piperAlanCore!.isReady) {
          TestLogger.log('⚠ Skipping benchmark - Piper Alan not downloaded');
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

        TestLogger.log('\nBenchmark Results ($iterations iterations):');
        TestLogger.log('=' * 50);
        TestLogger.progress('Average processing time: ${avgTime.toStringAsFixed(1)}ms');
        TestLogger.progress('Average audio duration: ${avgDuration.toStringAsFixed(1)}ms');
        TestLogger.progress('Real-time factor: ${rtf.toStringAsFixed(2)}x');
        TestLogger.progress(rtf < 1.0 ? '✓ Faster than real-time!' : '✗ Slower than real-time');
        TestLogger.log('=' * 50);
      }, timeout: const Timeout(Duration(minutes: 3)));
    });
  });
}
