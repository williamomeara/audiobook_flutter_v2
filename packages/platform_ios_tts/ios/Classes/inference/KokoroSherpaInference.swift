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
    
    /// Determine optimal thread count based on device CPU cores.
    /// Kokoro benefits from more threads (up to 4) on high-core devices.
    static func getOptimalThreadCount() -> Int32 {
        let cpuCores = ProcessInfo.processInfo.processorCount
        switch cpuCores {
        case 8...: return 4  // High-end devices: use 4 threads
        case 6..<8: return 3  // Mid-range: use 3 threads
        case 4..<6: return 2  // Budget: use 2 threads
        default: return 1     // Low-end: single thread
        }
    }
    
    /// Load a Kokoro model.
    /// - Parameters:
    ///   - modelPath: Path to the kokoro model.onnx file
    ///   - voicesPath: Path to the voices.bin file
    ///   - tokensPath: Path to the tokens.txt file
    ///   - dataDir: Optional path to data directory (for espeak-ng)
    ///   - numThreads: Optional thread count override (nil = auto-detect)
    func loadModel(modelPath: String, voicesPath: String, tokensPath: String, dataDir: String? = nil, numThreads: Int32? = nil) throws {
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
        
        // Use configured threads or auto-detect optimal count
        let threads = numThreads ?? Self.getOptimalThreadCount()
        print("[KokoroSherpaInference] CPU cores: \(ProcessInfo.processInfo.processorCount), using \(threads) threads")
        
        // Configure Kokoro model
        // For multi-lingual Kokoro v1.0+, specify English language
        let kokoroConfig = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: modelPath,
            voices: voicesPath,
            tokens: tokensPath,
            dataDir: dataDir ?? "",
            lengthScale: 1.0,
            lang: "en"  // Required for multi-lingual Kokoro >= v1.0
        )
        
        // Model config with Kokoro
        // Use CPU provider to keep memory footprint small
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            kokoro: kokoroConfig,
            numThreads: Int(threads),
            provider: "cpu"
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
