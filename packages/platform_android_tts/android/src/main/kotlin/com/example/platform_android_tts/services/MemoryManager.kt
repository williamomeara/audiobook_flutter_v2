package com.example.platform_android_tts.services

import android.app.ActivityManager
import android.content.Context

/**
 * Memory manager for TTS services.
 * 
 * Monitors memory pressure and provides recommendations for model management.
 * Helps prevent OOM errors by proactively checking memory before loading models.
 */
object MemoryManager {
    
    // Memory thresholds
    private const val LOW_MEMORY_THRESHOLD_MB = 100L
    private const val CRITICAL_MEMORY_THRESHOLD_MB = 50L
    private const val MAX_MODEL_MEMORY_MB = 500L
    
    /**
     * Actions recommended based on memory state.
     */
    enum class MemoryAction {
        /** Memory is fine, proceed normally */
        NONE,
        /** Memory is low, consider unloading LRU models */
        UNLOAD_LRU,
        /** Memory is critical, unload all non-essential models */
        UNLOAD_ALL
    }
    
    /**
     * Memory state information.
     */
    data class MemoryState(
        val availableMemoryMb: Long,
        val totalMemoryMb: Long,
        val usedMemoryMb: Long,
        val isLowMemory: Boolean,
        val recommendedAction: MemoryAction
    )
    
    /**
     * Check current memory pressure using the Runtime.
     * 
     * @return True if JVM heap usage is above threshold
     */
    fun checkHeapPressure(): Boolean {
        val runtime = Runtime.getRuntime()
        val usedMB = (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024)
        return usedMB > MAX_MODEL_MEMORY_MB
    }
    
    /**
     * Get detailed memory state information.
     * 
     * @param context Android context for ActivityManager access
     * @return MemoryState with current memory info and recommended action
     */
    fun getMemoryState(context: Context): MemoryState {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        
        val availableMb = memoryInfo.availMem / (1024 * 1024)
        val totalMb = memoryInfo.totalMem / (1024 * 1024)
        val usedMb = totalMb - availableMb
        
        val action = when {
            memoryInfo.lowMemory || availableMb < CRITICAL_MEMORY_THRESHOLD_MB -> MemoryAction.UNLOAD_ALL
            availableMb < LOW_MEMORY_THRESHOLD_MB -> MemoryAction.UNLOAD_LRU
            else -> MemoryAction.NONE
        }
        
        return MemoryState(
            availableMemoryMb = availableMb,
            totalMemoryMb = totalMb,
            usedMemoryMb = usedMb,
            isLowMemory = memoryInfo.lowMemory,
            recommendedAction = action
        )
    }
    
    /**
     * Get recommended action based on current memory state.
     * 
     * @param context Android context for ActivityManager access
     * @return Recommended MemoryAction
     */
    fun getRecommendedAction(context: Context): MemoryAction {
        return getMemoryState(context).recommendedAction
    }
    
    /**
     * Check if it's safe to load a new model.
     * 
     * @param context Android context
     * @param estimatedModelSizeMb Estimated memory required for the new model
     * @return True if safe to proceed with loading
     */
    fun isSafeToLoadModel(context: Context, estimatedModelSizeMb: Long = 200L): Boolean {
        val state = getMemoryState(context)
        
        // Don't load if we're already in low memory state
        if (state.isLowMemory) {
            android.util.Log.w("MemoryManager", "System is in low memory state, unsafe to load model")
            return false
        }
        
        // Check if we have enough headroom
        val safeThreshold = estimatedModelSizeMb + LOW_MEMORY_THRESHOLD_MB
        if (state.availableMemoryMb < safeThreshold) {
            android.util.Log.w("MemoryManager", 
                "Insufficient memory: ${state.availableMemoryMb}MB available, need ${safeThreshold}MB")
            return false
        }
        
        return true
    }
    
    /**
     * Log current memory state for debugging.
     * 
     * @param context Android context
     * @param tag Log tag
     */
    fun logMemoryState(context: Context, tag: String = "MemoryManager") {
        val state = getMemoryState(context)
        android.util.Log.d(tag, buildString {
            append("Memory State: ")
            append("${state.usedMemoryMb}MB / ${state.totalMemoryMb}MB used, ")
            append("${state.availableMemoryMb}MB available, ")
            append("lowMemory=${state.isLowMemory}, ")
            append("action=${state.recommendedAction}")
        })
    }
}
