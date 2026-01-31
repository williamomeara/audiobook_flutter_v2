import Foundation
import CoreML

/// CoreML-based inference for Supertonic TTS.
/// Implements the 4-stage pipeline: Duration Predictor → Text Encoder → Vector Estimator → Vocoder
final class SupertonicCoreMLInference {
    
    // MARK: - Types
    
    private struct Config: Decodable {
        let ttl: TTLConfig
        let ae: AEConfig
        
        struct TTLConfig: Decodable {
            let chunk_compress_factor: Int
        }
        
        struct AEConfig: Decodable {
            let sample_rate: Int
            let base_chunk_size: Int
        }
    }
    
    private struct Embedding {
        let vocabSize: Int
        let dim: Int
        let weights: [Float]
    }
    
    private struct VoiceFile: Decodable {
        struct Tensor: Decodable {
            let data: [[[Float]]]
            let dims: [Int]
        }
        let style_ttl: Tensor
        let style_dp: Tensor
    }
    
    private struct VoiceStyle {
        let ttl: MLMultiArray
        let dp: MLMultiArray
    }
    
    // MARK: - Properties
    
    private var dpModel: MLModel?
    private var teModel: MLModel?
    private var veModel: MLModel?
    private var vocModel: MLModel?
    
    private var unicodeIndexer: [Int] = []
    private var embeddingDP: Embedding?
    private var embeddingTE: Embedding?
    private var voiceDir: URL?
    
    private var sampleRate: Int = 24000
    private var baseChunkSize: Int = 256
    private var chunkCompressFactor: Int = 4
    
    private var maxTextLen: Int = 300
    private var latentDim: Int = 128
    private var latentLenMax: Int = 256
    
    private var voiceCache: [String: VoiceStyle] = [:]
    private let lock = NSLock()
    
