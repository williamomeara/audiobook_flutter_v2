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
 * Piper TTS Service running in its own process (:piper).
 * 
 * Provides synthesis using Piper VITS-based TTS models.
 * Each voice has its own ONNX model file.
 */
class PiperTtsService : Service() {
    
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    // Model state - Piper has per-voice models
    private var isInitialized = false
    private val loadedModels = mutableMapOf<String, PiperVoiceModel>()
    
    // Active synthesis jobs for cancellation
    private val activeJobs = mutableMapOf<String, Job>()
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        scope.cancel()
        unloadAllModels()
        super.onDestroy()
    }
    
    /**
     * Initialize the Piper engine.
     */
    suspend fun initEngine(corePath: String): Result<Unit> = runCatching {
        // Piper doesn't need a shared core - each voice is self-contained
        isInitialized = true
    }
    
    /**
     * Load a specific Piper voice model.
     */
    suspend fun loadVoice(voiceId: String, modelPath: String): Result<Unit> = runCatching {
        if (loadedModels.containsKey(voiceId)) {
            loadedModels[voiceId]?.lastUsed = System.currentTimeMillis()
            return Result.success(Unit)
        }
        
        // Verify model files exist
        val onnxFile = File(modelPath, "model.onnx")
        val configFile = File(modelPath, "model.onnx.json")
        
        if (!onnxFile.exists()) {
            throw IllegalStateException("Model file not found: ${onnxFile.path}")
        }
        
        // TODO: Load the ONNX model using piper-phonemize + ONNX Runtime
        loadedModels[voiceId] = PiperVoiceModel(
            voiceId = voiceId,
            modelPath = modelPath,
            lastUsed = System.currentTimeMillis()
        )
    }
    
    /**
     * Synthesize text to a WAV file.
     * 
     * Note: Piper typically uses 22050 Hz sample rate.
     */
    suspend fun synthesize(
        voiceId: String,
        text: String,
        outputPath: String,
        requestId: String,
        speed: Float = 1.0f
    ): SynthesisResult {
        val model = loadedModels[voiceId]
        if (model == null) {
            return SynthesisResult(
                success = false,
                errorCode = ErrorCode.MODEL_MISSING,
                errorMessage = "Voice not loaded: $voiceId"
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
                val tmpFile = File("$outputPath.tmp")
                tmpFile.parentFile?.mkdirs()
                
                // TODO: Run phonemizer + ONNX inference
                // For now, generate a silent WAV file for testing
                val sampleRate = 22050 // Piper default
                val durationSeconds = estimateDuration(text)
                val samples = (sampleRate * durationSeconds).toInt()
                
                val pcmData = ShortArray(samples) { 0 }
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
                model.lastUsed = System.currentTimeMillis()
                
                SynthesisResult(
                    success = true,
                    durationMs = estimateDurationMs(text),
                    sampleRate = 22050
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
        loadedModels.remove(voiceId)
    }
    
    /**
     * Unload all models and reset state.
     */
    fun unloadAllModels() {
        loadedModels.clear()
        isInitialized = false
        
        activeJobs.values.forEach { it.cancel() }
        activeJobs.clear()
    }
    
    /**
     * Unload least recently used voice.
     */
    fun unloadLeastUsedVoice(): String? {
        val lru = loadedModels.minByOrNull { it.value.lastUsed }
        return lru?.let {
            loadedModels.remove(it.key)
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
            loadedModelCount = loadedModels.size
        )
    }
    
    fun isReady(): Boolean = isInitialized
    fun isVoiceLoaded(voiceId: String): Boolean = loadedModels.containsKey(voiceId)
    
    // Private helpers
    
    private fun estimateDuration(text: String): Float {
        val words = text.length / 5.0f
        return words / 2.5f
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
            raf.writeBytes("RIFF")
            raf.writeIntLE(fileSize)
            raf.writeBytes("WAVE")
            raf.writeBytes("fmt ")
            raf.writeIntLE(16)
            raf.writeShortLE(1)
            raf.writeShortLE(numChannels)
            raf.writeIntLE(sampleRate)
            raf.writeIntLE(byteRate)
            raf.writeShortLE(blockAlign)
            raf.writeShortLE(bitsPerSample)
            raf.writeBytes("data")
            raf.writeIntLE(dataSize)
            
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
 * Piper voice model state.
 */
data class PiperVoiceModel(
    val voiceId: String,
    val modelPath: String,
    var lastUsed: Long
)
