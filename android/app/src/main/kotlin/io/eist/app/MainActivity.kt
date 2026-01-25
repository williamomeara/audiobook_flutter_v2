package io.eist.app

import android.content.ComponentCallbacks2
import android.os.StatFs
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Using FlutterFragmentActivity for audio_service compatibility.
// This is required for system media controls (lock screen, notification).
class MainActivity : FlutterFragmentActivity() {
    
    companion object {
        private const val SYSTEM_CHANNEL = "io.eist.app/system"
    }
    
    private var systemChannel: MethodChannel? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        systemChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_CHANNEL
        )
        
        systemChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageInfo" -> {
                    val storageInfo = getStorageInfo()
                    result.success(storageInfo)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    /**
     * Handle memory pressure events from the system.
     * 
     * Forwards memory pressure level to Flutter via platform channel.
     * This enables proactive memory management before OOM.
     */
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        
        val pressureLevel = when (level) {
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL,
            ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> "critical"
            
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW,
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE -> "moderate"
            
            else -> null
        }
        
        pressureLevel?.let {
            systemChannel?.invokeMethod("memoryPressure", it)
        }
    }
    
    /**
     * Get storage information for cache auto-configuration.
     * 
     * Returns available and total bytes for internal storage.
     */
    private fun getStorageInfo(): Map<String, Long> {
        return try {
            val stat = StatFs(filesDir.path)
            mapOf(
                "availableBytes" to stat.availableBytes,
                "totalBytes" to stat.totalBytes,
                "blockSize" to stat.blockSizeLong
            )
        } catch (e: Exception) {
            mapOf(
                "availableBytes" to 0L,
                "totalBytes" to 0L,
                "blockSize" to 0L
            )
        }
    }
}