    var isModelLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return dpModel != nil && teModel != nil && veModel != nil && vocModel != nil
    }
    
    // MARK: - Loading
    
    /// Load CoreML models from the app bundle.
    /// - Parameter bundlePath: "__BUNDLED_COREML__" to load from app bundle, or a directory path to downloaded models
    func loadFromBundle(_ bundlePath: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        NSLog("[SupertonicCoreML] Loading models from: %@", bundlePath)
        
        let mlConfig = MLModelConfiguration()
        mlConfig.computeUnits = .all
        mlConfig.allowLowPrecisionAccumulationOnGPU = true
        
        if bundlePath == "__BUNDLED_COREML__" {
            // Load from app bundle (legacy bundled mode)
            try loadFromAppBundle(config: mlConfig)
        } else {
            // Load from downloaded directory path
            try loadFromDirectory(URL(fileURLWithPath: bundlePath), config: mlConfig)
        }
        
        // Extract model limits from input constraints
        if let teModel = teModel,
           let desc = teModel.modelDescription.inputDescriptionsByName["text_mask"],
           let constraint = desc.multiArrayConstraint {
            let shape = constraint.shape.map { Int(truncating: $0) }
            if let lastDim = shape.last {
                maxTextLen = lastDim
            }
        }
        
        if let veModel = veModel,
           let desc = veModel.modelDescription.inputDescriptionsByName["noisy_latent"],
           let constraint = desc.multiArrayConstraint {
            let shape = constraint.shape.map { Int(truncating: $0) }
            if shape.count >= 3 {
                latentDim = shape[1]
                latentLenMax = shape[2]
            }
        }
        
        NSLog("[SupertonicCoreML] Models loaded. maxTextLen=%d, latentDim=%d, latentLenMax=%d", 
              maxTextLen, latentDim, latentLenMax)
    }
    
    /// Load models from app bundle (bundled with app)
    private func loadFromAppBundle(config: MLModelConfiguration) throws {
        let frameworkBundle = Bundle(for: SupertonicCoreMLInference.self)
        
        // Find resource bundles for models and resources
        guard let resourcesURL = frameworkBundle.url(forResource: "SupertonicResources", withExtension: "bundle"),
              let resourcesBundle = Bundle(url: resourcesURL) else {
            NSLog("[SupertonicCoreML] ERROR: SupertonicResources.bundle not found")
            throw TtsError.modelNotLoaded
        }
        
        let resourcesDir = resourcesBundle.bundleURL
        NSLog("[SupertonicCoreML] Found resources bundle at: %@", resourcesDir.path)
        
        // Load shared resources
        try loadResources(from: resourcesDir)
        
        // Load CoreML models from their respective bundles
        dpModel = try loadMLModelFromBundle("SupertonicDurationPredictor", frameworkBundle: frameworkBundle, config: config)
        teModel = try loadMLModelFromBundle("SupertonicTextEncoder", frameworkBundle: frameworkBundle, config: config)
        veModel = try loadMLModelFromBundle("SupertonicVectorEstimator", frameworkBundle: frameworkBundle, config: config)
        vocModel = try loadMLModelFromBundle("SupertonicVocoder", frameworkBundle: frameworkBundle, config: config)
    }
    
    /// Load models from a downloaded directory
    private func loadFromDirectory(_ baseDir: URL, config: MLModelConfiguration) throws {
        NSLog("[SupertonicCoreML] Loading from downloaded directory: %@", baseDir.path)
        
        // Load shared resources
        try loadResources(from: baseDir)
        
        // Load CoreML models from the directory
        dpModel = try loadMLModel("duration_predictor_mlprogram", in: baseDir, config: config)
        teModel = try loadMLModel("text_encoder_mlprogram", in: baseDir, config: config)
        veModel = try loadMLModel("vector_estimator_mlprogram", in: baseDir, config: config)
        vocModel = try loadMLModel("vocoder_mlprogram", in: baseDir, config: config)
    }
    
    /// Load shared resources (config, indexer, embeddings, voice styles)
    private func loadResources(from resourcesDir: URL) throws {
        // Load config
        let configURL = resourcesDir.appendingPathComponent("tts.json")
        if FileManager.default.fileExists(atPath: configURL.path) {
            let config = try loadConfig(configURL)
            sampleRate = config.ae.sample_rate
            baseChunkSize = config.ae.base_chunk_size
            chunkCompressFactor = config.ttl.chunk_compress_factor
        } else {
            // Try in onnx subdirectory (downloaded archive structure)
            let onnxConfigURL = resourcesDir.appendingPathComponent("onnx/tts.json")
            if FileManager.default.fileExists(atPath: onnxConfigURL.path) {
                let config = try loadConfig(onnxConfigURL)
                sampleRate = config.ae.sample_rate
                baseChunkSize = config.ae.base_chunk_size
                chunkCompressFactor = config.ttl.chunk_compress_factor
            }
        }
        
        // Load unicode indexer
        let indexerURL = resourcesDir.appendingPathComponent("unicode_indexer.json")
        let onnxIndexerURL = resourcesDir.appendingPathComponent("onnx/unicode_indexer.json")
        if FileManager.default.fileExists(atPath: indexerURL.path) {
            unicodeIndexer = try loadIndexer(indexerURL)
        } else if FileManager.default.fileExists(atPath: onnxIndexerURL.path) {
            unicodeIndexer = try loadIndexer(onnxIndexerURL)
        }
        
        // Load embeddings
        let embDir = resourcesDir.appendingPathComponent("embeddings")
        if FileManager.default.fileExists(atPath: embDir.path) {
            embeddingDP = try loadEmbedding(
                dataURL: embDir.appendingPathComponent("char_embedder_dp.fp32.bin"),
                shapeURL: embDir.appendingPathComponent("char_embedder_dp.shape.json")
            )
            embeddingTE = try loadEmbedding(
                dataURL: embDir.appendingPathComponent("char_embedder_te.fp32.bin"),
                shapeURL: embDir.appendingPathComponent("char_embedder_te.shape.json")
            )
        } else {
            // Try flat structure (bundled resources)
            embeddingDP = try loadEmbedding(
                dataURL: resourcesDir.appendingPathComponent("char_embedder_dp.fp32.bin"),
                shapeURL: resourcesDir.appendingPathComponent("char_embedder_dp.shape.json")
            )
            embeddingTE = try loadEmbedding(
                dataURL: resourcesDir.appendingPathComponent("char_embedder_te.fp32.bin"),
                shapeURL: resourcesDir.appendingPathComponent("char_embedder_te.shape.json")
            )
        }
        
        // Voice styles directory
        let voiceStylesDir = resourcesDir.appendingPathComponent("voice_styles")
        if FileManager.default.fileExists(atPath: voiceStylesDir.path) {
            voiceDir = voiceStylesDir
        } else {
            voiceDir = resourcesDir
        }
    }
    
    /// Synthesize text to audio samples.
    /// Thread-safe: Uses lock to prevent concurrent CoreML inference (CoreML models are not thread-safe)
    func synthesize(text: String, voiceName: String, speakerId: Int, speed: Float) throws -> (samples: [Float], sampleRate: Int) {
        // Hold lock for entire synthesis to prevent concurrent CoreML access
        lock.lock()
        defer { lock.unlock() }
        
        guard dpModel != nil && teModel != nil && veModel != nil && vocModel != nil else {
            throw TtsError.modelNotLoaded
        }
        
        guard let embeddingDP = embeddingDP, let embeddingTE = embeddingTE else {
            throw TtsError.invalidInput("Embeddings not loaded")
        }
        
        // Map voice ID to style name (e.g., supertonic_m1 -> M1)
        let styleName = mapVoiceIdToStyleName(voiceName, speakerId: speakerId)
        print("[SupertonicCoreML] Synthesizing text: '\(text)' with style: \(styleName), speakerId: \(speakerId)")
        
        let voice = try loadVoiceStyle(named: styleName)
        
        // Preprocess text
        let processed = preprocessText(text, lang: "en")
        print("[SupertonicCoreML] Processed text: '\(processed)'")
        
        // Build inputs
        let (textIds, textMask) = try buildTextInputs(processedText: processed, maxLen: maxTextLen)
        print("[SupertonicCoreML] Text IDs count: \(textIds.count), maxTextLen: \(maxTextLen)")
        
        let textEmbedDP = try buildTextEmbed(textIds: textIds, embedding: embeddingDP, maxLen: maxTextLen)
        let textEmbedTE = try buildTextEmbed(textIds: textIds, embedding: embeddingTE, maxLen: maxTextLen)
        
        // Stage 1: Duration Predictor
        let duration = try runDurationPredictor(styleDP: voice.dp, textMask: textMask, textEmbed: textEmbedDP)
        print("[SupertonicCoreML] Duration predictor output: \(duration) seconds")
        
        // Stage 2: Text Encoder
        let textEmb = try runTextEncoder(styleTTL: voice.ttl, textMask: textMask, textEmbed: textEmbedTE)
        
        // Apply speed and clamp duration
        let adjustedDuration = max(Double(duration) / max(Double(speed), 0.01), 0.05)
        let maxDuration = maxDurationSeconds()
        let clippedDuration = min(adjustedDuration, maxDuration)
        print("[SupertonicCoreML] Adjusted duration: \(adjustedDuration), maxDuration: \(maxDuration), clipped: \(clippedDuration)")
        
        // Stage 3: Vector Estimator (diffusion denoising)
        let (noisyLatent, latentMask) = try sampleNoisyLatent(durationSeconds: clippedDuration)
        let steps = 20 // Default diffusion steps
        print("[SupertonicCoreML] Running vector estimator with \(steps) steps")
        let denoised = try runVectorEstimator(
            noisyLatent: noisyLatent,
            textEmb: textEmb,
            styleTTL: voice.ttl,
            latentMask: latentMask,
            textMask: textMask,
            steps: steps
        )
        
        // Stage 4: Vocoder
        var wav = try runVocoder(latent: denoised)
        print("[SupertonicCoreML] Vocoder output: \(wav.count) samples (\(Double(wav.count) / Double(sampleRate)) seconds)")
        
        // Trim to target duration
        let trimSamples = min(Int(Double(sampleRate) * clippedDuration), wav.count)
        if trimSamples > 0 && trimSamples < wav.count {
            wav = Array(wav[0..<trimSamples])
        }
        print("[SupertonicCoreML] Final output: \(wav.count) samples (\(Double(wav.count) / Double(sampleRate)) seconds)")
        
        // Normalize audio
        normalizeAudio(&wav)
        
        return (wav, sampleRate)
    }
    
    func unload() {
        lock.lock()
        defer { lock.unlock() }
        
        dpModel = nil
        teModel = nil
        veModel = nil
        vocModel = nil
        voiceCache.removeAll()
        NSLog("[SupertonicCoreML] Models unloaded")
    }
    
    // MARK: - Model Runners
    
    private func runDurationPredictor(styleDP: MLMultiArray, textMask: MLMultiArray, textEmbed: MLMultiArray) throws -> Float {
        guard let dpModel = dpModel else { throw TtsError.modelNotLoaded }
        
        let inputs: [String: MLMultiArray] = [
            "style_dp": styleDP,
            "text_mask": textMask,
            "text_embed": textEmbed
        ]
        let output = try predict(model: dpModel, inputs: inputs)
        guard let duration = output["duration"] else {
            throw TtsError.synthesisFailure("Missing duration output")
        }
        return readScalar(duration)
    }
    
    private func runTextEncoder(styleTTL: MLMultiArray, textMask: MLMultiArray, textEmbed: MLMultiArray) throws -> MLMultiArray {
        guard let teModel = teModel else { throw TtsError.modelNotLoaded }
        
        let inputs: [String: MLMultiArray] = [
            "style_ttl": styleTTL,
            "text_mask": textMask,
            "text_embed": textEmbed
        ]
        let output = try predict(model: teModel, inputs: inputs)
        guard let textEmb = output["text_emb"] else {
            throw TtsError.synthesisFailure("Missing text_emb output")
        }
        return textEmb
    }
    
    private func runVectorEstimator(
        noisyLatent: MLMultiArray,
        textEmb: MLMultiArray,
        styleTTL: MLMultiArray,
        latentMask: MLMultiArray,
        textMask: MLMultiArray,
        steps: Int
    ) throws -> MLMultiArray {
        guard let veModel = veModel else { throw TtsError.modelNotLoaded }
        
        var latent = noisyLatent
        let totalStep = try makeScalar(Float(steps))
        
        for step in 0..<steps {
            let currentStep = try makeScalar(Float(step))
            let inputs: [String: MLMultiArray] = [
                "noisy_latent": latent,
                "text_emb": textEmb,
                "style_ttl": styleTTL,
                "latent_mask": latentMask,
                "text_mask": textMask,
                "current_step": currentStep,
                "total_step": totalStep
            ]
            let output = try predict(model: veModel, inputs: inputs)
            guard let denoised = output["denoised_latent"] else {
                throw TtsError.synthesisFailure("Missing denoised_latent output")
            }
            latent = denoised
        }
        return latent
    }
    
    private func runVocoder(latent: MLMultiArray) throws -> [Float] {
        guard let vocModel = vocModel else { throw TtsError.modelNotLoaded }
        
        let output = try predict(model: vocModel, inputs: ["latent": latent])
        guard let wav = output["wav_tts"] else {
            throw TtsError.synthesisFailure("Missing wav_tts output")
        }
        return toFloatArray(wav)
    }
    
    // MARK: - Text Processing
    
    private func preprocessText(_ text: String, lang: String) -> String {
        // Normalize and strip unsupported characters to match the training pipeline
        var processed = text.decomposedStringWithCompatibilityMapping
        
        // Remove emojis and special unicode blocks
        processed = processed.unicodeScalars.filter { scalar in
            let value = scalar.value
            // Filter out common emoji ranges
            return !((value >= 0x1F600 && value <= 0x1F64F) ||   // Emoticons
                     (value >= 0x1F300 && value <= 0x1F5FF) ||   // Misc Symbols/Pictographs
                     (value >= 0x1F680 && value <= 0x1F6FF) ||   // Transport/Map
                     (value >= 0x1F700 && value <= 0x1F77F) ||   // Alchemical
                     (value >= 0x1F780 && value <= 0x1F7FF) ||   // Geometric Extended
                     (value >= 0x1F800 && value <= 0x1F8FF) ||   // Supplemental Arrows-C
                     (value >= 0x1F900 && value <= 0x1F9FF) ||   // Supplemental Symbols
                     (value >= 0x1FA00 && value <= 0x1FA6F) ||   // Chess Symbols
                     (value >= 0x1FA70 && value <= 0x1FAFF) ||   // Symbols Extended-A
                     (value >= 0x2600 && value <= 0x26FF) ||     // Misc symbols
                     (value >= 0x2700 && value <= 0x27BF) ||     // Dingbats
                     (value >= 0x1F1E6 && value <= 0x1F1FF))     // Flags
        }.map { String($0) }.joined()
        
        // Character replacements
        let replacements: [String: String] = [
            "–": "-", "‑": "-", "—": "-", "_": " ",
            "\u{201C}": "\"", "\u{201D}": "\"",  // Smart quotes
            "\u{2018}": "'", "\u{2019}": "'",    // Smart apostrophes
            "´": "'", "`": "'",
            "[": " ", "]": " ", "|": " ", "/": " ", "#": " ",
            "→": " ", "←": " ",
            "♥": "", "☆": "", "♡": "", "©": "", "\\": "",
            "@": " at ", "e.g.,": "for example, ", "i.e.,": "that is, "
        ]
        for (old, new) in replacements {
            processed = processed.replacingOccurrences(of: old, with: new)
        }
        
        // Clean up spacing
        processed = processed.replacingOccurrences(of: " ,", with: ",")
        processed = processed.replacingOccurrences(of: " .", with: ".")
        processed = processed.replacingOccurrences(of: " !", with: "!")
        processed = processed.replacingOccurrences(of: " ?", with: "?")
        
        // Collapse multiple whitespaces
        let whitespacePattern = try? NSRegularExpression(pattern: "\\s+")
        let whitespaceRange = NSRange(processed.startIndex..., in: processed)
        if let whitespacePattern = whitespacePattern {
            processed = whitespacePattern.stringByReplacingMatches(in: processed, range: whitespaceRange, withTemplate: " ")
        }
        processed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure punctuation at end
        let punctPattern = try? NSRegularExpression(pattern: "[.!?;:,'\"\\u201C\\u201D\\u2018\\u2019)\\]}…。」』】〉》›»]$")
        let punctRange = NSRange(processed.startIndex..., in: processed)
        if punctPattern?.firstMatch(in: processed, range: punctRange) == nil && !processed.isEmpty {
            processed += "."
        }
        
        return "<\(lang)>\(processed)</\(lang)>"
    }
    
    private func buildTextInputs(processedText: String, maxLen: Int) throws -> ([Int], MLMultiArray) {
        let scalars = processedText.unicodeScalars
        var ids: [Int] = []
        
        for scalar in scalars {
            let value = Int(scalar.value)
            // Skip characters outside the indexer range
            guard value < unicodeIndexer.count else {
                print("[SupertonicCoreML] Warning: Skipping character with value \(value) (outside indexer range)")
                continue
            }
            let idx = unicodeIndexer[value]
            // Skip unsupported characters (index -1)
            guard idx >= 0 else {
                print("[SupertonicCoreML] Warning: Skipping unsupported character '\(scalar)' (code: \(value))")
                continue
            }
            ids.append(idx)
        }
        
        if ids.isEmpty {
            throw TtsError.invalidInput("No valid characters in text after filtering")
        }
        
        if ids.count > maxLen {
            print("[SupertonicCoreML] Warning: Text truncated from \(ids.count) to \(maxLen) characters")
            ids = Array(ids.prefix(maxLen))
        }
        
        let mask = try makeMask(length: ids.count, maxLen: maxLen)
        return (ids, mask)
    }
    
    private func buildTextEmbed(textIds: [Int], embedding: Embedding, maxLen: Int) throws -> MLMultiArray {
        let shape = [1, embedding.dim, maxLen]
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        let strides = array.strides.map { Int(truncating: $0) }
        let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)
        
        for t in 0..<maxLen {
            if t < textIds.count {
                let id = textIds[t]
                guard id >= 0, id < embedding.vocabSize else {
                    throw TtsError.invalidInput("Invalid text id: \(id)")
                }
                let base = id * embedding.dim
                for d in 0..<embedding.dim {
                    let offset = d * strides[1] + t * strides[2]
                    ptr[offset] = embedding.weights[base + d]
                }
            } else {
                for d in 0..<embedding.dim {
                    let offset = d * strides[1] + t * strides[2]
                    ptr[offset] = 0
                }
            }
        }
        return array
    }
    
    // MARK: - Latent Sampling
    
    private func sampleNoisyLatent(durationSeconds: Double) throws -> (MLMultiArray, MLMultiArray) {
        let wavLen = Int(durationSeconds * Double(sampleRate))
        let chunkSize = baseChunkSize * chunkCompressFactor
        let latentLen = min((wavLen + chunkSize - 1) / chunkSize, latentLenMax)
        
        let latentMask = try makeMask(length: latentLen, maxLen: latentLenMax)
        let noisyLatent = try MLMultiArray(shape: [1, latentDim, latentLenMax].map { NSNumber(value: $0) }, dataType: .float32)
        let strides = noisyLatent.strides.map { Int(truncating: $0) }
        let ptr = noisyLatent.dataPointer.bindMemory(to: Float32.self, capacity: noisyLatent.count)
        
        for d in 0..<latentDim {
            for t in 0..<latentLenMax {
                let offset = d * strides[1] + t * strides[2]
                ptr[offset] = t < latentLen ? randomNormal() : 0
            }
        }
        return (noisyLatent, latentMask)
    }
    
    private func randomNormal() -> Float {
        let u1 = max(Float.random(in: 0..<1), 1e-6)
        let u2 = Float.random(in: 0..<1)
        return sqrt(-2 * log(u1)) * cos(2 * Float.pi * u2)
    }
    
    private func makeMask(length: Int, maxLen: Int) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, 1, maxLen].map { NSNumber(value: $0) }, dataType: .float32)
        let strides = array.strides.map { Int(truncating: $0) }
        let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)
        for t in 0..<maxLen {
            let offset = t * strides[2]
            ptr[offset] = t < length ? 1 : 0
        }
        return array
    }
    
    private func makeScalar(_ value: Float) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1], dataType: .float32)
        let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: 1)
        ptr[0] = value
        return array
    }
    
    private func maxDurationSeconds() -> Double {
        let chunkSize = baseChunkSize * chunkCompressFactor
        let maxSamples = latentLenMax * chunkSize
        return Double(maxSamples) / Double(sampleRate)
    }
    
    // MARK: - CoreML Helpers
    
    private func predict(model: MLModel, inputs: [String: MLMultiArray]) throws -> [String: MLMultiArray] {
        let featureInputs: [String: MLFeatureValue] = inputs.mapValues { MLFeatureValue(multiArray: $0) }
        let provider = try MLDictionaryFeatureProvider(dictionary: featureInputs)
        let output = try model.prediction(from: provider)
        var result: [String: MLMultiArray] = [:]
        for name in output.featureNames {
            if let value = output.featureValue(for: name)?.multiArrayValue {
                result[name] = value
            }
        }
        return result
    }
    
    private func readScalar(_ array: MLMultiArray) -> Float {
        // Handle different data types - CoreML int8 models may use Float16
        if array.dataType == .float32 {
            let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: 1)
            return Float(ptr[0])
        }
        if #available(iOS 16.0, *), array.dataType == .float16 {
            let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: 1)
            return Float(ptr[0])
        }
        // Fallback - try subscript access which handles type conversion
        return array[0].floatValue
    }
    
    private func toFloatArray(_ array: MLMultiArray) -> [Float] {
        let count = array.count
        if array.dataType == .float32 {
            let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: count)
            return Array(UnsafeBufferPointer(start: ptr, count: count))
        }
        if #available(iOS 16.0, *), array.dataType == .float16 {
            let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: count)
            return Array(UnsafeBufferPointer(start: ptr, count: count)).map { Float($0) }
        }
        // Fallback
        let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: count)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }
    
    // MARK: - Audio
    
    private func normalizeAudio(_ audio: inout [Float]) {
        guard !audio.isEmpty else { return }
        let maxAbs = audio.map { abs($0) }.max() ?? 0
        guard maxAbs > 1e-6 else { return }
        let scale = 0.95 / maxAbs
        for i in 0..<audio.count {
            audio[i] = audio[i] * Float(scale)
        }
    }
    
    // MARK: - Voice Style Loading
    
    private func mapVoiceIdToStyleName(_ voiceId: String, speakerId: Int) -> String {
        // Map speakerId to voice style name
        // Male: M1-M5 (speakerId 0-4)
        // Female: F1-F5 (speakerId 5-9)
        if speakerId >= 0 && speakerId <= 4 {
            return "M\(speakerId + 1)"
        } else if speakerId >= 5 && speakerId <= 9 {
            return "F\(speakerId - 4)"
        }
        // Default fallback
        return "M1"
    }
    
    private func loadVoiceStyle(named name: String) throws -> VoiceStyle {
        if let cached = voiceCache[name] {
            return cached
        }
        
        guard let voiceDir = voiceDir else {
            throw TtsError.invalidInput("Voice directory not set")
        }
        
        let url = voiceDir.appendingPathComponent("\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TtsError.voiceNotLoaded(name)
        }
        
        let data = try Data(contentsOf: url)
        let voice = try JSONDecoder().decode(VoiceFile.self, from: data)
        
        let ttlFlat = flatten(voice.style_ttl.data)
        let dpFlat = flatten(voice.style_dp.data)
        
        let ttl = try makeMultiArray(shape: voice.style_ttl.dims, data: ttlFlat)
        let dp = try makeMultiArray(shape: voice.style_dp.dims, data: dpFlat)
        
        let style = VoiceStyle(ttl: ttl, dp: dp)
        voiceCache[name] = style
        return style
    }
    
    private func flatten(_ data: [[[Float]]]) -> [Float] {
        var flat: [Float] = []
        for a in data {
            for b in a {
                flat.append(contentsOf: b)
            }
        }
        return flat
    }
    
    private func makeMultiArray(shape: [Int], data: [Float]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        guard array.count == data.count else {
            throw TtsError.invalidInput("Shape mismatch")
        }
        let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)
        data.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                ptr.update(from: base, count: buffer.count)
            }
        }
        return array
    }
    
    // MARK: - Resource Loading
    
    private func locateResourceDir(_ name: String, in resources: URL) -> URL? {
        let fm = FileManager.default
        let candidates = [
            resources.appendingPathComponent(name, isDirectory: true),
            resources.appendingPathComponent("platform_ios_tts/\(name)", isDirectory: true),
            resources.appendingPathComponent("Assets/\(name)", isDirectory: true)
        ]
        for url in candidates {
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }
        
        // Search recursively for the directory
        if let enumerator = fm.enumerator(at: resources, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let url as URL in enumerator {
                if url.lastPathComponent == name {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        return url
                    }
                }
            }
        }
        return nil
    }
    
    private func loadConfig(_ url: URL) throws -> Config {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Config.self, from: data)
    }
    
    private func loadIndexer(_ url: URL) throws -> [Int] {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        guard let array = json as? [Int] else {
            throw TtsError.invalidInput("unicode_indexer.json is not an int array")
        }
        return array
    }
    
    private func loadEmbedding(dataURL: URL, shapeURL: URL) throws -> Embedding {
        let shapeData = try Data(contentsOf: shapeURL)
        let shapeJson = try JSONSerialization.jsonObject(with: shapeData) as? [String: Any]
        guard let shape = shapeJson?["shape"] as? [Int], shape.count == 2 else {
            throw TtsError.invalidInput("Embedding shape missing or invalid")
        }
        
        let data = try Data(contentsOf: dataURL)
        let count = data.count / MemoryLayout<Float>.size
        var weights = [Float](repeating: 0, count: count)
        weights.withUnsafeMutableBytes { dest in
            dest.copyBytes(from: data)
        }
        
        let expected = shape[0] * shape[1]
        guard expected == weights.count else {
            throw TtsError.invalidInput("Embedding size mismatch: expected \(expected), got \(weights.count)")
        }
        
        return Embedding(vocabSize: shape[0], dim: shape[1], weights: weights)
    }
    
    private func loadMLModel(_ name: String, in dir: URL, config: MLModelConfiguration) throws -> MLModel {
        // Try compiled model first
        let compiledPath = dir.appendingPathComponent("\(name).mlmodelc")
        if FileManager.default.fileExists(atPath: compiledPath.path) {
            return try MLModel(contentsOf: compiledPath, configuration: config)
        }
        
        // Try mlpackage
        let packagePath = dir.appendingPathComponent("\(name).mlpackage")
        if FileManager.default.fileExists(atPath: packagePath.path) {
            let compiled = try MLModel.compileModel(at: packagePath)
            return try MLModel(contentsOf: compiled, configuration: config)
        }
        
        throw TtsError.modelNotLoaded
    }
    
    /// Load CoreML model from a separate bundle (for resource_bundles in podspec)
    private func loadMLModelFromBundle(_ bundleName: String, frameworkBundle: Bundle, config: MLModelConfiguration) throws -> MLModel {
        guard let bundleURL = frameworkBundle.url(forResource: bundleName, withExtension: "bundle"),
              let modelBundle = Bundle(url: bundleURL) else {
            NSLog("[SupertonicCoreML] ERROR: %@.bundle not found", bundleName)
            throw TtsError.modelNotLoaded
        }
        
        let bundleDir = modelBundle.bundleURL
        NSLog("[SupertonicCoreML] Loading model from bundle: %@", bundleDir.path)
        
        // The model bundle contains the contents of the mlpackage directly
        // Try to find model.mlmodelc (compiled) first, then compile from mlpackage contents
        let compiledPath = bundleDir.appendingPathComponent("model.mlmodelc")
        if FileManager.default.fileExists(atPath: compiledPath.path) {
            return try MLModel(contentsOf: compiledPath, configuration: config)
        }
        
        // The bundle IS the mlpackage - compile it directly
        // Need to check if this is a valid mlpackage structure
        let manifestPath = bundleDir.appendingPathComponent("Manifest.json")
        if FileManager.default.fileExists(atPath: manifestPath.path) {
            // This bundle contains mlpackage contents - compile it
            let compiled = try MLModel.compileModel(at: bundleDir)
            return try MLModel(contentsOf: compiled, configuration: config)
        }
        
        NSLog("[SupertonicCoreML] ERROR: No valid model found in %@", bundleName)
        throw TtsError.modelNotLoaded
    }
}
