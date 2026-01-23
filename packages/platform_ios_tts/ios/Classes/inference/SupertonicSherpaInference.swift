import Foundation
import SherpaOnnxCApi

/// Supertonic TTS inference using sherpa-onnx VITS model.
/// Supertonic models are VITS-based similar to Piper.
class SupertonicSherpaInference {
    
    private var tts: SherpaOnnxOfflineTtsWrapper?
    private var currentModelPath: String?
    private var currentTokensPath: String?
    private var sampleRate: Int32 = 24000  // Supertonic default
    
    var isModelLoaded: Bool {
        return tts != nil
    }
    
    /// Load a Supertonic VITS model.
    /// - Parameters:
    ///   - modelPath: Path to the .onnx model file
    ///   - tokensPath: Path to the tokens.txt file
    ///   - dataDir: Optional path to espeak-ng-data directory
    func loadModel(modelPath: String, tokensPath: String, dataDir: String? = nil) throws {
        // Unload any existing model
        unload()
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TtsError.modelNotLoaded
        }
        
        guard FileManager.default.fileExists(atPath: tokensPath) else {
            throw TtsError.invalidInput("Tokens file not found: \(tokensPath)")
        }
        
        // Configure VITS model for Supertonic
        let vitsConfig = sherpaOnnxOfflineTtsVitsModelConfig(
            model: modelPath,
            tokens: tokensPath,
            dataDir: dataDir ?? "",
            noiseScale: 0.667,
            noiseScaleW: 0.8,
            lengthScale: 1.0
        )
        
        // Model config with VITS
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            vits: vitsConfig,
            numThreads: 2,
            provider: "coreml"  // Use CoreML for Metal acceleration
        )
        
        // TTS config
        var ttsConfig = sherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            maxNumSentences: 1
        )
        
        // Create TTS wrapper
        let wrapper = SherpaOnnxOfflineTtsWrapper(config: &ttsConfig)
        
        guard wrapper.tts != nil else {
            throw TtsError.modelNotLoaded
        }
        
        self.tts = wrapper
        self.currentModelPath = modelPath
        self.currentTokensPath = tokensPath
        
        print("[SupertonicSherpaInference] Model loaded: \(modelPath)")
    }
    
    /// Synthesize text to audio samples.
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - speakerId: Speaker ID for multi-speaker models (default 0)
    ///   - speed: Speech speed multiplier (1.0 = normal)
    /// - Returns: Tuple of (samples, sampleRate)
    func synthesize(text: String, speakerId: Int = 0, speed: Float = 1.0) throws -> (samples: [Float], sampleRate: Int) {
        guard let tts = tts else {
            throw TtsError.modelNotLoaded
        }
        
        let audio = tts.generate(text: text, sid: speakerId, speed: speed)
        
        let samples = audio.samples
        let rate = Int(audio.sampleRate)
        
        if samples.isEmpty {
            throw TtsError.synthesisFailure("No audio generated")
        }
        
        return (samples, rate)
    }
    
    /// Unload the model and free resources.
    func unload() {
        tts = nil
        currentModelPath = nil
        currentTokensPath = nil
        print("[SupertonicSherpaInference] Model unloaded")
    }
}
