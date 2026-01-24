import Foundation

/// Protocol that all TTS engine services must implement.
protocol TtsServiceProtocol {
    /// The engine type this service handles.
    var engineType: NativeEngineType { get }
    
    /// Whether the engine is ready for synthesis.
    var isReady: Bool { get }
    
    /// Initialize the engine with core model files.
    func loadCore(corePath: String, configPath: String?) async throws
    
    /// Load a voice into memory.
    func loadVoice(voiceId: String, modelPath: String, speakerId: Int?, configPath: String?) async throws
    
    /// Synthesize text to a WAV file.
    func synthesize(text: String, voiceId: String, outputPath: String, speakerId: Int?, speed: Double) async throws -> SynthesizeResult
    
    /// Cancel an in-flight synthesis operation.
    func cancelSynthesis(requestId: String)
    
    /// Unload a specific voice.
    func unloadVoice(voiceId: String)
    
    /// Unload all resources.
    func unloadAll()
}

/// Thread-safe counter for tracking active synthesis operations.
/// Used to prevent unloading while synthesis is in progress.
class SynthesisCounter {
    private var count: Int = 0
    private let lock = NSLock()
    
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
    
    func decrement() {
        lock.lock()
        count -= 1
        lock.unlock()
    }
    
    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return count > 0
    }
    
    /// Wait until no active synthesis operations (with timeout).
    /// Returns true if all operations completed, false if timed out.
    func waitUntilIdle(timeoutMs: Int = 5000) -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            if !isActive {
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)  // 10ms polling
        }
        return !isActive
    }
}

/// TTS-related errors.
enum TtsError: Error, LocalizedError {
    case modelNotLoaded
    case voiceNotLoaded(String)
    case synthesisFailure(String)
    case invalidInput(String)
    case outOfMemory
    case cancelled
    case fileWriteError(String)
    case notImplemented
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "TTS model is not loaded"
        case .voiceNotLoaded(let voiceId):
            return "Voice '\(voiceId)' is not loaded"
        case .synthesisFailure(let msg):
            return "Synthesis failed: \(msg)"
        case .invalidInput(let msg):
            return "Invalid input: \(msg)"
        case .outOfMemory:
            return "Out of memory"
        case .cancelled:
            return "Operation was cancelled"
        case .fileWriteError(let path):
            return "Failed to write file: \(path)"
        case .notImplemented:
            return "This feature is not yet implemented"
        }
    }
    
    var nativeErrorCode: NativeErrorCode {
        switch self {
        case .modelNotLoaded:
            return .modelMissing
        case .voiceNotLoaded:
            return .modelMissing
        case .synthesisFailure:
            return .inferenceFailed
        case .invalidInput:
            return .invalidInput
        case .outOfMemory:
            return .outOfMemory
        case .cancelled:
            return .cancelled
        case .fileWriteError:
            return .fileWriteError
        case .notImplemented:
            return .unknown
        }
    }
}
