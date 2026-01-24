package com.example.platform_android_tts.services

import java.util.concurrent.atomic.AtomicInteger

/**
 * Thread-safe counter for tracking active synthesis operations.
 * 
 * Used to prevent model unloading while synthesis is in progress.
 * Follows the pattern used in iOS (SynthesisCounter.swift).
 * 
 * Usage:
 * ```kotlin
 * private val synthesisCounter = SynthesisCounter()
 * 
 * suspend fun synthesize(...) {
 *     synthesisCounter.increment()
 *     try {
 *         // ... synthesis logic
 *     } finally {
 *         synthesisCounter.decrement()
 *     }
 * }
 * 
 * fun unloadVoice(...) {
 *     if (!synthesisCounter.waitUntilIdle(timeoutMs = 5000)) {
 *         // Timeout - synthesis still in progress
 *         return
 *     }
 *     // ... unload logic
 * }
 * ```
 */
class SynthesisCounter {
    private val count = AtomicInteger(0)
    
    /**
     * Increment the counter when starting a synthesis operation.
     * @return The new count value
     */
    fun increment(): Int = count.incrementAndGet()
    
    /**
     * Decrement the counter when a synthesis operation completes.
     * @return The new count value
     */
    fun decrement(): Int = count.decrementAndGet()
    
    /**
     * Check if there are no active synthesis operations.
     * @return true if count is 0
     */
    fun isIdle(): Boolean = count.get() == 0
    
    /**
     * Get the current count of active synthesis operations.
     * @return The current count
     */
    fun activeCount(): Int = count.get()
    
    /**
     * Wait until all synthesis operations complete or timeout.
     * 
     * @param timeoutMs Maximum time to wait in milliseconds
     * @param checkIntervalMs Interval between idle checks (default: 100ms)
     * @return true if idle within timeout, false if timed out
     */
    fun waitUntilIdle(timeoutMs: Long, checkIntervalMs: Long = 100): Boolean {
        val startTime = System.currentTimeMillis()
        while (!isIdle()) {
            if (System.currentTimeMillis() - startTime > timeoutMs) {
                return false
            }
            Thread.sleep(checkIntervalMs)
        }
        return true
    }
    
    /**
     * Wait until all synthesis operations complete or timeout (suspend version).
     * 
     * @param timeoutMs Maximum time to wait in milliseconds
     * @param checkIntervalMs Interval between idle checks (default: 100ms)
     * @return true if idle within timeout, false if timed out
     */
    suspend fun waitUntilIdleSuspend(timeoutMs: Long, checkIntervalMs: Long = 100): Boolean {
        val startTime = System.currentTimeMillis()
        while (!isIdle()) {
            if (System.currentTimeMillis() - startTime > timeoutMs) {
                return false
            }
            kotlinx.coroutines.delay(checkIntervalMs)
        }
        return true
    }
}
