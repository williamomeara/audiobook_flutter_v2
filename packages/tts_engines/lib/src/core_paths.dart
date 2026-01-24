import 'dart:io';

/// Centralized path management for TTS model cores.
/// 
/// Provides consistent path resolution for all TTS engines, eliminating
/// duplicated path logic across adapters.
/// 
/// Directory structure:
/// ```
/// baseDir/
///   kokoro/
///     kokoro_core_v1/
///       model.onnx (or model.int8.onnx)
///       tokens.txt
///       espeak-ng-data/
///       voices.bin
///   piper/
///     {coreId}/
///       model.onnx
///       config.json
///   supertonic/
///     {coreId}/
///       supertonic/           (Android)
///         onnx/
///           text_encoder.onnx
///           duration_predictor.onnx
///           vector_estimator.onnx
///           vocoder.onnx
///       supertonic_coreml/    (iOS)
///         TextEncoder.mlmodelc
///         ...
/// ```
class CorePaths {
  final Directory baseDir;
  
  CorePaths(this.baseDir);
  
  /// Get the base directory for an engine type.
  Directory getEngineDirectory(String engineType) {
    return Directory('${baseDir.path}/$engineType');
  }
  
  /// Get the core directory for a specific engine and core ID.
  /// 
  /// For Kokoro, coreId is typically 'kokoro_core_v1'.
  /// For Piper, coreId is the voice-specific core ID.
  /// For Supertonic, coreId varies by platform.
  Directory getCoreDirectory(String engineType, String coreId) {
    return Directory('${baseDir.path}/$engineType/$coreId');
  }
  
  // --- Kokoro-specific paths ---
  
  /// Get the Kokoro core directory.
  Directory getKokoroCoreDirectory({String coreId = 'kokoro_core_v1'}) {
    return Directory('${baseDir.path}/kokoro/$coreId');
  }
  
  /// Get the path to the Kokoro model file.
  /// Returns the int8 model if available, otherwise the full model.
  Future<File?> getKokoroModelFile({String coreId = 'kokoro_core_v1'}) async {
    final coreDir = getKokoroCoreDirectory(coreId: coreId);
    
    // Prefer quantized model
    final int8Model = File('${coreDir.path}/model.int8.onnx');
    if (await int8Model.exists()) return int8Model;
    
    final fullModel = File('${coreDir.path}/model.onnx');
    if (await fullModel.exists()) return fullModel;
    
    return null;
  }
  
  /// Get the path to the Kokoro voices.bin file.
  File getKokoroVoicesFile({String coreId = 'kokoro_core_v1'}) {
    return File('${getKokoroCoreDirectory(coreId: coreId).path}/voices.bin');
  }
  
  // --- Piper-specific paths ---
  
  /// Get the Piper voice directory for a specific core ID.
  Directory getPiperVoiceDirectory(String coreId) {
    return Directory('${baseDir.path}/piper/$coreId');
  }
  
  /// Get the Piper model file for a specific core ID.
  File getPiperModelFile(String coreId) {
    return File('${getPiperVoiceDirectory(coreId).path}/model.onnx');
  }
  
  // --- Supertonic-specific paths ---
  
  /// Get the Supertonic core subdirectory name based on platform.
  String getSupertonicSubdirectory() {
    return Platform.isIOS ? 'supertonic_coreml' : 'supertonic';
  }
  
  /// Get the Supertonic core directory for a specific core ID.
  Directory getSupertonicCoreDirectory(String coreId) {
    final subdir = getSupertonicSubdirectory();
    return Directory('${baseDir.path}/supertonic/$coreId/$subdir');
  }
  
  /// Get the Supertonic model path.
  /// On Android, points to the ONNX model file.
  /// On iOS, points to the CoreML model directory.
  String getSupertonicModelPath(String coreId) {
    final coreDir = getSupertonicCoreDirectory(coreId);
    if (Platform.isIOS) {
      return coreDir.path;
    } else {
      return '${coreDir.path}/onnx/model.onnx';
    }
  }
  
  // --- Utility methods ---
  
  /// Check if a core is downloaded and available.
  Future<bool> isCoreAvailable(String engineType, String coreId) async {
    final coreDir = getCoreDirectory(engineType, coreId);
    return await coreDir.exists();
  }
  
  /// Get the core ID from a voice ID based on engine-specific mapping.
  /// 
  /// This is a convenience method - actual mapping may need engine-specific
  /// logic in the adapters.
  String? getCoreIdForEngine(String engineType, String voiceId) {
    switch (engineType.toLowerCase()) {
      case 'kokoro':
        // Kokoro uses a single shared core
        return 'kokoro_core_v1';
      case 'piper':
        // Piper needs voice-specific mapping (handled by VoiceIds)
        return null; // Let adapter handle this
      case 'supertonic':
        // Supertonic uses platform-specific core
        return Platform.isIOS ? 'supertonic_core_ios_v1' : 'supertonic_core_v1';
      default:
        return null;
    }
  }
}
