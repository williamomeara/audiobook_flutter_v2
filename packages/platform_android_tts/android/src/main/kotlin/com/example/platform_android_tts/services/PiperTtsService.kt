package com.example.platform_android_tts.services

import android.app.Service
import android.content.Intent
import android.os.IBinder
import com.example.platform_android_tts.sherpa.PiperSherpaInference
import kotlinx.coroutines.*
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Semaphore

/**
 * Piper TTS Service running in its own process (:piper).
 * 
 * Provides synthesis using Piper VITS-based TTS models.
 * Each voice has its own ONNX model file.
 * 
 * Uses PiperSherpaInference for actual TTS synthesis (via sherpa-onnx).
 */
class PiperTtsService : Service() {
    
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    // Synthesis counter to prevent unload during active synthesis
    private val synthesisCounter = SynthesisCounter()
    
    // Model state - Piper has per-voice models
    @Volatile private var isInitialized = false
    private val loadedModels = ConcurrentHashMap<String, PiperVoiceModel>()
    
    // Inference engines per voice (Piper has separate model per voice)
    private val inferenceEngines = ConcurrentHashMap<String, PiperSherpaInference>()
    
    // Active synthesis jobs for cancellation (thread-safe)
    private val activeJobs = ConcurrentHashMap<String, Job>()
    
    // Limit concurrent synthesis to prevent resource exhaustion
    private val synthesisPermits = Semaphore(4)
    
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
        
        // Verify model path exists
        val modelDir = File(modelPath)
        if (!modelDir.exists() || !modelDir.isDirectory) {
            throw IllegalStateException("Model directory not found: $modelPath")
        }
        
        // PiperSherpaInference handles flexible model file discovery internally
        // (supports both model.onnx and {modelKey}.onnx formats)
        
        // Initialize the sherpa-onnx inference engine for this voice
        val inference = PiperSherpaInference(modelPath)
        inference.initialize().getOrThrow()
        
        inferenceEngines[voiceId] = inference
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
        val inference = inferenceEngines[voiceId]
        
        if (model == null || inference == null) {
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
        
        // Track active synthesis to prevent unload during operation
        synthesisCounter.increment()
        
        // Limit concurrent synthesis
        if (!synthesisPermits.tryAcquire()) {
            synthesisCounter.decrement()
            return SynthesisResult(
                success = false,
                errorCode = ErrorCode.BUSY,
                errorMessage = "Too many concurrent synthesis requests"
            )
        }
        
        val job = scope.launch {
            try {
                val tmpFile = File("$outputPath.tmp")
                val parentDir = tmpFile.parentFile
                if (parentDir != null && !parentDir.exists() && !parentDir.mkdirs()) {
                    throw IOException("Failed to create output directory: $parentDir")
                }
                
                // Run sherpa-onnx inference
                val samples = inference.synthesize(text, speed).getOrThrow()
                val sampleRate = inference.getSampleRate()
                
                // Convert float samples to 16-bit PCM
                val pcmData = samples.map { sample ->
                    (sample * 32767).toInt().coerceIn(-32768, 32767).toShort()
                }.toShortArray()
                
                writeWavFile(tmpFile, pcmData, sampleRate)
                
                ensureActive()
                val finalFile = File(outputPath)
                if (!tmpFile.renameTo(finalFile)) {
                    // Fallback: copy and delete
                    tmpFile.copyTo(finalFile, overwrite = true)
                    tmpFile.delete()
                }
                
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
                
                // Calculate duration from output file size (avoids double synthesis)
                val sampleRate = inference.getSampleRate()
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
            synthesisPermits.release()
        }
    }
    
    /**
     * Cancel an in-flight synthesis.
     */
    fun cancelSynthesis(requestId: String) {
        // Remove first, then cancel (prevents race with completion)
        val job = activeJobs.remove(requestId) ?: return
        job.cancel()
    }
    
    /**
     * Unload a specific voice.
     * Waits for any active synthesis to complete first.
     */
    fun unloadVoice(voiceId: String) {
        // Wait for any active synthesis to complete (max 5 seconds)
        if (!synthesisCounter.waitUntilIdle(timeoutMs = 5000)) {
            android.util.Log.w("PiperTtsService", "Timeout waiting for synthesis to complete before unload")
        }
        inferenceEngines[voiceId]?.dispose()
        inferenceEngines.remove(voiceId)
        loadedModels.remove(voiceId)
    }
    
    /**
     * Unload all models and reset state.
     * Waits for any active synthesis to complete first.
     */
    fun unloadAllModels() {
        // Wait for any active synthesis to complete (max 5 seconds)
        if (!synthesisCounter.waitUntilIdle(timeoutMs = 5000)) {
            android.util.Log.w("PiperTtsService", "Timeout waiting for synthesis to complete before unloadAll")
        }
        
        inferenceEngines.values.forEach { it.dispose() }
        inferenceEngines.clear()
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
            unloadVoice(it.key)
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
