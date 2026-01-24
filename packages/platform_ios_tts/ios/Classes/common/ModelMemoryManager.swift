import Foundation

/// Manages TTS model memory to prevent excessive memory usage.
/// Implements LRU (Least Recently Used) eviction strategy.
class ModelMemoryManager {
    
    /// Memory budget configuration per engine type.
    struct MemoryConfig {
        /// Maximum number of models that can be loaded simultaneously per engine.
        let maxModelsPerEngine: Int
        
        /// Maximum total number of models across all engines.
        let maxTotalModels: Int
        
        /// Default configuration for iOS (conservative due to memory constraints).
        static let `default` = MemoryConfig(
            maxModelsPerEngine: 2,
            maxTotalModels: 3
        )
        
        /// High memory configuration (for devices with more RAM).
        static let highMemory = MemoryConfig(
            maxModelsPerEngine: 3,
            maxTotalModels: 5
        )
    }
    
    /// Represents a loaded model in memory.
    struct LoadedModel {
        let voiceId: String
        let engineType: NativeEngineType
        let loadedAt: Date
        var lastUsed: Date
        let estimatedMemoryMB: Int
        
        init(voiceId: String, engineType: NativeEngineType, estimatedMemoryMB: Int) {
            self.voiceId = voiceId
            self.engineType = engineType
            self.loadedAt = Date()
            self.lastUsed = Date()
            self.estimatedMemoryMB = estimatedMemoryMB
        }
    }
    
    /// Singleton instance.
    static let shared = ModelMemoryManager()
    
    /// Memory configuration.
    private var config: MemoryConfig
    
    /// Currently loaded models.
    private var loadedModels: [String: LoadedModel] = [:]
    
    /// Lock for thread safety.
    private let lock = NSLock()
    
    /// Delegate for unloading models.
    weak var unloadDelegate: ModelMemoryManagerDelegate?
    
    // MARK: - Initialization
    
    private init() {
        self.config = Self.determineOptimalConfig()
        print("[ModelMemoryManager] Initialized with maxModelsPerEngine=\(config.maxModelsPerEngine), maxTotal=\(config.maxTotalModels)")
    }
    
    /// Determine optimal configuration based on device memory.
    private static func determineOptimalConfig() -> MemoryConfig {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Double(totalMemory) / (1024 * 1024 * 1024)
        
        // Devices with 4GB+ RAM can handle more models
        if memoryGB >= 4.0 {
            return .highMemory
        } else {
            return .default
        }
    }
    
    // MARK: - Public API
    
    /// Check if there's capacity to load a new model.
    /// Returns true if model can be loaded, false if eviction needed.
    func hasCapacity(for engineType: NativeEngineType) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let engineModels = loadedModels.values.filter { $0.engineType == engineType }
        let canLoadEngine = engineModels.count < config.maxModelsPerEngine
        let canLoadTotal = loadedModels.count < config.maxTotalModels
        
