package com.example.platform_android_tts.sherpa

import com.k2fsa.sherpa.onnx.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Kokoro TTS inference using sherpa-onnx.
 * 
 * Kokoro is a multi-speaker TTS model that uses voice embeddings for
 * different speaker styles. All speakers share a single model.
 */
class KokoroSherpaInference(
    private val modelPath: String,
    private val voicesPath: String,
    private val numThreads: Int? = null  // null = auto-detect
) {
    companion object {
        /**
         * Determine optimal thread count based on device CPU cores.
         * Kokoro benefits from more threads (up to 4) on high-core devices.
         */
        fun getOptimalThreadCount(): Int {
            val cpuCores = Runtime.getRuntime().availableProcessors()
            return when {
                cpuCores >= 8 -> 4  // High-end devices: use 4 threads
                cpuCores >= 6 -> 3  // Mid-range: use 3 threads
                cpuCores >= 4 -> 2  // Budget: use 2 threads
                else -> 1           // Low-end: single thread
            }
        }
    }
    private var tts: OfflineTts? = null
    
    /**
     * Initialize the Kokoro TTS engine.
     * 
     * Expected files:
     * - modelPath/model.onnx or model.int8.onnx: The Kokoro ONNX model
     * - modelPath/tokens.txt: Token vocabulary
     * - modelPath/espeak-ng-data/: eSpeak-ng data directory
     * - voicesPath: Path to voices.bin (voice embeddings)
     */
    suspend fun initialize(): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val modelFile = findModelFile()
            if (modelFile == null || !modelFile.exists()) {
                throw IllegalStateException("No ONNX model file found in $modelPath")
            }
            
            // Use configured threads or auto-detect optimal count
            val threads = numThreads ?: getOptimalThreadCount()
            
            android.util.Log.d("KokoroSherpaInference", "Initializing with model: ${modelFile.absolutePath}")
            android.util.Log.d("KokoroSherpaInference", "Voices: $voicesPath")
            android.util.Log.d("KokoroSherpaInference", "CPU cores: ${Runtime.getRuntime().availableProcessors()}, using $threads threads")
            
            val config = OfflineTtsConfig(
                model = OfflineTtsModelConfig(
                    kokoro = OfflineTtsKokoroModelConfig(
                        model = modelFile.absolutePath,
                        voices = voicesPath,
                        tokens = "$modelPath/tokens.txt",
                        dataDir = "$modelPath/espeak-ng-data",
                        lang = "en-us"
                    ),
                    numThreads = threads,
                    debug = false
                )
            )
            tts = OfflineTts(config = config)
            android.util.Log.d("KokoroSherpaInference", "Kokoro initialized, sampleRate=${tts?.sampleRate()}")
            Unit
        }
    }
    
    /**
     * Find the ONNX model file in the model directory.
     * Supports model.onnx, model.int8.onnx, and other .onnx files.
     */
    private fun findModelFile(): File? {
        val modelDir = File(modelPath)
        
        // Check for model.onnx first (standard naming)
        val standardModel = File(modelPath, "model.onnx")
        if (standardModel.exists()) {
            return standardModel
        }
        
        // Check for model.int8.onnx (sherpa-onnx quantized format)
        val int8Model = File(modelPath, "model.int8.onnx")
        if (int8Model.exists()) {
            return int8Model
        }
        
        // Look for any .onnx file, prefer larger files (likely the main model)
        val onnxFiles = modelDir.listFiles { file -> 
            file.isFile && file.name.endsWith(".onnx")
        }?.sortedByDescending { it.length() }
        
        return onnxFiles?.firstOrNull()
    }
    
    /**
     * Synthesize text to audio samples.
     * 
     * @param text The text to synthesize
     * @param speakerId The speaker ID (0-10 for Kokoro voices)
     * @param speed Speech rate multiplier (1.0 = normal speed)
     * @return FloatArray of audio samples at the model's sample rate
     */
    suspend fun synthesize(
        text: String,
        speakerId: Int = 0,
        speed: Float = 1.0f
    ): Result<FloatArray> = withContext(Dispatchers.Default) {
        runCatching {
            val engine = tts ?: throw IllegalStateException("Engine not initialized")
            val audio = engine.generate(text = text, sid = speakerId, speed = speed)
            audio.samples
        }
    }
    
    /**
     * Get the sample rate of the loaded model.
     */
    fun getSampleRate(): Int {
        return tts?.sampleRate() ?: 24000  // Kokoro default
    }
    
    /**
     * Check if the engine is ready.
     */
    fun isReady(): Boolean = tts != null
    
    /**
     * Release resources.
     */
    fun dispose() {
        tts?.release()
        tts = null
    }
}
