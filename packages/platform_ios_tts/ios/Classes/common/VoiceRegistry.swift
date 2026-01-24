import Foundation

/// Tracks loaded voices with persistence and usage statistics.
/// Provides voice lookup and LRU (least recently used) tracking.
class VoiceRegistry {
    
    /// Information about a registered voice.
    struct RegisteredVoice: Codable {
        let voiceId: String
        let engineType: String  // "kokoro", "piper", "supertonic"
        let modelPath: String
        let speakerId: Int?
        var lastUsed: Date
        var usageCount: Int
        
        init(voiceId: String, engineType: String, modelPath: String, speakerId: Int?, lastUsed: Date = Date(), usageCount: Int = 0) {
            self.voiceId = voiceId
            self.engineType = engineType
            self.modelPath = modelPath
            self.speakerId = speakerId
            self.lastUsed = lastUsed
            self.usageCount = usageCount
        }
    }
    
    /// Singleton instance.
    static let shared = VoiceRegistry()
    
    /// In-memory cache of registered voices.
    private var voices: [String: RegisteredVoice] = [:]
    
    /// Lock for thread safety.
    private let lock = NSLock()
    
    /// UserDefaults key for persistence.
    private let persistenceKey = "com.audiobook.tts.voiceRegistry"
    
    // MARK: - Initialization
    
    private init() {
        loadFromPersistence()
    }
    
    // MARK: - Public API
    
    /// Register a new voice or update an existing one.
    func register(
        voiceId: String,
        engineType: NativeEngineType,
        modelPath: String,
        speakerId: Int? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }
        
        let engineString = engineTypeToString(engineType)
        
        if var existing = voices[voiceId] {
            // Update existing voice
            existing.lastUsed = Date()
            existing.usageCount += 1
            voices[voiceId] = existing
        } else {
            // Register new voice
            voices[voiceId] = RegisteredVoice(
                voiceId: voiceId,
                engineType: engineString,
                modelPath: modelPath,
                speakerId: speakerId,
                lastUsed: Date(),
                usageCount: 1
            )
        }
        
        saveToPersistence()
        print("[VoiceRegistry] Registered voice: \(voiceId) (\(engineString))")
    }
    
    /// Mark a voice as recently used (updates lastUsed timestamp).
    func markUsed(voiceId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        if var voice = voices[voiceId] {
            voice.lastUsed = Date()
            voice.usageCount += 1
            voices[voiceId] = voice
            saveToPersistence()
        }
    }
    
    /// Get a registered voice by ID.
    func getVoice(voiceId: String) -> RegisteredVoice? {
        lock.lock()
        defer { lock.unlock() }
        return voices[voiceId]
    }
    
    /// Get all registered voices.
    func getAllVoices() -> [RegisteredVoice] {
        lock.lock()
        defer { lock.unlock() }
        return Array(voices.values)
    }
    
    /// Get all registered voices for a specific engine.
    func getVoices(for engineType: NativeEngineType) -> [RegisteredVoice] {
        lock.lock()
        defer { lock.unlock() }
        let engineString = engineTypeToString(engineType)
        return voices.values.filter { $0.engineType == engineString }
    }
    
    /// Get the least recently used voice (for eviction).
    func getLeastRecentlyUsed() -> RegisteredVoice? {
        lock.lock()
        defer { lock.unlock() }
        return voices.values.min(by: { $0.lastUsed < $1.lastUsed })
    }
    
    /// Get the least recently used voice for a specific engine.
    func getLeastRecentlyUsed(for engineType: NativeEngineType) -> RegisteredVoice? {
        lock.lock()
        defer { lock.unlock() }
        let engineString = engineTypeToString(engineType)
        return voices.values
            .filter { $0.engineType == engineString }
            .min(by: { $0.lastUsed < $1.lastUsed })
    }
    
    /// Unregister a voice.
    func unregister(voiceId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        voices.removeValue(forKey: voiceId)
        saveToPersistence()
        print("[VoiceRegistry] Unregistered voice: \(voiceId)")
    }
    
    /// Unregister all voices for a specific engine.
    func unregisterAll(for engineType: NativeEngineType) {
        lock.lock()
        defer { lock.unlock() }
        
        let engineString = engineTypeToString(engineType)
        voices = voices.filter { $0.value.engineType != engineString }
        saveToPersistence()
        print("[VoiceRegistry] Unregistered all \(engineString) voices")
    }
    
    /// Clear all registered voices.
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        
        voices.removeAll()
        saveToPersistence()
        print("[VoiceRegistry] Cleared all voices")
    }
    
    /// Check if a voice is registered.
    func isRegistered(voiceId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return voices[voiceId] != nil
    }
    
    /// Get count of registered voices.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return voices.count
    }
    
    // MARK: - Persistence
    
    private func saveToPersistence() {
        do {
            let data = try JSONEncoder().encode(voices)
            UserDefaults.standard.set(data, forKey: persistenceKey)
        } catch {
            print("[VoiceRegistry] Failed to save to persistence: \(error)")
        }
    }
    
    private func loadFromPersistence() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else {
            return
        }
        
        do {
            voices = try JSONDecoder().decode([String: RegisteredVoice].self, from: data)
            print("[VoiceRegistry] Loaded \(voices.count) voices from persistence")
        } catch {
            print("[VoiceRegistry] Failed to load from persistence: \(error)")
            voices = [:]
        }
    }
    
    // MARK: - Helpers
    
    private func engineTypeToString(_ engineType: NativeEngineType) -> String {
        switch engineType {
        case .kokoro:
            return "kokoro"
        case .piper:
            return "piper"
        case .supertonic:
            return "supertonic"
        @unknown default:
            return "unknown"
        }
    }
}