        return canLoadEngine && canLoadTotal
    }
    
    /// Ensure capacity for a new model, evicting LRU models if needed.
    /// Returns list of voice IDs that should be unloaded.
    func ensureCapacity(for engineType: NativeEngineType) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        
        var toUnload: [String] = []
        
        // Check engine-specific limit
        var engineModels = loadedModels.values.filter { $0.engineType == engineType }
        while engineModels.count >= config.maxModelsPerEngine {
            if let lru = engineModels.min(by: { $0.lastUsed < $1.lastUsed }) {
                toUnload.append(lru.voiceId)
                loadedModels.removeValue(forKey: lru.voiceId)
                engineModels = loadedModels.values.filter { $0.engineType == engineType }
                print("[ModelMemoryManager] Marked for eviction (engine limit): \(lru.voiceId)")
            } else {
                break
            }
        }
        
        // Check total limit
        while loadedModels.count >= config.maxTotalModels {
            if let lru = loadedModels.values.min(by: { $0.lastUsed < $1.lastUsed }) {
                toUnload.append(lru.voiceId)
                loadedModels.removeValue(forKey: lru.voiceId)
                print("[ModelMemoryManager] Marked for eviction (total limit): \(lru.voiceId)")
            } else {
                break
            }
        }
        
        return toUnload
    }
    
    /// Register a model as loaded.
    func registerLoaded(voiceId: String, engineType: NativeEngineType, estimatedMemoryMB: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        loadedModels[voiceId] = LoadedModel(
            voiceId: voiceId,
            engineType: engineType,
            estimatedMemoryMB: estimatedMemoryMB
        )
        print("[ModelMemoryManager] Registered loaded model: \(voiceId) (~\(estimatedMemoryMB)MB)")
    }
    
    /// Mark a model as recently used.
    func markUsed(voiceId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        if var model = loadedModels[voiceId] {
            model.lastUsed = Date()
            loadedModels[voiceId] = model
        }
    }
    
    /// Register a model as unloaded.
    func registerUnloaded(voiceId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        loadedModels.removeValue(forKey: voiceId)
        print("[ModelMemoryManager] Registered unloaded model: \(voiceId)")
    }
    
    /// Get the least recently used model (for manual eviction).
    func getLeastRecentlyUsed() -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        return loadedModels.values.min(by: { $0.lastUsed < $1.lastUsed })?.voiceId
    }
    
    /// Get the least recently used model for a specific engine.
    func getLeastRecentlyUsed(for engineType: NativeEngineType) -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        return loadedModels.values
            .filter { $0.engineType == engineType }
            .min(by: { $0.lastUsed < $1.lastUsed })?
            .voiceId
    }
    
    /// Get all currently loaded models.
    func getLoadedModels() -> [LoadedModel] {
        lock.lock()
        defer { lock.unlock() }
        return Array(loadedModels.values)
    }
    
    /// Get loaded models for a specific engine.
    func getLoadedModels(for engineType: NativeEngineType) -> [LoadedModel] {
        lock.lock()
        defer { lock.unlock() }
        return loadedModels.values.filter { $0.engineType == engineType }
    }
    
    /// Check if a specific model is loaded.
    func isLoaded(voiceId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadedModels[voiceId] != nil
    }
    
    /// Get total estimated memory usage in MB.
    var totalMemoryUsageMB: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadedModels.values.reduce(0) { $0 + $1.estimatedMemoryMB }
    }
    
    /// Clear all loaded models (for cleanup/reset).
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        
        loadedModels.removeAll()
        print("[ModelMemoryManager] Cleared all loaded models")
    }
    
    /// Get current number of loaded models.
    var loadedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadedModels.count
    }
    
    /// Update configuration (for testing or dynamic adjustment).
    func updateConfig(_ newConfig: MemoryConfig) {
        lock.lock()
        defer { lock.unlock() }
        
        config = newConfig
        print("[ModelMemoryManager] Updated config: maxModelsPerEngine=\(config.maxModelsPerEngine), maxTotal=\(config.maxTotalModels)")
    }
    
    // MARK: - Memory Pressure Handling
    
    /// Handle memory warning from the system.
    /// Returns list of voice IDs that should be unloaded.
    func handleMemoryWarning() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        
        print("[ModelMemoryManager] Memory warning received")
        
        // Unload all but the most recently used model
        var toUnload: [String] = []
        let sorted = loadedModels.values.sorted { $0.lastUsed > $1.lastUsed }
        
        for (index, model) in sorted.enumerated() {
            if index > 0 {  // Keep only the most recent
                toUnload.append(model.voiceId)
                loadedModels.removeValue(forKey: model.voiceId)
            }
        }
        
        if !toUnload.isEmpty {
            print("[ModelMemoryManager] Evicting \(toUnload.count) models due to memory pressure")
        }
        
        return toUnload
    }
}

// MARK: - Delegate Protocol

/// Delegate for handling model unloading.
protocol ModelMemoryManagerDelegate: AnyObject {
    /// Called when a model should be unloaded due to memory constraints.
    func memoryManager(_ manager: ModelMemoryManager, shouldUnloadVoice voiceId: String, engineType: NativeEngineType)
}
