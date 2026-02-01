import Foundation

/// ONNX-based inference for Supertonic TTS.
/// Implements the 4-stage pipeline: Duration Predictor → Text Encoder → Vector Estimator → Vocoder
/// Based on the official Supertonic SDK implementation (supertone-inc/supertonic).
final class SupertonicOnnxInference {
    
    // MARK: - Types
    
    private struct Config: Decodable {
        let ttl: TTLConfig
        let ae: AEConfig
        
        struct TTLConfig: Decodable {
            let chunk_compress_factor: Int
            let latent_dim: Int
        }
        
        struct AEConfig: Decodable {
            let sample_rate: Int
            let base_chunk_size: Int
        }
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
        let ttl: [Float]
        let ttlDims: [Int64]
        let dp: [Float]
        let dpDims: [Int64]
    }
    
    // MARK: - Properties
    
    private var ortWrapper: OrtWrapper?
    private var dpSession: OrtSession?
    private var teSession: OrtSession?
    private var veSession: OrtSession?
    private var vocSession: OrtSession?
    
    private var unicodeIndexer: [Int64] = []
    private var voiceDir: URL?
    
    // Defaults match tts.json from Supertone/supertonic on HuggingFace
    // These are overwritten when tts.json is loaded
    private var sampleRate: Int = 44100
    private var baseChunkSize: Int = 512
    private var chunkCompressFactor: Int = 6
    private var latentDim: Int = 24
    
    private var voiceCache: [String: VoiceStyle] = [:]
    private let lock = NSLock()
    
    private static let supportedLangs = ["en", "ko", "es", "pt", "fr"]
    private static let defaultSteps = 20
    
