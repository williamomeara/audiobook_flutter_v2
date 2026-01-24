package com.example.platform_android_tts

import com.example.platform_android_tts.generated.*
import com.example.platform_android_tts.services.*
import kotlinx.coroutines.*
import java.util.concurrent.ConcurrentHashMap

/**
 * Implementation of Pigeon-generated TtsNativeApi.
 * Routes requests to the appropriate engine service based on engine type.
 */
class TtsNativeApiImpl(
    private val kokoroService: KokoroTtsService,
    private val piperService: PiperTtsService,
    private val supertonicService: SupertonicTtsService,
    private val flutterApi: TtsFlutterApi
) : TtsNativeApi {
    
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    // Track which engine owns each request for efficient cancellation
    private val requestOwners = ConcurrentHashMap<String, NativeEngineType>()
    
    override fun initEngine(request: InitEngineRequest, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            val result = when (request.engineType) {
                NativeEngineType.KOKORO -> kokoroService.initEngine(request.corePath)
                NativeEngineType.PIPER -> piperService.initEngine(request.corePath)
                NativeEngineType.SUPERTONIC -> supertonicService.initEngine(request.corePath)
            }
            callback(result)
        }
    }
    
    override fun loadVoice(request: LoadVoiceRequest, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            val result = when (request.engineType) {
                NativeEngineType.KOKORO -> kokoroService.loadVoice(
                    request.voiceId,
                    request.speakerId?.toInt() ?: 0
                )
                NativeEngineType.PIPER -> piperService.loadVoice(
                    request.voiceId,
                    request.modelPath
                )
                NativeEngineType.SUPERTONIC -> supertonicService.loadVoice(
                    request.voiceId,
                    request.speakerId?.toInt() ?: 0,
                    request.configPath
                )
            }
            callback(result)
        }
    }
    
    override fun synthesize(
        request: SynthesizeRequest,
        callback: (Result<SynthesizeResult>) -> Unit
    ) {
        // Track request ownership for efficient cancellation
        requestOwners[request.requestId] = request.engineType
        
        scope.launch {
            try {
                val result = when (request.engineType) {
                    NativeEngineType.KOKORO -> kokoroService.synthesize(
                        voiceId = request.voiceId,
                        text = request.text,
                        outputPath = request.outputPath,
                        requestId = request.requestId,
                        speakerId = request.speakerId?.toInt() ?: 0,
                        speed = request.speed.toFloat()
                    )
                    NativeEngineType.PIPER -> piperService.synthesize(
                        voiceId = request.voiceId,
                        text = request.text,
                        outputPath = request.outputPath,
                        requestId = request.requestId,
                        speed = request.speed.toFloat()
                    )
                    NativeEngineType.SUPERTONIC -> supertonicService.synthesize(
                        voiceId = request.voiceId,
                        text = request.text,
                        outputPath = request.outputPath,
                        requestId = request.requestId,
                        speakerId = request.speakerId?.toInt() ?: 0,
                        speed = request.speed.toFloat()
                    )
                }
                
                callback(Result.success(SynthesizeResult(
                    success = result.success,
                    durationMs = result.durationMs?.toLong(),
                    sampleRate = result.sampleRate?.toLong(),
                    errorCode = result.errorCode?.toPigeonError(),
                    errorMessage = result.errorMessage
                )))
            } finally {
                // Clean up request ownership tracking
                requestOwners.remove(request.requestId)
            }
        }
    }
    
    override fun cancelSynthesis(requestId: String, callback: (Result<Unit>) -> Unit) {
        // Cancel only on the service that owns the request (more efficient)
        when (requestOwners.remove(requestId)) {
            NativeEngineType.KOKORO -> kokoroService.cancelSynthesis(requestId)
            NativeEngineType.PIPER -> piperService.cancelSynthesis(requestId)
            NativeEngineType.SUPERTONIC -> supertonicService.cancelSynthesis(requestId)
            null -> {
                // Request not found or already completed - no-op
                android.util.Log.d("TtsNativeApiImpl", "Cancel: requestId=$requestId not found (already completed?)")
            }
        }
        callback(Result.success(Unit))
    }
    
    override fun unloadVoice(
        engineType: NativeEngineType,
        voiceId: String,
        callback: (Result<Unit>) -> Unit
    ) {
        when (engineType) {
            NativeEngineType.KOKORO -> kokoroService.unloadVoice(voiceId)
            NativeEngineType.PIPER -> piperService.unloadVoice(voiceId)
            NativeEngineType.SUPERTONIC -> supertonicService.unloadVoice(voiceId)
        }
        // Notify Flutter that voice was unloaded
        notifyVoiceUnloaded(engineType, voiceId)
        callback(Result.success(Unit))
    }
    
    override fun unloadEngine(
        engineType: NativeEngineType,
        callback: (Result<Unit>) -> Unit
    ) {
        // Get loaded voices before unloading to notify Flutter
        val voicesToNotify = when (engineType) {
            NativeEngineType.KOKORO -> kokoroService.getLoadedVoiceIds()
            NativeEngineType.PIPER -> piperService.getLoadedVoiceIds()
            NativeEngineType.SUPERTONIC -> supertonicService.getLoadedVoiceIds()
        }
        
        when (engineType) {
            NativeEngineType.KOKORO -> kokoroService.unloadAllModels()
            NativeEngineType.PIPER -> piperService.unloadAllModels()
            NativeEngineType.SUPERTONIC -> supertonicService.unloadAllModels()
        }
        
        // Notify Flutter about all unloaded voices
        voicesToNotify.forEach { voiceId ->
            notifyVoiceUnloaded(engineType, voiceId)
        }
        
        // Notify engine state changed
        notifyEngineStateChanged(engineType, NativeCoreState.NOT_STARTED, null)
        
        callback(Result.success(Unit))
    }
    
    override fun getMemoryInfo(callback: (Result<MemoryInfo>) -> Unit) {
        // Aggregate from all services
        val kokoroMem = kokoroService.getMemoryInfo()
        val piperMem = piperService.getMemoryInfo()
        val supertonicMem = supertonicService.getMemoryInfo()
        
        val totalLoaded = kokoroMem.loadedModelCount + 
            piperMem.loadedModelCount + 
            supertonicMem.loadedModelCount
        
        callback(Result.success(MemoryInfo(
            availableMB = kokoroMem.availableMB.toLong(),
            totalMB = kokoroMem.totalMB.toLong(),
            loadedModelCount = totalLoaded.toLong()
        )))
    }
    
    override fun getCoreStatus(
        engineType: NativeEngineType,
        callback: (Result<CoreStatus>) -> Unit
    ) {
        val (isReady, state) = when (engineType) {
            NativeEngineType.KOKORO -> kokoroService.isReady() to NativeCoreState.READY
            NativeEngineType.PIPER -> piperService.isReady() to NativeCoreState.READY
            NativeEngineType.SUPERTONIC -> supertonicService.isReady() to NativeCoreState.READY
        }
        
        callback(Result.success(CoreStatus(
            engineType = engineType,
            state = if (isReady) NativeCoreState.READY else NativeCoreState.NOT_STARTED,
            errorMessage = null,
            downloadProgress = null
        )))
    }
    
    override fun isVoiceReady(
        engineType: NativeEngineType,
        voiceId: String,
        callback: (Result<Boolean>) -> Unit
    ) {
        val ready = when (engineType) {
            NativeEngineType.KOKORO -> kokoroService.isVoiceLoaded(voiceId)
            NativeEngineType.PIPER -> piperService.isVoiceLoaded(voiceId)
            NativeEngineType.SUPERTONIC -> supertonicService.isVoiceLoaded(voiceId)
        }
        callback(Result.success(ready))
    }
    
    override fun dispose(callback: (Result<Unit>) -> Unit) {
        kokoroService.unloadAllModels()
        piperService.unloadAllModels()
        supertonicService.unloadAllModels()
        scope.cancel()
        callback(Result.success(Unit))
    }
    
    fun cleanup() {
        scope.cancel()
    }
    
    // Helper methods for Flutter callbacks
    
    private fun notifyVoiceUnloaded(engineType: NativeEngineType, voiceId: String) {
        scope.launch(Dispatchers.Main) {
            flutterApi.onVoiceUnloaded(engineType, voiceId) { /* ignore callback result */ }
        }
    }
    
    private fun notifyEngineStateChanged(engineType: NativeEngineType, state: NativeCoreState, errorMessage: String?) {
        scope.launch(Dispatchers.Main) {
            flutterApi.onEngineStateChanged(engineType, state, errorMessage) { /* ignore callback result */ }
        }
    }
    
    private fun notifyMemoryWarning(engineType: NativeEngineType, availableMB: Int, totalMB: Int) {
        scope.launch(Dispatchers.Main) {
            flutterApi.onMemoryWarning(engineType, availableMB.toLong(), totalMB.toLong()) { /* ignore callback result */ }
        }
    }
    
    /**
     * Called by services when they internally unload a voice (e.g., due to LRU eviction).
     */
    fun onVoiceUnloadedByService(engineType: NativeEngineType, voiceId: String) {
        notifyVoiceUnloaded(engineType, voiceId)
    }
    
    /**
     * Called by memory manager to warn Flutter of low memory.
     */
    fun onMemoryWarningFromService(engineType: NativeEngineType, availableMB: Int, totalMB: Int) {
        notifyMemoryWarning(engineType, availableMB, totalMB)
    }
}

// Extension to convert service ErrorCode to Pigeon NativeErrorCode
private fun ErrorCode.toPigeonError(): NativeErrorCode {
    return when (this) {
        ErrorCode.NONE -> NativeErrorCode.NONE
        ErrorCode.MODEL_MISSING -> NativeErrorCode.MODEL_MISSING
        ErrorCode.MODEL_CORRUPTED -> NativeErrorCode.MODEL_CORRUPTED
        ErrorCode.OUT_OF_MEMORY -> NativeErrorCode.OUT_OF_MEMORY
        ErrorCode.INFERENCE_FAILED -> NativeErrorCode.INFERENCE_FAILED
        ErrorCode.CANCELLED -> NativeErrorCode.CANCELLED
        ErrorCode.RUNTIME_CRASH -> NativeErrorCode.RUNTIME_CRASH
        ErrorCode.INVALID_INPUT -> NativeErrorCode.INVALID_INPUT
        ErrorCode.FILE_WRITE_ERROR -> NativeErrorCode.FILE_WRITE_ERROR
        ErrorCode.BUSY -> NativeErrorCode.BUSY
        ErrorCode.UNKNOWN -> NativeErrorCode.UNKNOWN
    }
}
