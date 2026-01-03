package com.example.platform_android_tts.services

import android.app.Service
import android.content.Intent
import android.os.IBinder
import kotlinx.coroutines.*
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Kokoro TTS Service running in its own process (:kokoro).
 * 
 * Provides synthesis using Kokoro sherpa-onnx TTS models.
 * Supports INT8 and FP32 model variants.
 */
class KokoroTtsService : Service() {
    
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    // Model state
    private var modelPath: String? = null
    private var isInitialized = false
    private var loadedVoices = mutableMapOf<String, Long>() // voiceId -> loadedTimestamp
    
    // Active synthesis jobs for cancellation
    private val activeJobs = mutableMapOf<String, Job>()
    
    override fun onBind(intent: Intent?): IBinder? {
        // For now, using MethodChannel instead of Binder
        // Will implement AIDL binding for production
        return null
    }
    
    override fun onDestroy() {
        scope.cancel()
        unloadAllModels()
        super.onDestroy()
    }
    
    /**
     * Initialize the Kokoro engine with the core model path.
     */
    suspend fun initEngine(corePath: String): Result<Unit> = runCatching {
        if (isInitialized && modelPath == corePath) {
            return Result.success(Unit)
        }
        
        // Verify model files exist
        val modelFile = File(corePath, "model.onnx")
        if (!modelFile.exists()) {
            throw IllegalStateException("Model file not found: ${modelFile.path}")
        }
        
        // TODO: Load ONNX Runtime and initialize model
        // This is where sherpa-onnx or ONNX Runtime would be initialized
        modelPath = corePath
        isInitialized = true
    }
    
    /**
     * Load a specific voice (Kokoro voices share the model, just track speaker ID).
     */
    suspend fun loadVoice(voiceId: String, speakerId: Int): Result<Unit> = runCatching {
        if (!isInitialized) {
            throw IllegalStateException("Engine not initialized")
        }
        
        loadedVoices[voiceId] = System.currentTimeMillis()
    }
    
    /**
     * Synthesize text to a WAV file.
     */
    suspend fun synthesize(
        voiceId: String,
        text: String,
        outputPath: String,
        requestId: String,
        speakerId: Int = 0,
        speed: Float = 1.0f
    ): SynthesisResult {
        if (!isInitialized) {
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
        
        val job = scope.launch {
            try {
                // Create temp file for atomic write
                val tmpFile = File("$outputPath.tmp")
                tmpFile.parentFile?.mkdirs()
                
                // TODO: Actually run ONNX inference here
                // For now, generate a silent WAV file for testing
                val sampleRate = 24000
                val durationSeconds = estimateDuration(text)
                val samples = (sampleRate * durationSeconds).toInt()
                
                // Generate PCM samples (silence for now)
                val pcmData = ShortArray(samples) { 0 }
                
                // Write WAV file
                writeWavFile(tmpFile, pcmData, sampleRate)
                
                // Check cancellation before atomic rename
                ensureActive()
                
                // Atomic rename
                tmpFile.renameTo(File(outputPath))
                
            } catch (e: CancellationException) {
                // Clean up temp file on cancellation
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
                val file = File(outputPath)
                val durationMs = estimateDurationMs(text)
                
                SynthesisResult(
                    success = true,
                    durationMs = durationMs,
                    sampleRate = 24000
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
     * Unload a specific voice.
     */
    fun unloadVoice(voiceId: String) {
        loadedVoices.remove(voiceId)
    }
    
    /**
     * Unload all models and reset state.
     */
    fun unloadAllModels() {
        loadedVoices.clear()
        isInitialized = false
        modelPath = null
        
        // Cancel all active jobs
        activeJobs.values.forEach { it.cancel() }
        activeJobs.clear()
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
            loadedModelCount = loadedVoices.size
        )
    }
    
    /**
     * Check if engine is ready.
     */
    fun isReady(): Boolean = isInitialized
    
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
