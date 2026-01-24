package com.example.platform_android_tts.services

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.assertFalse
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.concurrent.thread

/**
 * Unit tests for SynthesisCounter.
 * Tests thread-safety and timeout behavior.
 */
internal class SynthesisCounterTest {

    @Test
    fun `increment increases count by one`() {
        val counter = SynthesisCounter()
        
        assertEquals(0, counter.activeCount())
        
        val result = counter.increment()
        
        assertEquals(1, result)
        assertEquals(1, counter.activeCount())
    }

    @Test
    fun `decrement decreases count by one`() {
        val counter = SynthesisCounter()
        counter.increment()
        counter.increment()
        
        val result = counter.decrement()
        
        assertEquals(1, result)
        assertEquals(1, counter.activeCount())
    }

    @Test
    fun `isIdle returns true when count is zero`() {
        val counter = SynthesisCounter()
        
        assertTrue(counter.isIdle())
    }

    @Test
    fun `isIdle returns false when count is greater than zero`() {
        val counter = SynthesisCounter()
        counter.increment()
        
        assertFalse(counter.isIdle())
    }

    @Test
    fun `waitUntilIdle returns immediately when already idle`() {
        val counter = SynthesisCounter()
        
        val startTime = System.currentTimeMillis()
        val result = counter.waitUntilIdle(timeoutMs = 5000)
        val elapsed = System.currentTimeMillis() - startTime
        
        assertTrue(result)
        assertTrue(elapsed < 200) // Should return almost immediately
    }

    @Test
    fun `waitUntilIdle waits for counter to reach zero`() {
        val counter = SynthesisCounter()
        counter.increment()
        
        // Start a thread that decrements after 200ms
        thread {
            Thread.sleep(200)
            counter.decrement()
        }
        
        val startTime = System.currentTimeMillis()
        val result = counter.waitUntilIdle(timeoutMs = 5000)
        val elapsed = System.currentTimeMillis() - startTime
        
        assertTrue(result)
        assertTrue(elapsed >= 200)
        assertTrue(elapsed < 1000) // Should not take too long
    }

    @Test
    fun `waitUntilIdle returns false on timeout`() {
        val counter = SynthesisCounter()
        counter.increment()
        // Don't decrement - let it timeout
        
        val startTime = System.currentTimeMillis()
        val result = counter.waitUntilIdle(timeoutMs = 300)
        val elapsed = System.currentTimeMillis() - startTime
        
        assertFalse(result)
        assertTrue(elapsed >= 300)
        assertTrue(elapsed < 500) // Should timeout reasonably promptly
    }

    @Test
    fun `counter is thread-safe with concurrent increments`() {
        val counter = SynthesisCounter()
        val numThreads = 10
        val threads = mutableListOf<Thread>()
        
        // Start multiple threads that increment
        repeat(numThreads) {
            threads.add(thread {
                counter.increment()
            })
        }
        
        // Wait for all threads to complete
        threads.forEach { it.join() }
        
        assertEquals(numThreads, counter.activeCount())
    }

    @Test
    fun `counter is thread-safe with concurrent increments and decrements`() {
        val counter = SynthesisCounter()
        val iterations = 100
        val threads = mutableListOf<Thread>()
        
        // Start threads that increment then decrement
        repeat(iterations) {
            threads.add(thread {
                counter.increment()
                Thread.sleep(10)
                counter.decrement()
            })
        }
        
        // Wait for all threads to complete
        threads.forEach { it.join() }
        
        assertEquals(0, counter.activeCount())
        assertTrue(counter.isIdle())
    }

    @Test
    fun `waitUntilIdleSuspend works correctly`() = runBlocking {
        val counter = SynthesisCounter()
        counter.increment()
        
        // Launch a coroutine that decrements after 200ms
        launch {
            delay(200)
            counter.decrement()
        }
        
        val startTime = System.currentTimeMillis()
        val result = counter.waitUntilIdleSuspend(timeoutMs = 5000)
        val elapsed = System.currentTimeMillis() - startTime
        
        assertTrue(result)
        assertTrue(elapsed >= 200)
    }

    @Test
    fun `waitUntilIdleSuspend times out correctly`() = runBlocking {
        val counter = SynthesisCounter()
        counter.increment()
        // Don't decrement - let it timeout
        
        val startTime = System.currentTimeMillis()
        val result = counter.waitUntilIdleSuspend(timeoutMs = 300)
        val elapsed = System.currentTimeMillis() - startTime
        
        assertFalse(result)
        assertTrue(elapsed >= 300)
    }
}
