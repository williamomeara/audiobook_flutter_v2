import Foundation
import SherpaOnnxCApi

/// Kokoro TTS inference using sherpa-onnx Kokoro model support.
/// Kokoro models use sherpa-onnx's native Kokoro TTS API.
class KokoroSherpaInference {
    
    private var tts: SherpaOnnxOfflineTtsWrapper?
    private var currentModelPath: String?
    private var currentVoicesPath: String?
    private var sampleRate: Int32 = 24000  // Kokoro default
    
    var isModelLoaded: Bool {
        return tts != nil
    }
    
    /// Load a Kokoro model.
    /// - Parameters:
    ///   - modelPath: Path to the kokoro model.onnx file
    ///   - voicesPath: Path to the voices.bin file
    ///   - tokensPath: Path to the tokens.txt file
    ///   - dataDir: Optional path to data directory (for espeak-ng)
    func loadModel(modelPath: String, voicesPath: String, tokensPath: String, dataDir: String? = nil) throws {
        // Unload any existing model
        unload()
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TtsError.modelNotLoaded
        }
        
        guard FileManager.default.fileExists(atPath: voicesPath) else {
            throw TtsError.invalidInput("Voices file not found: \(voicesPath)")
        }
        
        guard FileManager.default.fileExists(atPath: tokensPath) else {
            throw TtsError.invalidInput("Tokens file not found: \(tokensPath)")
        }
        
        // Configure Kokoro model
        let kokoroConfig = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: modelPath,
            voices: voicesPath,
            tokens: tokensPath,
            dataDir: dataDir ?? "",
            lengthScale: 1.0
        )
        
        // Model config with Kokoro
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            kokoro: kokoroConfig,
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
        self.currentVoicesPath = voicesPath
        
        print("[KokoroSherpaInference] Model loaded: \(modelPath)")
    }
    
    /// Synthesize text to audio samples.
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - speakerId: Speaker ID for voice selection
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
        currentVoicesPath = nil
        print("[KokoroSherpaInference] Model unloaded")
    }
}
