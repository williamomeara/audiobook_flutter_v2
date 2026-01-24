import Foundation
import SherpaOnnxCApi

/// Kokoro TTS engine service.
/// Uses sherpa-onnx's native Kokoro TTS support for inference.
class KokoroTtsService: TtsServiceProtocol {
    let engineType: NativeEngineType = .kokoro
    
    private var inference = KokoroSherpaInference()
    private var loadedVoices: [String: VoiceInfo] = [:]
    private let lock = NSLock()
    private let synthesisCounter = SynthesisCounter()
    
    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return inference.isModelLoaded
    }
    
    func loadCore(corePath: String, configPath: String?) async throws {
        // For Kokoro, the core model is loaded with voice
        lock.lock()
        defer { lock.unlock() }
        
        guard FileManager.default.fileExists(atPath: corePath) else {
            throw TtsError.modelNotLoaded
        }
        
        print("[KokoroTtsService] Core path validated: \(corePath)")
    }
    
    func loadVoice(voiceId: String, modelPath: String, speakerId: Int?, configPath: String?) async throws {
        lock.lock()
        defer { lock.unlock() }
        
        // modelPath is the directory containing the model files
        let modelDir = modelPath
        
        guard FileManager.default.fileExists(atPath: modelDir) else {
            throw TtsError.voiceNotLoaded(voiceId)
        }
        
        // Find the ONNX model file in the directory
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: modelDir) else {
            throw TtsError.invalidInput("Cannot read model directory: \(modelDir)")
        }
        
        // Find .onnx file (not .onnx.json)
        let onnxFile = contents.first { $0.hasSuffix(".onnx") && !$0.hasSuffix(".onnx.json") }
        guard let onnxFile = onnxFile else {
            throw TtsError.invalidInput("No ONNX model found in: \(modelDir)")
        }
        
        let fullModelPath = (modelDir as NSString).appendingPathComponent(onnxFile)
        
        // Kokoro requires: model.onnx, voices.bin, tokens.txt
        let voicesPath = (modelDir as NSString).appendingPathComponent("voices.bin")
        let tokensPath = (modelDir as NSString).appendingPathComponent("tokens.txt")
        
        guard FileManager.default.fileExists(atPath: voicesPath) else {
            throw TtsError.invalidInput("Voices file not found at: \(voicesPath)")
        }
        
        guard FileManager.default.fileExists(atPath: tokensPath) else {
            throw TtsError.invalidInput("Tokens file not found at: \(tokensPath)")
        }
        
        // Find espeak-ng-data directory if exists
        let dataDir = (modelDir as NSString).appendingPathComponent("espeak-ng-data")
        let dataDirPath = FileManager.default.fileExists(atPath: dataDir) ? dataDir : nil
        
        print("[KokoroTtsService] Loading model from: \(fullModelPath)")
        print("[KokoroTtsService] Voices file: \(voicesPath)")
        print("[KokoroTtsService] Tokens file: \(tokensPath)")
        print("[KokoroTtsService] Data dir: \(dataDirPath ?? "none")")
        
        // Load the model
        try inference.loadModel(
            modelPath: fullModelPath,
            voicesPath: voicesPath,
            tokensPath: tokensPath,
            dataDir: dataDirPath
        )
        
        loadedVoices[voiceId] = VoiceInfo(
            voiceId: voiceId,
            modelPath: fullModelPath,
            speakerId: speakerId,
            lastUsed: Date()
        )
        print("[KokoroTtsService] Voice loaded: \(voiceId)")
    }
    
    func synthesize(text: String, voiceId: String, outputPath: String, speakerId: Int?, speed: Double) async throws -> SynthesizeResult {
        // Track active synthesis to prevent unload during operation
        synthesisCounter.increment()
        defer { synthesisCounter.decrement() }
        
        lock.lock()
        let voice = loadedVoices[voiceId]
        lock.unlock()
        
        guard voice != nil else {
            throw TtsError.voiceNotLoaded(voiceId)
        }
        
        guard !text.isEmpty else {
            throw TtsError.invalidInput("Text is empty")
        }
        
        // Synthesize using sherpa-onnx
        let (samples, sampleRate) = try inference.synthesize(
            text: text,
            speakerId: speakerId ?? 0,
            speed: Float(speed)
        )
        
        // Write WAV file
        try AudioConverter.writeWav(samples: samples, sampleRate: sampleRate, to: outputPath)
        
        let durationMs = AudioConverter.durationMs(sampleCount: samples.count, sampleRate: sampleRate)
        
        return SynthesizeResult(
            success: true,
            durationMs: durationMs,
            sampleRate: Int64(sampleRate),
            errorCode: .none,
            errorMessage: nil
        )
    }
    
    func cancelSynthesis(requestId: String) {
        print("[KokoroTtsService] Cancel requested for: \(requestId)")
    }
    
    func unloadVoice(voiceId: String) {
        // Wait for active synthesis operations to complete
        _ = synthesisCounter.waitUntilIdle(timeoutMs: 5000)
        
        lock.lock()
        defer { lock.unlock() }
        loadedVoices.removeValue(forKey: voiceId)
        inference.unload()
        print("[KokoroTtsService] Voice unloaded: \(voiceId)")
    }
    
    func unloadAll() {
        // Wait for active synthesis operations to complete
        _ = synthesisCounter.waitUntilIdle(timeoutMs: 5000)
        
        lock.lock()
        defer { lock.unlock() }
        loadedVoices.removeAll()
        inference.unload()
        print("[KokoroTtsService] All resources unloaded")
    }
}

/// Voice information stored in memory.
struct VoiceInfo {
    let voiceId: String
    let modelPath: String
    let speakerId: Int?
    var lastUsed: Date
}
