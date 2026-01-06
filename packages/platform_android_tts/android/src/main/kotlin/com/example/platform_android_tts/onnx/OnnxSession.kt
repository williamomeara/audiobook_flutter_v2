package com.example.platform_android_tts.onnx

/**
 * STUB: Wrapper around ONNX Runtime OrtSession with lifecycle management.
 * 
 * NOTE: Currently a stub because sherpa-onnx bundles its own libonnxruntime.so
 * and we cannot add a separate onnxruntime-android dependency without conflicts.
 * 
 * For Supertonic support (which requires raw ONNX Runtime), options are:
 * 1. Use JNI directly to call the bundled libonnxruntime.so from sherpa-onnx
 * 2. Build Supertonic as a native library that links against sherpa-onnx's ONNX Runtime
 * 3. Wait for sherpa-onnx to add Supertonic model support
 * 
 * For now, Piper and Kokoro work via sherpa-onnx, and Supertonic is a stub.
 */
class OnnxSession(modelPath: String) {
    init {
        // Stub - no actual model loading
        android.util.Log.w("OnnxSession", "STUB: OnnxSession created for $modelPath - not functional")
    }
    
    /**
     * Get input names for this model.
     */
    fun getInputNames(): Set<String> = emptySet()
    
    /**
     * Get output names for this model.
     */
    fun getOutputNames(): Set<String> = emptySet()
    
    /**
     * Close the session and release resources.
     */
    fun close() {
        // Stub - nothing to close
    }
}
