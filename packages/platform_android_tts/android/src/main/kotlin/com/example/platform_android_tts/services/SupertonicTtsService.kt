package com.example.platform_android_tts.services

import android.app.Service
import android.content.Intent
import android.os.IBinder
import com.example.platform_android_tts.onnx.SupertonicNative
import kotlinx.coroutines.*
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Semaphore

/**
 * Supertonic TTS Service running in its own process (:supertonic).
 * 
 * Provides synthesis using Supertonic ONNX TTS models via JNI.
 * Uses speaker embeddings for voice cloning/variation.
 */
class SupertonicTtsService : Service() {
    
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    // Synthesis counter to prevent unload during active synthesis
    private val synthesisCounter = SynthesisCounter()
    
    // Model state
    private var modelPath: String? = null
    @Volatile private var isInitialized = false
    private val loadedSpeakers = ConcurrentHashMap<String, SupertonicSpeaker>()
    
    // Active synthesis jobs for cancellation (thread-safe)
    private val activeJobs = ConcurrentHashMap<String, Job>()
    
    // Limit concurrent synthesis to prevent resource exhaustion
    private val synthesisPermits = Semaphore(4)
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        scope.cancel()
        unloadAllModels()
        // Dispose native resources
        if (isInitialized) {
            SupertonicNative.dispose()
        }
        super.onDestroy()
    }
    
    /**
     * Initialize the Supertonic engine with the core model path.
     * 
     * Expected structure:
     * corePath/
     *   onnx/
     *     text_encoder.onnx
     *     duration_predictor.onnx
     *     vector_estimator.onnx
     *     vocoder.onnx
     *     unicode_indexer.json
     *   voice_styles/
     *     M1.json, M2.json, ..., F1.json, F2.json, ...
     */
    suspend fun initEngine(corePath: String): Result<Unit> = runCatching {
        if (isInitialized && modelPath == corePath) {
            return Result.success(Unit)
        }
        
        // Check for native library availability
        if (!SupertonicNative.isNativeAvailable()) {
            throw IllegalStateException("Supertonic native library not available")
        }
        
        // Verify model files exist
        val textEncoder = File(corePath, "onnx/text_encoder.onnx")
        if (!textEncoder.exists()) {
            throw IllegalStateException("Model file not found: ${textEncoder.path}")
        }
        
        // Initialize native engine
        val success = SupertonicNative.initialize(corePath)
        if (!success) {
            throw IllegalStateException("Failed to initialize Supertonic native engine at: $corePath")
        }
        
        modelPath = corePath
        isInitialized = true
        android.util.Log.i("SupertonicTtsService", "Engine initialized at: $corePath")
    }
    
    /**
     * Load a speaker with optional embedding.
     */
    suspend fun loadVoice(
        voiceId: String, 
        speakerId: Int,
        embeddingPath: String? = null
    ): Result<Unit> = runCatching {
        if (!isInitialized) {
            throw IllegalStateException("Engine not initialized")
        }
        
        // TODO: Load speaker embedding if provided
        loadedSpeakers[voiceId] = SupertonicSpeaker(
            voiceId = voiceId,
            speakerId = speakerId,
            embeddingPath = embeddingPath,
            lastUsed = System.currentTimeMillis()
        )
    }
    
    /**
     * Synthesize text to a WAV file using Supertonic native engine.
     */
    suspend fun synthesize(
        voiceId: String,
        text: String,
        outputPath: String,
        requestId: String,
        speakerId: Int = 0,
        speed: Float = 1.0f
    ): SynthesisResult {
        if (!isInitialized || !SupertonicNative.isReady()) {
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
        
        // Limit concurrent synthesis
        if (!synthesisPermits.tryAcquire()) {
            synthesisCounter.decrement()
            return SynthesisResult(
                success = false,
                errorCode = ErrorCode.BUSY,
                errorMessage = "Too many concurrent synthesis requests"
            )
        }
        
        // Get or create speaker
        val speaker = loadedSpeakers.getOrPut(voiceId) {
            SupertonicSpeaker(
                voiceId = voiceId,
                speakerId = speakerId,
                lastUsed = System.currentTimeMillis()
            )
        }
        
        var audioSamples: FloatArray? = null
        var synthError: Exception? = null
        
        val job = scope.launch {
            try {
                // Run native ONNX inference
                audioSamples = SupertonicNative.synthesize(text, speaker.speakerId, speed)
                
                if (audioSamples == null) {
                    synthError = IllegalStateException("Native synthesis returned null")
                    return@launch
                }
                
                ensureActive()
                
                // Convert float samples to 16-bit PCM and write WAV
                val sampleRate = SupertonicNative.getSampleRate()
                val pcmData = floatToPcm16(audioSamples!!)
                
                val tmpFile = File("$outputPath.tmp")
                val parentDir = tmpFile.parentFile
                if (parentDir != null && !parentDir.exists() && !parentDir.mkdirs()) {
                    throw IOException("Failed to create output directory: $parentDir")
                }
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
            } catch (e: Exception) {
                synthError = e
                android.util.Log.e("SupertonicTtsService", "Synthesis error", e)
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
            } else if (synthError != null) {
                SynthesisResult(
                    success = false,
                    errorCode = mapExceptionToErrorCode(synthError!!),
                    errorMessage = synthError!!.message
                )
            } else if (audioSamples != null) {
                speaker.lastUsed = System.currentTimeMillis()
                val sampleRate = SupertonicNative.getSampleRate()
                val durationMs = (audioSamples!!.size * 1000 / sampleRate)
                
                SynthesisResult(
                    success = true,
                    durationMs = durationMs,
                    sampleRate = sampleRate
                )
            } else {
                SynthesisResult(
                    success = false,
                    errorCode = ErrorCode.INFERENCE_FAILED,
                    errorMessage = "No audio output generated"
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
            android.util.Log.w("SupertonicTtsService", "Timeout waiting for synthesis to complete before unload")
        }
        loadedSpeakers.remove(voiceId)
    }
    
    /**
     * Unload all models and reset state.
     * Waits for any active synthesis to complete first.
     */
    fun unloadAllModels() {
        // Wait for any active synthesis to complete (max 5 seconds)
        if (!synthesisCounter.waitUntilIdle(timeoutMs = 5000)) {
            android.util.Log.w("SupertonicTtsService", "Timeout waiting for synthesis to complete before unloadAll")
        }
        
        loadedSpeakers.clear()
        
        if (isInitialized) {
            SupertonicNative.dispose()
        }
        
        isInitialized = false
        modelPath = null
        
        activeJobs.values.forEach { it.cancel() }
        activeJobs.clear()
    }
    
    /**
     * Unload least recently used speaker.
     */
    fun unloadLeastUsedVoice(): String? {
        val lru = loadedSpeakers.minByOrNull { it.value.lastUsed }
        return lru?.let {
            loadedSpeakers.remove(it.key)
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
            loadedModelCount = loadedSpeakers.size
        )
    }
    
    fun isReady(): Boolean = isInitialized && SupertonicNative.isReady()
    fun isVoiceLoaded(voiceId: String): Boolean = loadedSpeakers.containsKey(voiceId)
    
    // Private helpers
    
    /**
     * Convert float audio samples [-1.0, 1.0] to 16-bit PCM.
     */
    private fun floatToPcm16(samples: FloatArray): ShortArray {
        return ShortArray(samples.size) { i ->
            val sample = samples[i].coerceIn(-1.0f, 1.0f)
            (sample * 32767).toInt().toShort()
        }
    }
    
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
 * Supertonic speaker state.
 */
data class SupertonicSpeaker(
    val voiceId: String,
    val speakerId: Int,
    val embeddingPath: String? = null,
    var lastUsed: Long
)
