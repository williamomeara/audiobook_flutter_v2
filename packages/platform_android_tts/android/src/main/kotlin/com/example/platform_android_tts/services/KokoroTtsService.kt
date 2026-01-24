package com.example.platform_android_tts.services

import android.app.Service
import android.content.Intent
import android.os.IBinder
import com.example.platform_android_tts.sherpa.KokoroSherpaInference
import kotlinx.coroutines.*
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Kokoro TTS Service running in its own process (:kokoro).
 * 
 * Provides synthesis using Kokoro sherpa-onnx TTS models.
 * Kokoro is a multi-speaker model - all voices share a single model
 * with different speaker IDs.
 * 
 * Uses KokoroSherpaInference for actual TTS synthesis (via sherpa-onnx).
 */
class KokoroTtsService : Service() {
    
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    // Synthesis counter to prevent unload during active synthesis
    private val synthesisCounter = SynthesisCounter()
    
    // Model state - Kokoro uses single shared model
    private var modelPath: String? = null
    private var voicesPath: String? = null
    private var isInitialized = false
    private var loadedVoices = mutableMapOf<String, KokoroVoice>() // voiceId -> voice info
    
    // Single inference engine (shared model)
    private var inference: KokoroSherpaInference? = null
    
    // Active synthesis jobs for cancellation
    private val activeJobs = mutableMapOf<String, Job>()
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        scope.cancel()
        unloadAllModels()
        super.onDestroy()
    }
    
    /**
     * Initialize the Kokoro engine with the core model path.
     * 
     * @param corePath Path to directory containing model.onnx, tokens.txt, espeak-ng-data/
     * @param voicesFile Path to voices.bin file with voice embeddings
     */
    suspend fun initEngine(corePath: String, voicesFile: String? = null): Result<Unit> = runCatching {
        if (isInitialized && modelPath == corePath) {
            return Result.success(Unit)
        }
        
        // Verify model files exist - support both model.onnx and model.int8.onnx
        val modelFile = findModelFile(corePath)
        if (modelFile == null || !modelFile.exists()) {
            throw IllegalStateException("Model file not found in: $corePath")
        }
        
        // Look for voices file in expected locations
        val actualVoicesPath = voicesFile ?: findVoicesFile(corePath)
        if (actualVoicesPath == null || !File(actualVoicesPath).exists()) {
            throw IllegalStateException("Voices file not found in $corePath")
        }
        
        // Initialize sherpa-onnx inference engine
        val engine = KokoroSherpaInference(corePath, actualVoicesPath)
        engine.initialize().getOrThrow()
        
        inference = engine
        modelPath = corePath
        voicesPath = actualVoicesPath
        isInitialized = true
    }
    
    /**
     * Find the ONNX model file in the core path.
     */
    private fun findModelFile(corePath: String): File? {
        val standardModel = File(corePath, "model.onnx")
        if (standardModel.exists()) return standardModel
        
        val int8Model = File(corePath, "model.int8.onnx")
        if (int8Model.exists()) return int8Model
        
        // Look for any .onnx file
        return File(corePath).listFiles { file ->
            file.isFile && file.name.endsWith(".onnx")
        }?.maxByOrNull { it.length() }
    }
    
    /**
     * Find the voices.bin file in expected locations.
     */
    private fun findVoicesFile(corePath: String): String? {
        val candidates = listOf(
            "$corePath/voices.bin",
            "$corePath/../voices.bin",
            "$corePath/voices/voices.bin"
        )
        return candidates.firstOrNull { File(it).exists() }
    }
    
    /**
     * Load a specific voice (register speaker ID mapping).
     */
    suspend fun loadVoice(voiceId: String, speakerId: Int): Result<Unit> = runCatching {
        if (!isInitialized) {
            throw IllegalStateException("Engine not initialized")
        }
        
        loadedVoices[voiceId] = KokoroVoice(
            voiceId = voiceId,
            speakerId = speakerId,
            lastUsed = System.currentTimeMillis()
        )
    }
    
    /**
     * Synthesize text to a WAV file.
     * 
     * Note: Kokoro uses 24000 Hz sample rate.
     */
    suspend fun synthesize(
        voiceId: String,
        text: String,
        outputPath: String,
        requestId: String,
        speakerId: Int = 0,
        speed: Float = 1.0f
    ): SynthesisResult {
        val engine = inference
        
        if (!isInitialized || engine == null) {
            return SynthesisResult(
                success = false,
                errorCode = ErrorCode.MODEL_MISSING,
                errorMessage = "Engine not initialized"
            )
        }
        
        if (text.isBlank()) {
            return SynthesisResult(
                success = false,
                errorCode = ErrorCode.INVALID_INPUT,
                errorMessage = "Empty text"
            )
        }
        
        // Track active synthesis to prevent unload during operation
        synthesisCounter.increment()
        
        // Get speaker ID from loaded voice or use provided ID
        val voice = loadedVoices[voiceId]
        val actualSpeakerId = voice?.speakerId ?: speakerId
        
        val job = scope.launch {
            try {
                val tmpFile = File("$outputPath.tmp")
                tmpFile.parentFile?.mkdirs()
                
                // Run sherpa-onnx inference (only once!)
                val samples = engine.synthesize(text, actualSpeakerId, speed).getOrThrow()
                val sampleRate = engine.getSampleRate()
                
                // Convert float samples to 16-bit PCM
                val pcmData = samples.map { sample ->
                    (sample * 32767).toInt().coerceIn(-32768, 32767).toShort()
                }.toShortArray()
                
                writeWavFile(tmpFile, pcmData, sampleRate)
                
                ensureActive()
                tmpFile.renameTo(File(outputPath))
                
            } catch (e: CancellationException) {
                File("$outputPath.tmp").delete()
                throw e
            }
        }
        
        activeJobs[requestId] = job
        
        return try {
            job.join()
            
            if (job.isCancelled) {
                SynthesisResult(
                    success = false,
                    errorCode = ErrorCode.CANCELLED,
                    errorMessage = "Synthesis cancelled"
                )
            } else {
                voice?.lastUsed = System.currentTimeMillis()
                
                // Calculate duration from output file size (avoids double synthesis)
                val sampleRate = engine.getSampleRate()
                val outputFile = File(outputPath)
                val durationMs = if (outputFile.exists()) {
                    val fileSize = outputFile.length()
                    val dataSize = fileSize - 44 // WAV header is 44 bytes
                    val sampleCount = dataSize / 2 // 16-bit samples = 2 bytes each
                    (sampleCount * 1000 / sampleRate).toInt()
                } else {
                    estimateDurationMs(text)
                }
                
                SynthesisResult(
                    success = true,
                    durationMs = durationMs,
                    sampleRate = sampleRate
                )
            }
        } catch (e: Exception) {
            SynthesisResult(
                success = false,
                errorCode = mapExceptionToErrorCode(e),
                errorMessage = e.message
            )
        } finally {
            activeJobs.remove(requestId)
            synthesisCounter.decrement()
        }
    }
    
    /**
     * Cancel an in-flight synthesis.
     */
    fun cancelSynthesis(requestId: String) {
        activeJobs[requestId]?.cancel()
        activeJobs.remove(requestId)
    }
    
    /**
     * Unload a specific voice (just removes from tracking).
     * Waits for any active synthesis to complete first.
     */
    fun unloadVoice(voiceId: String) {
        // Wait for any active synthesis to complete (max 5 seconds)
        if (!synthesisCounter.waitUntilIdle(timeoutMs = 5000)) {
            android.util.Log.w("KokoroTtsService", "Timeout waiting for synthesis to complete before unload")
        }
        loadedVoices.remove(voiceId)
    }
    
    /**
     * Unload all models and reset state.
     * Waits for any active synthesis to complete first.
     */
    fun unloadAllModels() {
        // Wait for any active synthesis to complete (max 5 seconds)
        if (!synthesisCounter.waitUntilIdle(timeoutMs = 5000)) {
            android.util.Log.w("KokoroTtsService", "Timeout waiting for synthesis to complete before unloadAll")
        }
        
        inference?.dispose()
        inference = null
        loadedVoices.clear()
        isInitialized = false
        modelPath = null
        voicesPath = null
        
        activeJobs.values.forEach { it.cancel() }
        activeJobs.clear()
    }
    
    /**
     * Unload least recently used voice.
     */
    fun unloadLeastUsedVoice(): String? {
        val lru = loadedVoices.minByOrNull { it.value.lastUsed }
        return lru?.let {
            loadedVoices.remove(it.key)
            it.key
        }
    }
    
    /**
     * Get memory info.
     */
    fun getMemoryInfo(): ServiceMemoryInfo {
        val runtime = Runtime.getRuntime()
        val availableMB = ((runtime.maxMemory() - runtime.totalMemory()) / (1024 * 1024)).toInt()
        val totalMB = (runtime.maxMemory() / (1024 * 1024)).toInt()
        
        return ServiceMemoryInfo(
            availableMB = availableMB,
            totalMB = totalMB,
            loadedModelCount = if (isInitialized) 1 else 0
        )
    }
    
    /**
     * Check if engine is ready.
     */
    fun isReady(): Boolean = isInitialized && inference?.isReady() == true
    
    /**
     * Check if a voice is loaded.
     */
    fun isVoiceLoaded(voiceId: String): Boolean = loadedVoices.containsKey(voiceId)
    
    // Private helpers
    
    private fun estimateDuration(text: String): Float {
        // Rough estimate: 150 words per minute, average 5 characters per word
        val words = text.length / 5.0f
        return words / 2.5f // 150 wpm = 2.5 words per second
    }
    
    private fun estimateDurationMs(text: String): Int {
        return (estimateDuration(text) * 1000).toInt()
    }
    
    private fun writeWavFile(file: File, samples: ShortArray, sampleRate: Int) {
        val numChannels = 1
        val bitsPerSample = 16
        val byteRate = sampleRate * numChannels * bitsPerSample / 8
        val blockAlign = numChannels * bitsPerSample / 8
        val dataSize = samples.size * 2
        val fileSize = 36 + dataSize
        
        RandomAccessFile(file, "rw").use { raf ->
            // RIFF header
            raf.writeBytes("RIFF")
            raf.writeIntLE(fileSize)
            raf.writeBytes("WAVE")
            
            // fmt chunk
            raf.writeBytes("fmt ")
            raf.writeIntLE(16) // chunk size
            raf.writeShortLE(1) // audio format (PCM)
            raf.writeShortLE(numChannels)
            raf.writeIntLE(sampleRate)
            raf.writeIntLE(byteRate)
            raf.writeShortLE(blockAlign)
            raf.writeShortLE(bitsPerSample)
            
            // data chunk
            raf.writeBytes("data")
            raf.writeIntLE(dataSize)
            
            // Write samples
            val buffer = ByteBuffer.allocate(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
            samples.forEach { buffer.putShort(it) }
            raf.write(buffer.array())
        }
    }
    
    private fun RandomAccessFile.writeIntLE(value: Int) {
        val buffer = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(value)
        write(buffer.array())
    }
    
    private fun RandomAccessFile.writeShortLE(value: Int) {
        val buffer = ByteBuffer.allocate(2).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putShort(value.toShort())
        write(buffer.array())
    }
    
    private fun mapExceptionToErrorCode(e: Exception): ErrorCode {
        return when {
            e is OutOfMemoryError -> ErrorCode.OUT_OF_MEMORY
            e is CancellationException -> ErrorCode.CANCELLED
            e.message?.contains("model", ignoreCase = true) == true -> ErrorCode.MODEL_MISSING
            else -> ErrorCode.INFERENCE_FAILED
        }
    }
}

/**
 * Result of a synthesis operation.
 */
data class SynthesisResult(
    val success: Boolean,
    val durationMs: Int? = null,
    val sampleRate: Int? = null,
    val errorCode: ErrorCode? = null,
    val errorMessage: String? = null
)

/**
 * Memory information (service-level type).
 */
data class ServiceMemoryInfo(
    val availableMB: Int,
    val totalMB: Int,
    val loadedModelCount: Int
)

/**
 * Error codes for synthesis operations.
 */
enum class ErrorCode {
    NONE,
    MODEL_MISSING,
    MODEL_CORRUPTED,
    OUT_OF_MEMORY,
    INFERENCE_FAILED,
    CANCELLED,
    RUNTIME_CRASH,
    INVALID_INPUT,
    FILE_WRITE_ERROR,
    UNKNOWN
}

/**
 * Kokoro voice state.
 */
data class KokoroVoice(
    val voiceId: String,
    val speakerId: Int,
    var lastUsed: Long
)
