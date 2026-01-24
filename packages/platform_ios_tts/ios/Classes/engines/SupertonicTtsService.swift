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
        lock.lock()
        defer { lock.unlock() }
        
        NSLog("[SupertonicTtsService] loadCore called with corePath: %@", corePath)
        
        // Check if already loaded
        if coremlInference.isModelLoaded {
            NSLog("[SupertonicTtsService] CoreML models already loaded")
            return
        }
        
        // Load CoreML models from bundle
        if corePath == Self.bundledCoreMLMarker {
            NSLog("[SupertonicTtsService] Loading bundled CoreML models...")
            try coremlInference.loadFromBundle(corePath)
            NSLog("[SupertonicTtsService] CoreML models loaded successfully")
        } else {
            // Legacy path - not supported for iOS CoreML
            NSLog("[SupertonicTtsService] ERROR: Non-bundled CoreML not supported. Use __BUNDLED_COREML__ marker.")
            throw TtsError.modelNotLoaded
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
        
        // Synthesize using CoreML 4-stage pipeline
        let startTime = CFAbsoluteTimeGetCurrent()
        let (samples, sampleRate) = try coremlInference.synthesize(
            text: text,
            voiceName: voiceId,
            speakerId: speakerId ?? 0,
            speed: Float(speed)
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
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
