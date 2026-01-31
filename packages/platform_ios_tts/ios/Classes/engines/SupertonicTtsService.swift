import Foundation
import CoreML

/// Supertonic TTS engine service.
/// Uses CoreML for 4-stage pipeline synthesis (bundled models).
class SupertonicTtsService: TtsServiceProtocol {
    let engineType: NativeEngineType = .supertonic
    
    private var coremlInference = SupertonicCoreMLInference()
    private var loadedVoices: [String: VoiceInfo] = [:]
    private let lock = NSLock()
    private let synthesisCounter = SynthesisCounter()
    
    /// Marker path indicating bundled CoreML models should be used
    private static let bundledCoreMLMarker = "__BUNDLED_COREML__"
    
    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return coremlInference.isModelLoaded
    }
    
    func loadCore(corePath: String, configPath: String?) async throws {
        NSLog("[SupertonicTtsService] loadCore called with corePath: %@", corePath)
        
        // Check if already loaded (quick check without heavy work)
        lock.lock()
        let alreadyLoaded = coremlInference.isModelLoaded
        lock.unlock()
        
        if alreadyLoaded {
            NSLog("[SupertonicTtsService] CoreML models already loaded")
            return
        }
        
        // Load CoreML models on a background thread to avoid blocking UI
        // CoreML model loading is CPU-intensive and should not run on main thread
        let inference = self.coremlInference
        let path = corePath
        try await Task.detached(priority: .userInitiated) {
            NSLog("[SupertonicTtsService] Loading CoreML models from background thread: %@", path)
            try inference.loadFromBundle(path)
            NSLog("[SupertonicTtsService] CoreML models loaded successfully")
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
        
        NSLog("[SupertonicTtsService] Synthesizing with CoreML: voiceId=%@, speakerId=%d, text length=%d", voiceId, speakerId ?? 0, text.count)
        NSLog("[SupertonicTtsService] isModelLoaded=%@", coremlInference.isModelLoaded ? "YES" : "NO")
        
        // Run synthesis on background thread to avoid blocking UI
        let inference = self.coremlInference
        let (samples, sampleRate, elapsed) = try await Task.detached(priority: .userInitiated) {
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
        coremlInference.unload()
        NSLog("[SupertonicTtsService] Voice unloaded: %@", voiceId)
    }
    
    func unloadAll() {
        // Wait for active synthesis operations to complete
        _ = synthesisCounter.waitUntilIdle(timeoutMs: 5000)
        
        lock.lock()
        defer { lock.unlock() }
        loadedVoices.removeAll()
        coremlInference.unload()
        NSLog("[SupertonicTtsService] All resources unloaded")
    }
}
