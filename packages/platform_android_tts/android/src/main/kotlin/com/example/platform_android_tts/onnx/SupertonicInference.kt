package com.example.platform_android_tts.onnx

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.Normalizer

/**
 * Supertonic TTS inference.
 * 
 * Supertonic uses a 4-stage pipeline:
 * 1. Text Encoder: Raw text → latent representation
 * 2. Duration Predictor: Latent → durations for each unit
 * 3. Vector Estimator: Diffusion-based denoising (may be part of autoencoder)
 * 4. Vocoder/Autoencoder: Latent + durations → audio waveform
 * 
 * Key difference from VITS-based TTS: No phonemization needed!
 * Supertonic works directly with raw Unicode text (NFKD normalized).
 * 
 * This implementation uses JNI to call the ONNX Runtime bundled with sherpa-onnx,
 * avoiding native library conflicts.
 */
class SupertonicInference(private val corePath: String) {
    private var isInitialized = false
    
    /**
     * Initialize all ONNX models.
     * 
     * Expected files in corePath:
     * - onnx/text_encoder.onnx
     * - onnx/duration_predictor.onnx
     * - onnx/vector_estimator.onnx (or autoencoder.onnx)
     * - onnx/vocoder.onnx
     */
    suspend fun initialize(): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            // Check if native library is available
            if (!SupertonicNative.isNativeAvailable()) {
                throw IllegalStateException("Supertonic native library not available")
            }
            
            // Initialize native engine
            val success = SupertonicNative.initialize(corePath)
            if (!success) {
                throw IllegalStateException("Failed to initialize Supertonic native engine")
            }
            
            isInitialized = true
            android.util.Log.i("SupertonicInference", "Supertonic initialized from $corePath")
            Unit
        }
    }
    
    /**
     * Synthesize text to audio samples.
     * 
     * @param text The text to synthesize
     * @param speakerId The speaker ID for multi-speaker support
     * @param speed Speech rate multiplier (1.0 = normal speed)
     * @return FloatArray of audio samples at 24000 Hz
     */
    suspend fun synthesize(
        text: String,
        speakerId: Int = 0,
        speed: Float = 1.0f
    ): Result<FloatArray> = withContext(Dispatchers.Default) {
        runCatching {
            if (!isInitialized) {
                throw IllegalStateException("Engine not initialized")
            }
            
            // Normalize text (NFKD Unicode normalization)
            val normalizedText = Normalizer.normalize(text, Normalizer.Form.NFKD)
            
            // Call native synthesis
            val samples = SupertonicNative.synthesize(normalizedText, speakerId, speed)
                ?: throw IllegalStateException("Native synthesis returned null")
            
            android.util.Log.d("SupertonicInference", "Synthesized ${samples.size} samples")
            samples
        }
    }
    
    /**
     * Get the sample rate.
     */
    fun getSampleRate(): Int {
        return if (isInitialized) {
            SupertonicNative.getSampleRate()
        } else {
            24000 // Default
        }
    }
    
    /**
     * Check if all models are loaded.
     */
    fun isReady(): Boolean {
        return isInitialized && SupertonicNative.isReady()
    }
    
    /**
     * Release all resources.
     */
    fun dispose() {
        if (isInitialized) {
            SupertonicNative.dispose()
            isInitialized = false
        }
    }
}
