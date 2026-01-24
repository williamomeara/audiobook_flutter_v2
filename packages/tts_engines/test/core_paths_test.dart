import 'dart:io';

import 'package:test/test.dart';
import 'package:tts_engines/src/core_paths.dart';

void main() {
  group('CorePaths', () {
    late Directory tempDir;
    late CorePaths corePaths;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('core_paths_test_');
      corePaths = CorePaths(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('getEngineDirectory', () {
      test('returns correct path for kokoro', () {
        final dir = corePaths.getEngineDirectory('kokoro');
        expect(dir.path, equals('${tempDir.path}/kokoro'));
      });

      test('returns correct path for piper', () {
        final dir = corePaths.getEngineDirectory('piper');
        expect(dir.path, equals('${tempDir.path}/piper'));
      });

      test('returns correct path for supertonic', () {
        final dir = corePaths.getEngineDirectory('supertonic');
        expect(dir.path, equals('${tempDir.path}/supertonic'));
      });
    });

    group('getCoreDirectory', () {
      test('returns correct path for kokoro core', () {
        final dir = corePaths.getCoreDirectory('kokoro', 'kokoro_core_v1');
        expect(dir.path, equals('${tempDir.path}/kokoro/kokoro_core_v1'));
      });

      test('returns correct path for piper voice core', () {
        final dir = corePaths.getCoreDirectory('piper', 'piper_jenny_v1');
        expect(dir.path, equals('${tempDir.path}/piper/piper_jenny_v1'));
      });

      test('returns correct path for supertonic core', () {
        final dir = corePaths.getCoreDirectory('supertonic', 'supertonic_core_v1');
        expect(dir.path, equals('${tempDir.path}/supertonic/supertonic_core_v1'));
      });
    });

    group('Kokoro-specific paths', () {
      test('getKokoroCoreDirectory returns default core path', () {
        final dir = corePaths.getKokoroCoreDirectory();
        expect(dir.path, equals('${tempDir.path}/kokoro/kokoro_core_v1'));
      });

      test('getKokoroCoreDirectory accepts custom coreId', () {
        final dir = corePaths.getKokoroCoreDirectory(coreId: 'kokoro_core_v2');
        expect(dir.path, equals('${tempDir.path}/kokoro/kokoro_core_v2'));
      });

      test('getKokoroVoicesFile returns correct path', () {
        final file = corePaths.getKokoroVoicesFile();
        expect(file.path, equals('${tempDir.path}/kokoro/kokoro_core_v1/voices.bin'));
      });

      test('getKokoroModelFile returns int8 model if available', () async {
        // Create the core directory
        final coreDir = corePaths.getKokoroCoreDirectory();
        await coreDir.create(recursive: true);
        
        // Create int8 model file
        final int8Model = File('${coreDir.path}/model.int8.onnx');
        await int8Model.writeAsString('mock model data');
        
        final result = await corePaths.getKokoroModelFile();
        expect(result?.path, equals(int8Model.path));
      });

      test('getKokoroModelFile returns full model if no int8 available', () async {
        // Create the core directory
        final coreDir = corePaths.getKokoroCoreDirectory();
        await coreDir.create(recursive: true);
        
        // Create only full model file
        final fullModel = File('${coreDir.path}/model.onnx');
        await fullModel.writeAsString('mock model data');
        
        final result = await corePaths.getKokoroModelFile();
        expect(result?.path, equals(fullModel.path));
      });

      test('getKokoroModelFile returns null if no model exists', () async {
        final result = await corePaths.getKokoroModelFile();
        expect(result, isNull);
      });
    });

    group('Piper-specific paths', () {
      test('getPiperVoiceDirectory returns correct path', () {
        final dir = corePaths.getPiperVoiceDirectory('piper_jenny_v1');
        expect(dir.path, equals('${tempDir.path}/piper/piper_jenny_v1'));
      });

      test('getPiperModelFile returns correct path', () {
        final file = corePaths.getPiperModelFile('piper_jenny_v1');
        expect(file.path, equals('${tempDir.path}/piper/piper_jenny_v1/model.onnx'));
      });
    });

    group('Supertonic-specific paths', () {
      test('getSupertonicSubdirectory returns platform-appropriate value', () {
        final subdir = corePaths.getSupertonicSubdirectory();
        // On test platform (Linux/macOS/Windows), should return Android value
        if (Platform.isIOS) {
          expect(subdir, equals('supertonic_coreml'));
        } else {
          expect(subdir, equals('supertonic'));
        }
      });

      test('getSupertonicCoreDirectory returns correct path', () {
        final dir = corePaths.getSupertonicCoreDirectory('supertonic_core_v1');
        final expectedSubdir = Platform.isIOS ? 'supertonic_coreml' : 'supertonic';
        expect(dir.path, equals('${tempDir.path}/supertonic/supertonic_core_v1/$expectedSubdir'));
      });

      test('getSupertonicModelPath returns platform-appropriate path', () {
        final path = corePaths.getSupertonicModelPath('supertonic_core_v1');
        if (Platform.isIOS) {
          expect(path, contains('supertonic_coreml'));
          expect(path, isNot(contains('onnx/model.onnx')));
        } else {
          expect(path, contains('onnx/model.onnx'));
        }
      });
    });

    group('Utility methods', () {
      test('isCoreAvailable returns false for non-existent core', () async {
        final available = await corePaths.isCoreAvailable('kokoro', 'kokoro_core_v1');
        expect(available, isFalse);
      });

      test('isCoreAvailable returns true for existing core', () async {
        // Create the core directory
        final coreDir = corePaths.getCoreDirectory('kokoro', 'kokoro_core_v1');
        await coreDir.create(recursive: true);
        
        final available = await corePaths.isCoreAvailable('kokoro', 'kokoro_core_v1');
        expect(available, isTrue);
      });

      test('getCoreIdForEngine returns correct values', () {
        expect(corePaths.getCoreIdForEngine('kokoro', 'any_voice'), 'kokoro_core_v1');
        expect(corePaths.getCoreIdForEngine('piper', 'any_voice'), isNull); // Needs voice-specific mapping
        expect(corePaths.getCoreIdForEngine('supertonic', 'any_voice'), isNotNull);
        expect(corePaths.getCoreIdForEngine('unknown', 'any_voice'), isNull);
      });

      test('getCoreIdForEngine handles case insensitivity', () {
        expect(corePaths.getCoreIdForEngine('KOKORO', 'any_voice'), 'kokoro_core_v1');
        expect(corePaths.getCoreIdForEngine('Kokoro', 'any_voice'), 'kokoro_core_v1');
      });
    });
  });
}
