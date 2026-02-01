import Foundation

/// Supertonic TTS engine service.
/// Uses ONNX Runtime for 4-stage pipeline synthesis (matches official Supertonic SDK).
class SupertonicTtsService: TtsServiceProtocol {
    let engineType: NativeEngineType = .supertonic
    
    private var onnxInference = SupertonicOnnxInference()
    private var loadedVoices: [String: VoiceInfo] = [:]
    private let lock = NSLock()
    private let synthesisCounter = SynthesisCounter()
    
    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return onnxInference.isModelLoaded
    }
    
    func loadCore(corePath: String, configPath: String?) async throws {
        // Thread logging: loadCore entry
        NSLog("[THREAD] SupertonicTtsService.loadCore ENTRY: isMainThread=%@, thread=%@", 
              Thread.isMainThread ? "YES" : "NO", 
              Thread.current.description)
        NSLog("[SupertonicTtsService] loadCore called with corePath: %@", corePath)
        
        // Check if already loaded (quick check without heavy work)
        lock.lock()
        let alreadyLoaded = onnxInference.isModelLoaded
        lock.unlock()
        
        if alreadyLoaded {
            NSLog("[SupertonicTtsService] ONNX models already loaded")
            return
        }
        
        // Load ONNX models on a background thread
        let inference = self.onnxInference
        let path = corePath
        try await Task.detached(priority: .userInitiated) {
            // Thread logging: Inside Task.detached for model loading
            NSLog("[THREAD] SupertonicTtsService.loadCore Task.detached: isMainThread=%@, thread=%@", 
                  Thread.isMainThread ? "YES" : "NO", 
                  Thread.current.description)
            NSLog("[SupertonicTtsService] Loading ONNX models from background thread: %@", path)
            try inference.loadFromDirectory(path)
            NSLog("[SupertonicTtsService] ONNX models loaded successfully")
        }.value
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
        NSLog("[SupertonicTtsService] Voice registered: %@ with speakerId: %d", voiceId, speakerId ?? 0)
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
        
        // Thread logging: Entry point (should be background from PlatformIosTtsPlugin)
        NSLog("[THREAD] SupertonicTtsService.synthesize ENTRY: isMainThread=%@, thread=%@", 
              Thread.isMainThread ? "YES" : "NO", 
              Thread.current.description)
        
        NSLog("[SupertonicTtsService] Synthesizing with ONNX: voiceId=%@, speakerId=%d, text length=%d", voiceId, speakerId ?? 0, text.count)
        NSLog("[SupertonicTtsService] isModelLoaded=%@", onnxInference.isModelLoaded ? "YES" : "NO")
        
        // Run synthesis on background thread with lower priority to avoid UI contention
        let inference = self.onnxInference
        let (samples, sampleRate, elapsed) = try await Task.detached(priority: .utility) {
            // Thread logging: Inside utility priority Task (should be background)
            NSLog("[THREAD] SupertonicTtsService ONNX inference: isMainThread=%@, thread=%@", 
                  Thread.isMainThread ? "YES" : "NO", 
                  Thread.current.description)
            
            let startTime = CFAbsoluteTimeGetCurrent()
            let (samples, sampleRate) = try inference.synthesize(
                text: text,
                voiceName: voiceId,
                speakerId: speakerId ?? 0,
                speed: Float(speed)
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return (samples, sampleRate, elapsed)
        }.value
        
        // Thread logging: After Task.detached returns
        NSLog("[THREAD] SupertonicTtsService after ONNX: isMainThread=%@, thread=%@", 
              Thread.isMainThread ? "YES" : "NO", 
              Thread.current.description)
        
        NSLog("[SupertonicTtsService] Synthesis complete: %d samples at %dHz in %.2fs", samples.count, sampleRate, elapsed)
        
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
        NSLog("[SupertonicTtsService] Cancel requested for: %@", requestId)
    }
    
    func unloadVoice(voiceId: String) {
        // Wait for active synthesis operations to complete
        _ = synthesisCounter.waitUntilIdle(timeoutMs: 5000)
        
        lock.lock()
        defer { lock.unlock() }
        loadedVoices.removeValue(forKey: voiceId)
        onnxInference.unload()
        NSLog("[SupertonicTtsService] Voice unloaded: %@", voiceId)
    }
    
    func unloadAll() {
        // Wait for active synthesis operations to complete
        _ = synthesisCounter.waitUntilIdle(timeoutMs: 5000)
        
        lock.lock()
        defer { lock.unlock() }
        loadedVoices.removeAll()
        onnxInference.unload()
        NSLog("[SupertonicTtsService] All resources unloaded")
    }
}
