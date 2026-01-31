import Foundation
import SherpaOnnxCApi

/// Piper TTS inference using sherpa-onnx VITS model.
/// Piper models are VITS-based and use sherpa-onnx's VITS TTS API.
class PiperSherpaInference {
    
    private var tts: SherpaOnnxOfflineTtsWrapper?
    private var currentModelPath: String?
    private var currentTokensPath: String?
    private var sampleRate: Int32 = 22050  // Piper default
    
    var isModelLoaded: Bool {
        return tts != nil
    }
    
    /// Determine optimal thread count based on device CPU cores.
    /// Piper is lighter than Kokoro and benefits from threads on most devices.
    static func getOptimalThreadCount() -> Int32 {
        let cpuCores = ProcessInfo.processInfo.processorCount
        switch cpuCores {
        case 8...: return 4  // High-end devices: use 4 threads
        case 6..<8: return 3  // Mid-range: use 3 threads
        case 4..<6: return 2  // Budget: use 2 threads
        default: return 1     // Low-end: single thread
        }
    }
    
    /// Load a Piper VITS model.
    /// - Parameters:
    ///   - modelPath: Path to the .onnx model file
    ///   - tokensPath: Path to the tokens.txt file (espeak phonemes)
    ///   - dataDir: Optional path to espeak-ng-data directory
    ///   - numThreads: Optional thread count override (nil = auto-detect)
    func loadModel(modelPath: String, tokensPath: String, dataDir: String? = nil, numThreads: Int32? = nil) throws {
        // Unload any existing model
        unload()
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TtsError.modelNotLoaded
        }
        
        guard FileManager.default.fileExists(atPath: tokensPath) else {
            throw TtsError.invalidInput("Tokens file not found: \(tokensPath)")
        }
        
        // Use configured threads or auto-detect optimal count
        let threads = numThreads ?? Self.getOptimalThreadCount()
        print("[PiperSherpaInference] CPU cores: \(ProcessInfo.processInfo.processorCount), using \(threads) threads")
        
        // Configure VITS model for Piper
        let vitsConfig = sherpaOnnxOfflineTtsVitsModelConfig(
            model: modelPath,
            tokens: tokensPath,
            dataDir: dataDir ?? "",
            noiseScale: 0.667,
            noiseScaleW: 0.8,
            lengthScale: 1.0
        )
        
        // Model config with VITS
        // Use CPU provider to avoid memory pressure when CoreML is used for Supertonic
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            vits: vitsConfig,
            numThreads: Int(threads),
            provider: "cpu"  // Use CPU to avoid CoreML memory conflicts with Supertonic
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
        
        print("[PiperSherpaInference] Model loaded: \(modelPath)")
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
        print("[PiperSherpaInference] Model unloaded")
    }
}
