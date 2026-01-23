import Foundation
import SherpaOnnxCApi

/// Supertonic TTS engine service.
/// Uses sherpa-onnx for VITS-based synthesis.
class SupertonicTtsService: TtsServiceProtocol {
    let engineType: NativeEngineType = .supertonic
    
    private var inference = SupertonicSherpaInference()
    private var loadedVoices: [String: VoiceInfo] = [:]
    private let lock = NSLock()
    private let synthesisCounter = SynthesisCounter()
    
    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return inference.isModelLoaded
    }
    
    func loadCore(corePath: String, configPath: String?) async throws {
        lock.lock()
        defer { lock.unlock() }
        
        NSLog("[SupertonicTtsService] loadCore called with corePath: %@", corePath)
        
        guard FileManager.default.fileExists(atPath: corePath) else {
            NSLog("[SupertonicTtsService] ERROR: corePath does not exist: %@", corePath)
            throw TtsError.modelNotLoaded
        }
        
        // Load the model if not already loaded
        if !inference.isModelLoaded {
            // Find model.onnx in onnx subdirectory
            let onnxDir = (corePath as NSString).appendingPathComponent("onnx")
            let modelPath = (onnxDir as NSString).appendingPathComponent("model.onnx")
            let tokensPath = (onnxDir as NSString).appendingPathComponent("tokens.txt")
            
            NSLog("[SupertonicTtsService] Looking for model at: %@", modelPath)
            NSLog("[SupertonicTtsService] Looking for tokens at: %@", tokensPath)
            
            guard FileManager.default.fileExists(atPath: modelPath) else {
                NSLog("[SupertonicTtsService] ERROR: model.onnx not found at: %@", modelPath)
                // List contents of corePath to debug
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: corePath) {
                    NSLog("[SupertonicTtsService] Contents of corePath: %@", contents)
                }
                if FileManager.default.fileExists(atPath: onnxDir) {
                    if let onnxContents = try? FileManager.default.contentsOfDirectory(atPath: onnxDir) {
                        NSLog("[SupertonicTtsService] Contents of onnx dir: %@", onnxContents)
                    }
                } else {
                    NSLog("[SupertonicTtsService] onnx subdirectory does not exist")
                }
                throw TtsError.modelNotLoaded
            }
            
            guard FileManager.default.fileExists(atPath: tokensPath) else {
                NSLog("[SupertonicTtsService] ERROR: tokens.txt not found at: %@", tokensPath)
                throw TtsError.invalidInput("Tokens file not found at: \(tokensPath)")
            }
            
            // Find espeak-ng-data directory if exists
            let dataDir = (onnxDir as NSString).appendingPathComponent("espeak-ng-data")
            let dataDirPath = FileManager.default.fileExists(atPath: dataDir) ? dataDir : nil
            
            NSLog("[SupertonicTtsService] Loading model...")
            try inference.loadModel(modelPath: modelPath, tokensPath: tokensPath, dataDir: dataDirPath)
            NSLog("[SupertonicTtsService] Model loaded successfully from: %@", modelPath)
        } else {
            NSLog("[SupertonicTtsService] Core already loaded")
        }
    }
    
    func loadVoice(voiceId: String, modelPath: String, speakerId: Int?, configPath: String?) async throws {
        lock.lock()
        defer { lock.unlock() }
        
        // For Supertonic, all voices use the same model with different speakerIds
        // Just register the voice - model is loaded during loadCore
        loadedVoices[voiceId] = VoiceInfo(
            voiceId: voiceId,
            modelPath: modelPath,
            speakerId: speakerId,
            lastUsed: Date()
        )
        print("[SupertonicTtsService] Voice registered: \(voiceId) with speakerId: \(speakerId ?? 0)")
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
        print("[SupertonicTtsService] Cancel requested for: \(requestId)")
    }
    
    func unloadVoice(voiceId: String) {
        // Wait for active synthesis operations to complete
        _ = synthesisCounter.waitUntilIdle(timeoutMs: 5000)
        
        lock.lock()
        defer { lock.unlock() }
        loadedVoices.removeValue(forKey: voiceId)
        inference.unload()
        print("[SupertonicTtsService] Voice unloaded: \(voiceId)")
    }
    
    func unloadAll() {
        // Wait for active synthesis operations to complete
        _ = synthesisCounter.waitUntilIdle(timeoutMs: 5000)
        
        lock.lock()
        defer { lock.unlock() }
        loadedVoices.removeAll()
        inference.unload()
        print("[SupertonicTtsService] All resources unloaded")
    }
}