    var isModelLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return dpSession != nil && teSession != nil && veSession != nil && vocSession != nil
    }
    
    // MARK: - Loading
    
    /// Load ONNX models from a directory path.
    func loadFromDirectory(_ basePath: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        NSLog("[SupertonicOnnx] Loading models from: %@", basePath)
        let baseDir = URL(fileURLWithPath: basePath)
        
        // Initialize ONNX Runtime
        let wrapper = try OrtWrapper()
        self.ortWrapper = wrapper
        
        // Determine if models are in onnx subdirectory
        let onnxDir: URL
        let onnxSubdir = baseDir.appendingPathComponent("onnx")
        if FileManager.default.fileExists(atPath: onnxSubdir.path) {
            onnxDir = onnxSubdir
        } else {
            onnxDir = baseDir
        }
        
        // Load config
        let configPath = onnxDir.appendingPathComponent("tts.json")
        if FileManager.default.fileExists(atPath: configPath.path) {
            let data = try Data(contentsOf: configPath)
            let config = try JSONDecoder().decode(Config.self, from: data)
            sampleRate = config.ae.sample_rate
            baseChunkSize = config.ae.base_chunk_size
            chunkCompressFactor = config.ttl.chunk_compress_factor
            latentDim = config.ttl.latent_dim
            NSLog("[SupertonicOnnx] Config loaded: sampleRate=%d, baseChunkSize=%d, chunkCompressFactor=%d, latentDim=%d",
                  sampleRate, baseChunkSize, chunkCompressFactor, latentDim)
        }
        
        // Load unicode indexer
        let indexerPath = onnxDir.appendingPathComponent("unicode_indexer.json")
        if FileManager.default.fileExists(atPath: indexerPath.path) {
            let data = try Data(contentsOf: indexerPath)
            unicodeIndexer = try JSONDecoder().decode([Int64].self, from: data)
            NSLog("[SupertonicOnnx] Unicode indexer loaded: %d entries", unicodeIndexer.count)
        }
        
        // Load ONNX sessions
        let dpPath = onnxDir.appendingPathComponent("duration_predictor.onnx")
        let tePath = onnxDir.appendingPathComponent("text_encoder.onnx")
        let vePath = onnxDir.appendingPathComponent("vector_estimator.onnx")
        let vocPath = onnxDir.appendingPathComponent("vocoder.onnx")
        
        NSLog("[SupertonicOnnx] Loading duration predictor...")
        dpSession = try wrapper.createSession(modelPath: dpPath.path)
        
        NSLog("[SupertonicOnnx] Loading text encoder...")
        teSession = try wrapper.createSession(modelPath: tePath.path)
        
        NSLog("[SupertonicOnnx] Loading vector estimator...")
        veSession = try wrapper.createSession(modelPath: vePath.path)
        
        NSLog("[SupertonicOnnx] Loading vocoder...")
        vocSession = try wrapper.createSession(modelPath: vocPath.path)
        
        // Set voice styles directory
        let voiceStylesDir = baseDir.appendingPathComponent("voice_styles")
        if FileManager.default.fileExists(atPath: voiceStylesDir.path) {
            voiceDir = voiceStylesDir
        } else {
            voiceDir = baseDir
        }
        
        NSLog("[SupertonicOnnx] All models loaded successfully")
    }
    
    /// Synthesize text to audio samples.
    func synthesize(text: String, voiceName: String, speakerId: Int, speed: Float) throws -> (samples: [Float], sampleRate: Int) {
        // Thread logging: This should be on a background thread
        NSLog("[THREAD] SupertonicOnnxInference.synthesize: isMainThread=%@, thread=%@", 
              Thread.isMainThread ? "YES" : "NO", 
              Thread.current.description)
        
        lock.lock()
        defer { lock.unlock() }
        
        guard let wrapper = ortWrapper,
              let dpSession = dpSession,
              let teSession = teSession,
              let veSession = veSession,
              let vocSession = vocSession else {
            throw TtsError.modelNotLoaded
        }
        
        let lang = "en"
        let styleName = mapVoiceIdToStyleName(voiceName, speakerId: speakerId)
        NSLog("[SupertonicOnnx] Synthesizing: style=%@, speed=%.2f, text='%@'", styleName, speed, text)
        
        // Load voice style
        let style = try loadVoiceStyle(named: styleName)
        
        // Preprocess text
        let processedText = preprocessText(text, lang: lang)
        NSLog("[SupertonicOnnx] Processed: '%@'", processedText)
        
        // Build text inputs
        let (textIds, textMask) = buildTextInputs(text: processedText)
        let seqLen = textIds.count
        
        // Create tensors
        let textIdsTensor = try OrtTensor.createInt64(
            api: wrapper.api,
            data: textIds,
            shape: [1, Int64(seqLen)]
        )
        let textMaskTensor = try OrtTensor.createFloat(
            api: wrapper.api,
            data: textMask,
            shape: [1, 1, Int64(seqLen)]
        )
        let styleDpTensor = try OrtTensor.createFloat(
            api: wrapper.api,
            data: style.dp,
            shape: style.dpDims
        )
        let styleTtlTensor = try OrtTensor.createFloat(
            api: wrapper.api,
            data: style.ttl,
            shape: style.ttlDims
        )
        
        // Stage 1: Duration Predictor
        let dpOutputs = try dpSession.run(
            inputs: [
                "text_ids": textIdsTensor,
                "style_dp": styleDpTensor,
                "text_mask": textMaskTensor
            ],
            outputNames: ["duration"]
        )
        
        guard let durationTensor = dpOutputs["duration"] else {
            throw TtsError.synthesisFailure("Missing duration output")
        }
        let durationData = try durationTensor.getFloatData()
        var duration = durationData[0] / speed
        duration = max(duration, 0.05)  // Minimum duration
        NSLog("[SupertonicOnnx] Duration: %.3f seconds", duration)
        
        // Stage 2: Text Encoder
        let teOutputs = try teSession.run(
            inputs: [
                "text_ids": textIdsTensor,
                "style_ttl": styleTtlTensor,
                "text_mask": textMaskTensor
            ],
            outputNames: ["text_emb"]
        )
        
        guard let textEmbTensor = teOutputs["text_emb"] else {
            throw TtsError.synthesisFailure("Missing text_emb output")
        }
        
        // Stage 3: Vector Estimator (diffusion denoising)
        let (noisyLatent, latentMask, latentLen) = sampleNoisyLatent(duration: duration)
        
        var latent = noisyLatent
        let latentDimVal = latentDim * chunkCompressFactor
        let totalSteps = Self.defaultSteps
        
        for step in 0..<totalSteps {
            let latentTensor = try OrtTensor.createFloat(
                api: wrapper.api,
                data: latent,
                shape: [1, Int64(latentDimVal), Int64(latentLen)]
            )
            let latentMaskTensor = try OrtTensor.createFloat(
                api: wrapper.api,
                data: latentMask,
                shape: [1, 1, Int64(latentLen)]
            )
            let currentStepTensor = try OrtTensor.createFloat(
                api: wrapper.api,
                data: [Float(step)],
                shape: [1]
            )
            let totalStepTensor = try OrtTensor.createFloat(
                api: wrapper.api,
                data: [Float(totalSteps)],
                shape: [1]
            )
            
            let veOutputs = try veSession.run(
                inputs: [
                    "noisy_latent": latentTensor,
                    "text_emb": textEmbTensor,
                    "style_ttl": styleTtlTensor,
                    "latent_mask": latentMaskTensor,
                    "text_mask": textMaskTensor,
                    "current_step": currentStepTensor,
                    "total_step": totalStepTensor
                ],
                outputNames: ["denoised_latent"]
            )
            
            guard let denoisedTensor = veOutputs["denoised_latent"] else {
                throw TtsError.synthesisFailure("Missing denoised_latent output at step \(step)")
            }
            latent = try denoisedTensor.getFloatData()
        }
        
        // Stage 4: Vocoder
        let finalLatentTensor = try OrtTensor.createFloat(
            api: wrapper.api,
            data: latent,
            shape: [1, Int64(latentDimVal), Int64(latentLen)]
        )
        
        let vocOutputs = try vocSession.run(
            inputs: ["latent": finalLatentTensor],
            outputNames: ["wav_tts"]
        )
        
        guard let wavTensor = vocOutputs["wav_tts"] else {
            throw TtsError.synthesisFailure("Missing wav_tts output")
        }
        var wav = try wavTensor.getFloatData()
        
        // Trim to target duration
        let targetSamples = Int(duration * Float(sampleRate))
        if targetSamples > 0 && targetSamples < wav.count {
            wav = Array(wav.prefix(targetSamples))
        }
        
        // Normalize audio
        normalizeAudio(&wav)
        
        NSLog("[SupertonicOnnx] Synthesis complete: %d samples (%.2f seconds)", wav.count, Float(wav.count) / Float(sampleRate))
        
        return (wav, sampleRate)
    }
    
    func unload() {
        lock.lock()
        defer { lock.unlock() }
        
        dpSession = nil
        teSession = nil
        veSession = nil
        vocSession = nil
        ortWrapper = nil
        voiceCache.removeAll()
        NSLog("[SupertonicOnnx] Models unloaded")
    }
    
    // MARK: - Text Processing
    
    private func preprocessText(_ text: String, lang: String) -> String {
        var processed = text.decomposedStringWithCompatibilityMapping
        
        // Remove emojis
        processed = processed.unicodeScalars.filter { scalar in
            let value = scalar.value
            return !((value >= 0x1F600 && value <= 0x1F64F) ||
                     (value >= 0x1F300 && value <= 0x1F5FF) ||
                     (value >= 0x1F680 && value <= 0x1F6FF) ||
                     (value >= 0x1F700 && value <= 0x1F77F) ||
                     (value >= 0x1F780 && value <= 0x1F7FF) ||
                     (value >= 0x1F800 && value <= 0x1F8FF) ||
                     (value >= 0x1F900 && value <= 0x1F9FF) ||
                     (value >= 0x1FA00 && value <= 0x1FA6F) ||
                     (value >= 0x1FA70 && value <= 0x1FAFF) ||
                     (value >= 0x2600 && value <= 0x26FF) ||
                     (value >= 0x2700 && value <= 0x27BF) ||
                     (value >= 0x1F1E6 && value <= 0x1F1FF))
        }.map { String($0) }.joined()
        
        // Replace dashes and special chars
        let replacements: [(String, String)] = [
            ("–", "-"), ("‑", "-"), ("—", "-"), ("_", " "),
            ("\u{201C}", "\""), ("\u{201D}", "\""),
            ("\u{2018}", "'"), ("\u{2019}", "'"),
            ("´", "'"), ("`", "'"),
            ("[", " "), ("]", " "), ("|", " "), ("/", " "), ("#", " "),
            ("→", " "), ("←", " ")
        ]
        for (old, new) in replacements {
            processed = processed.replacingOccurrences(of: old, with: new)
        }
        
        // Remove special symbols
        for symbol in ["♥", "☆", "♡", "©", "\\"] {
            processed = processed.replacingOccurrences(of: symbol, with: "")
        }
        
        // Fix spacing
        processed = processed.replacingOccurrences(of: " ,", with: ",")
        processed = processed.replacingOccurrences(of: " .", with: ".")
        processed = processed.replacingOccurrences(of: " !", with: "!")
        processed = processed.replacingOccurrences(of: " ?", with: "?")
        
        // Remove extra whitespace
        let pattern = try! NSRegularExpression(pattern: "\\s+")
        let range = NSRange(processed.startIndex..., in: processed)
        processed = pattern.stringByReplacingMatches(in: processed, range: range, withTemplate: " ")
        processed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add period if no ending punctuation
        if !processed.isEmpty {
            let punctPattern = try! NSRegularExpression(pattern: "[.!?;:,'\"\\u201C\\u201D\\u2018\\u2019)\\]}…。」』】〉》›»]$")
            let punctRange = NSRange(processed.startIndex..., in: processed)
            if punctPattern.firstMatch(in: processed, range: punctRange) == nil {
                processed += "."
            }
        }
        
        // Wrap with language tags
        processed = "<\(lang)>\(processed)</\(lang)>"
        
        return processed
    }
    
    private func buildTextInputs(text: String) -> (textIds: [Int64], textMask: [Float]) {
        var textIds: [Int64] = []
        
        for scalar in text.unicodeScalars {
            let value = Int(scalar.value)
            if value < unicodeIndexer.count {
                textIds.append(unicodeIndexer[value])
            } else {
                textIds.append(-1)
            }
        }
        
        let textMask = [Float](repeating: 1.0, count: textIds.count)
        return (textIds, textMask)
    }
    
    private func sampleNoisyLatent(duration: Float) -> (latent: [Float], mask: [Float], len: Int) {
        let wavLen = Int(duration * Float(sampleRate))
        let chunkSize = baseChunkSize * chunkCompressFactor
        let latentLen = (wavLen + chunkSize - 1) / chunkSize
        let latentDimVal = latentDim * chunkCompressFactor
        
        // Generate random noise using Box-Muller transform
        var latent = [Float]()
        for _ in 0..<(latentDimVal * latentLen) {
            let u1 = Float.random(in: 0.0001...1.0)
            let u2 = Float.random(in: 0.0...1.0)
            let val = sqrt(-2.0 * log(u1)) * cos(2.0 * Float.pi * u2)
            latent.append(val)
        }
        
        let mask = [Float](repeating: 1.0, count: latentLen)
        
        return (latent, mask, latentLen)
    }
    
    private func mapVoiceIdToStyleName(_ voiceId: String, speakerId: Int) -> String {
        // Map voice ID like "supertonic_m1" or "supertonic_f1" to style names
        if voiceId.contains("_m") {
            let num = voiceId.split(separator: "_").last.flatMap { String($0).dropFirst() } ?? "1"
            return "M\(num)"
        } else if voiceId.contains("_f") {
            let num = voiceId.split(separator: "_").last.flatMap { String($0).dropFirst() } ?? "1"
            return "F\(num)"
        }
        // Default to speaker ID based
        return speakerId < 5 ? "M\(speakerId + 1)" : "F\(speakerId - 4)"
    }
    
    private func loadVoiceStyle(named name: String) throws -> VoiceStyle {
        // Check cache
        if let cached = voiceCache[name] {
            return cached
        }
        
        guard let voiceDir = voiceDir else {
            throw TtsError.invalidInput("Voice directory not set")
        }
        
        // Try different file name patterns
        let possibleNames = ["\(name).json", "\(name.lowercased()).json", "en_\(name.lowercased()).json"]
        var voiceURL: URL?
        
        for fileName in possibleNames {
            let url = voiceDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                voiceURL = url
                break
            }
        }
        
        guard let url = voiceURL else {
            throw TtsError.voiceNotLoaded(name)
        }
        
        let data = try Data(contentsOf: url)
        let voiceFile = try JSONDecoder().decode(VoiceFile.self, from: data)
        
        // Flatten the 3D arrays
        let ttlFlat = voiceFile.style_ttl.data.flatMap { $0.flatMap { $0 } }
        let dpFlat = voiceFile.style_dp.data.flatMap { $0.flatMap { $0 } }
        
        // Voice files already include batch dimension in dims (e.g., [1, 50, 256] and [1, 8, 16])
        let ttlDims = voiceFile.style_ttl.dims.map { Int64($0) }
        let dpDims = voiceFile.style_dp.dims.map { Int64($0) }
        
        let style = VoiceStyle(ttl: ttlFlat, ttlDims: ttlDims, dp: dpFlat, dpDims: dpDims)
        voiceCache[name] = style
        
        return style
    }
    
    private func normalizeAudio(_ samples: inout [Float]) {
        guard !samples.isEmpty else { return }
        
        let maxAbs = samples.map { abs($0) }.max() ?? 1.0
        if maxAbs > 0.01 {
            let scale = 0.95 / maxAbs
            for i in samples.indices {
                samples[i] *= scale
            }
        }
    }
}
