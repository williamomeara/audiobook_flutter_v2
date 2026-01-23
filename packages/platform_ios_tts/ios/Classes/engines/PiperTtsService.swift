import Foundation
import SherpaOnnxCApi

/// Piper TTS engine service.
/// Uses sherpa-onnx for VITS-based synthesis.
class PiperTtsService: TtsServiceProtocol {
    let engineType: NativeEngineType = .piper
    
    private var inference = PiperSherpaInference()
    private var loadedVoices: [String: VoiceInfo] = [:]
    private let lock = NSLock()
    private let synthesisCounter = SynthesisCounter()
    
    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return inference.isModelLoaded
    }
    
    func loadCore(corePath: String, configPath: String?) async throws {
        // For Piper, core loading is per-voice (each voice has its own ONNX model)
        // This method can be used to validate the base path or pre-load shared resources
        lock.lock()
        defer { lock.unlock() }
        
        guard FileManager.default.fileExists(atPath: corePath) else {
            throw TtsError.modelNotLoaded
        }
        
        print("[PiperTtsService] Core path validated: \(corePath)")
    }
    
    func loadVoice(voiceId: String, modelPath: String, speakerId: Int?, configPath: String?) async throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TtsError.voiceNotLoaded(voiceId)
        }
        
        // Find tokens file (should be in same directory or specified in config)
        let modelDir = (modelPath as NSString).deletingLastPathComponent
        let tokensPath = (modelDir as NSString).appendingPathComponent("tokens.txt")
        
        guard FileManager.default.fileExists(atPath: tokensPath) else {
            throw TtsError.invalidInput("Tokens file not found at: \(tokensPath)")
        }
        
        // Find espeak-ng-data directory if exists
        let dataDir = (modelDir as NSString).appendingPathComponent("espeak-ng-data")
        let dataDirPath = FileManager.default.fileExists(atPath: dataDir) ? dataDir : nil
        
        // Load the model
        try inference.loadModel(modelPath: modelPath, tokensPath: tokensPath, dataDir: dataDirPath)
        
        loadedVoices[voiceId] = VoiceInfo(
            voiceId: voiceId,
            modelPath: modelPath,
            speakerId: speakerId,
            lastUsed: Date()
        )
        print("[PiperTtsService] Voice loaded: \(voiceId)")
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
        print("[PiperTtsService] Cancel requested for: \(requestId)")
    }
    
    func unloadVoice(voiceId: String) {
        // Wait for active synthesis operations to complete
        _ = synthesisCounter.waitUntilIdle(timeoutMs: 5000)
        
        lock.lock()
        defer { lock.unlock() }
        loadedVoices.removeValue(forKey: voiceId)
        inference.unload()
        print("[PiperTtsService] Voice unloaded: \(voiceId)")
    }
    
    func unloadAll() {
        // Wait for active synthesis operations to complete
        _ = synthesisCounter.waitUntilIdle(timeoutMs: 5000)
        
        lock.lock()
        defer { lock.unlock() }
        loadedVoices.removeAll()
        inference.unload()
        print("[PiperTtsService] All resources unloaded")
    }
}
