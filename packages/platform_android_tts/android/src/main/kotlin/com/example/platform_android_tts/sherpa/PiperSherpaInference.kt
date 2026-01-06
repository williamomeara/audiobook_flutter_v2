package com.example.platform_android_tts.sherpa

import com.k2fsa.sherpa.onnx.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

/**
 * Piper TTS inference using sherpa-onnx.
 * 
 * Piper uses VITS-based models which are directly supported by sherpa-onnx.
 * Each voice has its own self-contained ONNX model.
 * 
 * This wrapper handles conversion between standard Piper model format
 * (model.onnx + model.onnx.json) and sherpa-onnx format (model.onnx + tokens.txt + espeak-ng-data).
 */
class PiperSherpaInference(
    private val modelPath: String
) {
    private var tts: OfflineTts? = null
    
    /**
     * Initialize the Piper TTS engine with the model at the specified path.
     * 
     * Expected files in modelPath (standard Piper format):
     * - model.onnx: The VITS ONNX model
     * - model.onnx.json: Config with phoneme_id_map
     * 
     * OR (sherpa-onnx format):
     * - model.onnx: The VITS ONNX model
     * - tokens.txt: Token vocabulary
     * - espeak-ng-data/: eSpeak-ng data directory
     */
    suspend fun initialize(): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            // Check for sherpa-onnx format first
            val tokensFile = File(modelPath, "tokens.txt")
            val espeakDataDir = File(modelPath, "espeak-ng-data")
            
            // Find the model file - sherpa-onnx uses {modelKey}.onnx format
            val modelFile = findModelFile()
            if (modelFile == null || !modelFile.exists()) {
                throw IllegalStateException("No ONNX model file found in $modelPath")
            }
            
            if (!tokensFile.exists()) {
                // Try to generate tokens.txt from Piper JSON config
                val jsonConfig = File(modelPath, "model.onnx.json")
                val modelJsonConfig = File(modelFile.absolutePath + ".json")
                val configFile = when {
                    jsonConfig.exists() -> jsonConfig
                    modelJsonConfig.exists() -> modelJsonConfig
                    else -> null
                }
                
                if (configFile != null) {
                    android.util.Log.d("PiperSherpaInference", "Generating tokens.txt from ${configFile.name}")
                    generateTokensFile(configFile, tokensFile)
                } else {
                    throw IllegalStateException("Neither tokens.txt nor .onnx.json config found in $modelPath")
                }
            }
            
            // Determine data directory - can be empty if not available
            val dataDir = if (espeakDataDir.exists()) espeakDataDir.absolutePath else ""
            
            android.util.Log.d("PiperSherpaInference", "Creating OfflineTts config for: $modelPath")
            android.util.Log.d("PiperSherpaInference", "  model: ${modelFile.absolutePath}")
            android.util.Log.d("PiperSherpaInference", "  tokens: ${tokensFile.absolutePath}")
            android.util.Log.d("PiperSherpaInference", "  dataDir: $dataDir")
            
            val config = OfflineTtsConfig(
                model = OfflineTtsModelConfig(
                    vits = OfflineTtsVitsModelConfig(
                        model = modelFile.absolutePath,
                        tokens = tokensFile.absolutePath,
                        dataDir = dataDir
                    ),
                    numThreads = 2,
                    debug = false
                )
            )
            
            android.util.Log.d("PiperSherpaInference", "Creating OfflineTts instance...")
            tts = OfflineTts(config = config)
            android.util.Log.d("PiperSherpaInference", "OfflineTts created successfully, sampleRate=${tts?.sampleRate()}")
            Unit
        }
    }
    
    /**
     * Find the ONNX model file in the model directory.
     * Supports both model.onnx (standard) and {modelKey}.onnx (sherpa-onnx) formats.
     */
    private fun findModelFile(): File? {
        val modelDir = File(modelPath)
        
        // First check for model.onnx
        val standardModel = File(modelPath, "model.onnx")
        if (standardModel.exists()) {
            return standardModel
        }
        
        // Look for any .onnx file (sherpa-onnx format uses {modelKey}.onnx)
        val onnxFiles = modelDir.listFiles { file -> 
            file.isFile && file.name.endsWith(".onnx") && !file.name.contains("-")
        }?.sortedByDescending { it.length() }
        
        if (!onnxFiles.isNullOrEmpty()) {
            return onnxFiles.first()
        }
        
        // Finally check for any .onnx file (including those with dashes like en_GB-alan-medium.onnx)
        val allOnnxFiles = modelDir.listFiles { file -> 
            file.isFile && file.name.endsWith(".onnx")
        }?.sortedByDescending { it.length() }
        
        return allOnnxFiles?.firstOrNull()
    }
    
    /**
     * Generate tokens.txt from Piper's model.onnx.json phoneme_id_map.
     */
    private fun generateTokensFile(jsonConfig: File, tokensFile: File) {
        val jsonText = jsonConfig.readText()
        val json = JSONObject(jsonText)
        val phonemeIdMap = json.getJSONObject("phoneme_id_map")
        
        // Build a sorted list of token entries
        val tokenEntries = mutableListOf<Pair<Int, String>>()
        
        for (key in phonemeIdMap.keys()) {
            val idArray = phonemeIdMap.getJSONArray(key)
            // Each phoneme maps to an array of IDs, take the first one
            val id = idArray.getInt(0)
            tokenEntries.add(id to key)
        }
        
        // Sort by ID and write to tokens.txt
        tokenEntries.sortBy { it.first }
        
        val tokensContent = tokenEntries.joinToString("\n") { (id, token) ->
            // Format: token id (space separated)
            // Some special characters need escaping
            val escapedToken = when (token) {
                " " -> "<space>"
                "\n" -> "<newline>"
                "\t" -> "<tab>"
                else -> token
            }
            "$escapedToken $id"
        }
        
        tokensFile.writeText(tokensContent)
        android.util.Log.d("PiperSherpaInference", "Generated tokens.txt with ${tokenEntries.size} entries")
    }
    
    /**
     * Synthesize text to audio samples.
     * 
     * @param text The text to synthesize
     * @param speed Speech rate multiplier (1.0 = normal speed)
     * @return FloatArray of audio samples at the model's sample rate
     */
    suspend fun synthesize(
        text: String,
        speed: Float = 1.0f
    ): Result<FloatArray> = withContext(Dispatchers.Default) {
        runCatching {
            val engine = tts ?: throw IllegalStateException("Engine not initialized")
            android.util.Log.d("PiperSherpaInference", "Synthesizing text (${text.length} chars) at speed $speed")
            val audio = engine.generate(text = text, speed = speed)
            android.util.Log.d("PiperSherpaInference", "Generated ${audio.samples.size} samples")
            audio.samples
        }
    }
    
    /**
     * Get the sample rate of the loaded model.
     */
    fun getSampleRate(): Int {
        return tts?.sampleRate() ?: 22050  // Piper default
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
