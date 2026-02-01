import Flutter
import UIKit

public class PlatformIosTtsPlugin: NSObject, FlutterPlugin {
    private let ttsApiImpl = TtsNativeApiImpl()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PlatformIosTtsPlugin()
        
        // Set up Pigeon API handler
        TtsNativeApiSetup.setUp(
            binaryMessenger: registrar.messenger(),
            api: instance.ttsApiImpl
        )
    }
}

/// Implementation of TtsNativeApi that routes calls to engine-specific services.
class TtsNativeApiImpl: TtsNativeApi {
    private lazy var kokoroService = KokoroTtsService()
    private lazy var piperService = PiperTtsService()
    private lazy var supertonicService = SupertonicTtsService()
    
    private var activeRequests: [String: Bool] = [:]
    private let lock = NSLock()
    
    private func service(for engine: NativeEngineType) -> TtsServiceProtocol {
        switch engine {
        case .kokoro:
            return kokoroService
        case .piper:
            return piperService
        case .supertonic:
            return supertonicService
        }
    }
    
    // MARK: - TtsNativeApi Protocol
    
    func initEngine(request: InitEngineRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        // Thread logging: Entry point for initEngine
        NSLog("[THREAD] initEngine ENTRY: isMainThread=%@, thread=%@", 
              Thread.isMainThread ? "YES" : "NO", 
              Thread.current.description)
        
        Task.detached(priority: .userInitiated) { [self] in
            // Thread logging: Inside Task.detached
            NSLog("[THREAD] initEngine Task.detached: isMainThread=%@, thread=%@", 
                  Thread.isMainThread ? "YES" : "NO", 
                  Thread.current.description)
            
            do {
                let svc = service(for: request.engineType)
                try await svc.loadCore(corePath: request.corePath, configPath: request.configPath)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func loadVoice(request: LoadVoiceRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        // Thread logging: Entry point for loadVoice
        NSLog("[THREAD] loadVoice ENTRY: isMainThread=%@, thread=%@", 
              Thread.isMainThread ? "YES" : "NO", 
              Thread.current.description)
        
        Task.detached(priority: .userInitiated) { [self] in
            // Thread logging: Inside Task.detached
            NSLog("[THREAD] loadVoice Task.detached: isMainThread=%@, thread=%@", 
                  Thread.isMainThread ? "YES" : "NO", 
                  Thread.current.description)
            
            do {
                let svc = service(for: request.engineType)
                try await svc.loadVoice(
                    voiceId: request.voiceId,
                    modelPath: request.modelPath,
                    speakerId: request.speakerId.map { Int($0) },
                    configPath: request.configPath
                )
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func synthesize(request: SynthesizeRequest, completion: @escaping (Result<SynthesizeResult, Error>) -> Void) {
        // Thread logging: Entry point from Pigeon (should be main thread)
        NSLog("[THREAD] synthesize ENTRY: isMainThread=%@, thread=%@", 
              Thread.isMainThread ? "YES" : "NO", 
              Thread.current.description)
        
        lock.lock()
        activeRequests[request.requestId] = true
        lock.unlock()
        
        // Use Task.detached to run synthesis off the main thread
        // This creates an independent task that doesn't inherit the main actor context
        Task.detached(priority: .userInitiated) { [self] in
            // Thread logging: Inside Task.detached (should be background)
            NSLog("[THREAD] synthesize Task.detached: isMainThread=%@, thread=%@", 
                  Thread.isMainThread ? "YES" : "NO", 
                  Thread.current.description)
            
            do {
                let svc = service(for: request.engineType)
                
                // Check if cancelled before starting
                lock.lock()
                let isCancelled = activeRequests[request.requestId] == nil
                lock.unlock()
                
                if isCancelled {
                    completion(.success(SynthesizeResult(
                        success: false,
                        durationMs: nil,
                        sampleRate: nil,
                        errorCode: .cancelled,
                        errorMessage: "Synthesis was cancelled"
                    )))
                    return
                }
                
                let result = try await svc.synthesize(
                    text: request.text,
                    voiceId: request.voiceId,
                    outputPath: request.outputPath,
                    speakerId: request.speakerId.map { Int($0) },
                    speed: request.speed
                )
                
                lock.lock()
                activeRequests.removeValue(forKey: request.requestId)
                lock.unlock()
                
                completion(.success(result))
            } catch let error as TtsError {
                lock.lock()
                activeRequests.removeValue(forKey: request.requestId)
                lock.unlock()
                
                completion(.success(SynthesizeResult(
                    success: false,
                    durationMs: nil,
                    sampleRate: nil,
                    errorCode: error.nativeErrorCode,
                    errorMessage: error.localizedDescription
                )))
            } catch {
                lock.lock()
                activeRequests.removeValue(forKey: request.requestId)
                lock.unlock()
                
                completion(.failure(error))
            }
        }
    }
    
    func cancelSynthesis(requestId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        activeRequests.removeValue(forKey: requestId)
        lock.unlock()
        
        // Notify all services about cancellation
        kokoroService.cancelSynthesis(requestId: requestId)
        piperService.cancelSynthesis(requestId: requestId)
        supertonicService.cancelSynthesis(requestId: requestId)
        
        completion(.success(()))
    }
    
    func unloadVoice(engineType: NativeEngineType, voiceId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Task.detached(priority: .userInitiated) { [self] in
            let svc = service(for: engineType)
            svc.unloadVoice(voiceId: voiceId)
            completion(.success(()))
        }
    }
    
    func unloadEngine(engineType: NativeEngineType, completion: @escaping (Result<Void, Error>) -> Void) {
        // Run in background thread to avoid blocking UI
        // unloadAll() calls waitUntilIdle which can block for up to 5 seconds
        Task.detached(priority: .userInitiated) { [self] in
            let svc = service(for: engineType)
            svc.unloadAll()
            completion(.success(()))
        }
    }
    
    func getMemoryInfo(completion: @escaping (Result<MemoryInfo, Error>) -> Void) {
        // Get system memory info
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: Int32.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        let usedMB = result == KERN_SUCCESS ? Int64(info.resident_size / (1024 * 1024)) : 0
        let totalMB = Int64(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
        
        completion(.success(MemoryInfo(
            availableMB: totalMB - usedMB,
            totalMB: totalMB,
            loadedModelCount: 0 // TODO: Track loaded models
        )))
    }
    
    func getCoreStatus(engineType: NativeEngineType, completion: @escaping (Result<CoreStatus, Error>) -> Void) {
        // Thread logging: Entry point from Pigeon
        NSLog("[THREAD] getCoreStatus ENTRY: isMainThread=%@, thread=%@", 
              Thread.isMainThread ? "YES" : "NO", 
              Thread.current.description)
        
        // IMPORTANT: Run on background thread to avoid blocking main thread
        // when synthesis is in progress (svc.isReady acquires a lock)
        Task.detached(priority: .userInitiated) { [self] in
            let svc = service(for: engineType)
            let state: NativeCoreState = svc.isReady ? .ready : .notStarted
            
            completion(.success(CoreStatus(
                engineType: engineType,
                state: state,
                errorMessage: nil,
                downloadProgress: nil
            )))
        }
    }
    
    func isVoiceReady(engineType: NativeEngineType, voiceId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        // Thread logging: Entry point from Pigeon
        NSLog("[THREAD] isVoiceReady ENTRY: isMainThread=%@, thread=%@", 
              Thread.isMainThread ? "YES" : "NO", 
              Thread.current.description)
        
        // IMPORTANT: Run on background thread to avoid blocking main thread
        // when synthesis is in progress (svc.isReady acquires a lock)
        Task.detached(priority: .userInitiated) { [self] in
            // For now, just check if the engine is ready
            // TODO: Implement per-voice tracking
            let svc = service(for: engineType)
            completion(.success(svc.isReady))
        }
    }
    
    func dispose(completion: @escaping (Result<Void, Error>) -> Void) {
        kokoroService.unloadAll()
        piperService.unloadAll()
        supertonicService.unloadAll()
        
        lock.lock()
        activeRequests.removeAll()
        lock.unlock()
        
        completion(.success(()))
    }
}

