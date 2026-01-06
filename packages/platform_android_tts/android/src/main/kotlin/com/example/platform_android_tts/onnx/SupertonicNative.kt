package com.example.platform_android_tts.onnx

/**
 * JNI wrapper for Supertonic TTS native implementation.
 * 
 * This class provides access to the Supertonic TTS pipeline which runs
 * 4 ONNX models in sequence:
 * 1. text_encoder - converts text tokens to hidden states
 * 2. duration_predictor - predicts phoneme durations
 * 3. vector_estimator - generates latent audio representations
 * 4. vocoder - converts latent vectors to audio waveform
 * 
 * The native implementation uses the ONNX Runtime bundled with sherpa-onnx,
 * loaded dynamically to avoid library conflicts.
 */
object SupertonicNative {
    
    private var nativeLibLoaded = false
    
    init {
        try {
            System.loadLibrary("supertonic_native")
            nativeLibLoaded = true
            android.util.Log.i("SupertonicNative", "Native library loaded successfully")
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.e("SupertonicNative", "Failed to load native library", e)
            nativeLibLoaded = false
        }
    }
    
    /**
     * Check if the native library is available.
     */
    fun isNativeAvailable(): Boolean = nativeLibLoaded
    
    /**
     * Initialize the Supertonic engine with models from the given path.
     * 
     * Expected files in corePath:
     * - onnx/text_encoder.onnx
     * - onnx/duration_predictor.onnx
     * - onnx/vector_estimator.onnx
     * - onnx/vocoder.onnx
     * - onnx/unicode_indexer.json
     * - onnx/tts.json
     * 
     * @param corePath Path to the Supertonic core directory
     * @return true if initialization succeeded
     */
    external fun initialize(corePath: String): Boolean
    
    /**
     * Synthesize text to audio samples.
     * 
     * @param text The text to synthesize (Unicode, will be NFKD normalized)
     * @param speakerId Speaker ID for multi-speaker support
     * @param speed Speech rate multiplier (1.0 = normal)
     * @return FloatArray of audio samples at 24kHz, or null on error
     */
    external fun synthesize(text: String, speakerId: Int, speed: Float): FloatArray?
    
    /**
     * Get the sample rate of generated audio.
     * @return Sample rate in Hz (24000)
     */
    external fun getSampleRate(): Int
    
    /**
     * Check if the engine is ready for synthesis.
     * @return true if models are loaded and ready
     */
    external fun isReady(): Boolean
    
    /**
     * Release all resources.
     */
    external fun dispose()
}
