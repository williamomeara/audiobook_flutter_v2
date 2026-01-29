# ONNX Runtime Inference Implementation Plan (Phase 6)

## Overview

This document outlines the implementation plan for integrating TTS inference into the native Android services. Currently, the services (`KokoroTtsService.kt`, `PiperTtsService.kt`, `SupertonicTtsService.kt`) have placeholder code that generates silent audio files. This phase will implement actual TTS inference.

## Current State Analysis

### What's Already Done
- ✅ **Pigeon API**: Complete type-safe interface between Flutter and Kotlin (`TtsApi.g.kt`)
- ✅ **Service Architecture**: Three separate service classes with proper async/coroutine handling
- ✅ **TtsNativeApiImpl**: Routes requests to appropriate engine based on `NativeEngineType`
- ✅ **Download Infrastructure**: Models can be downloaded and extracted to app cache
- ✅ **Voice Manifest**: JSON manifest with all voice metadata (speaker IDs, file paths, etc.)
- ✅ **WAV File Writing**: Helper functions for writing 16-bit PCM WAV files
- ✅ **Error Handling**: Comprehensive `ErrorCode` enum and result types

### What Needs Implementation
- ❌ sherpa-onnx dependency integration (for Kokoro + Piper)
- ❌ ONNX Runtime dependency integration (for Supertonic)
- ❌ Model loading in `initEngine()` methods
- ❌ Actual inference in `synthesize()` methods
- ❌ Voice/speaker embedding handling

---

## Architecture Decision: Hybrid Approach

After research, we'll use a **hybrid approach**:

### sherpa-onnx for Kokoro + Piper
**Rationale:**
- Purpose-built for TTS inference on mobile
- Handles phonemization automatically (includes espeak-ng)
- Specifically designed for VITS-based models (Piper) and Kokoro
- High-level API minimizes implementation complexity
- Available as Maven dependency: `com.bihe0832.android:lib-sherpa-onnx:8.0.2`

### ONNX Runtime for Supertonic
**Rationale:**
- Supertonic is NOT supported by sherpa-onnx (different architecture)
- Supertonic has its own 4-stage pipeline (text encoder → duration predictor → vector estimator → vocoder)
- Uses raw character-level text input (no phonemization needed - handles text normalization internally)
- Simple ONNX Runtime integration works well
- Available as Maven dependency: `com.microsoft.onnxruntime:onnxruntime-android:1.17.0`

---

## Supertonic Architecture Deep Dive

Supertonic uses a **4-model pipeline** (different from VITS-based TTS):

### Pipeline Stages
1. **Text Encoder** (`text_encoder.onnx` ~105MB)
   - Input: Raw Unicode text (no phonemes needed!)
   - Uses NFKD Unicode normalization
   - Converts directly to latent representation using ConvNeXt blocks
   - Handles numbers, dates, currency, abbreviations automatically

2. **Duration Predictor** (`duration_predictor.onnx` ~73MB)
   - Input: Text encoder output
   - Output: Duration for each speech unit
   - Controls pacing and prosody
   - Speed parameter scales predicted durations

3. **Vector Estimator** (part of autoencoder or separate)
   - Diffusion-based denoising loop
   - Refines latent audio representations

4. **Vocoder/Autoencoder** (`autoencoder.onnx` ~94MB)
   - Input: Denoised latent vectors + durations
   - Output: Audio waveform (24000 Hz)

### Key Difference from Kokoro/Piper
- **No phonemization**: Works with raw character-level text
- **4 ONNX models** vs 1 for VITS-based TTS
- **~66M parameters** total, split across models
- **Multi-speaker** via speaker embeddings

---

## Implementation Tasks

### Phase 6.1: Dependencies and Project Setup

#### 6.1.1 Add dependencies to build.gradle.kts
**File:** `packages/platform_android_tts/android/build.gradle.kts`

```kotlin
dependencies {
    // Existing
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    
    // sherpa-onnx for Kokoro + Piper (VITS-based TTS)
    implementation("com.bihe0832.android:lib-sherpa-onnx:8.0.2")
    
    // ONNX Runtime for Supertonic (custom pipeline)
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.17.0")
}
```

#### 6.1.2 Create package structure
```
packages/platform_android_tts/android/src/main/kotlin/com/example/platform_android_tts/
├── sherpa/
│   └── SherpaOnnxWrapper.kt    # Wrapper for sherpa-onnx TTS
├── onnx/
│   ├── OnnxSession.kt          # ONNX Runtime wrapper
│   └── SupertonicInference.kt  # Supertonic 4-stage pipeline
```

---

### Phase 6.2: Piper TTS Implementation (sherpa-onnx)

#### 6.2.1 sherpa-onnx Piper Integration
Piper models are directly supported by sherpa-onnx VITS engine.

```kotlin
package com.example.platform_android_tts.sherpa

import com.k2fsa.sherpa.onnx.*

class PiperSherpaInference(
    private val modelPath: String,
    private val configPath: String
) {
    private var tts: OfflineTts? = null
    
    fun initialize(): Result<Unit> = runCatching {
        val config = OfflineTtsConfig(
            model = OfflineTtsModelConfig(
                vits = OfflineTtsVitsModelConfig(
                    model = "$modelPath/model.onnx",
                    tokens = "$modelPath/tokens.txt",  // From config.json
                    dataDir = ""  // espeak-ng data if needed
                ),
                numThreads = 2,
                debug = false
            )
        )
        tts = OfflineTts(config)
    }
    
    fun synthesize(text: String, speed: Float = 1.0f): FloatArray {
        val audio = tts!!.generate(text, speed = speed)
        return audio.samples
    }
    
    fun getSampleRate(): Int = tts!!.sampleRate()
    
    fun dispose() {
        tts?.release()
        tts = null
    }
}
```

#### 6.2.2 Update PiperTtsService.kt
Replace placeholder with sherpa-onnx calls.

---

### Phase 6.3: Kokoro TTS Implementation (sherpa-onnx)

#### 6.3.1 sherpa-onnx Kokoro Integration
Kokoro is also supported by sherpa-onnx with multi-speaker support.

```kotlin
class KokoroSherpaInference(
    private val modelPath: String,
    private val voicesPath: String
) {
    private var tts: OfflineTts? = null
    
    fun initialize(): Result<Unit> = runCatching {
        val config = OfflineTtsConfig(
            model = OfflineTtsModelConfig(
                kokoro = OfflineTtsKokoroModelConfig(
                    model = "$modelPath/model.onnx",
                    voices = voicesPath,
                    tokens = "$modelPath/tokens.txt",
                    dataDir = "$modelPath/espeak-ng-data"
                ),
                numThreads = 2,
                debug = false
            )
        )
        tts = OfflineTts(config)
    }
    
    fun synthesize(
        text: String,
        speakerId: Int = 0,
        speed: Float = 1.0f
    ): FloatArray {
        val audio = tts!!.generate(text, sid = speakerId, speed = speed)
        return audio.samples
    }
    
    fun getSampleRate(): Int = tts!!.sampleRate()
    
    fun dispose() {
        tts?.release()
        tts = null
    }
}
```

#### 6.3.2 Update KokoroTtsService.kt
Replace placeholder with sherpa-onnx calls, mapping speakerId from manifest.

---

### Phase 6.4: Supertonic TTS Implementation (ONNX Runtime)

#### 6.4.1 ONNX Runtime Wrapper
```kotlin
package com.example.platform_android_tts.onnx

import ai.onnxruntime.*
import java.nio.FloatBuffer
import java.nio.LongBuffer

class OnnxSession(modelPath: String) {
    private val env = OrtEnvironment.getEnvironment()
    private val session = env.createSession(modelPath)
    
    fun run(inputs: Map<String, OnnxTensor>): Map<String, OnnxTensor> {
        return session.run(inputs).associate { 
            it.key to it.value as OnnxTensor 
        }
    }
    
    fun close() {
        session.close()
    }
}
```

#### 6.4.2 Supertonic 4-Stage Pipeline
```kotlin
package com.example.platform_android_tts.onnx

class SupertonicInference(private val corePath: String) {
    private lateinit var textEncoder: OnnxSession
    private lateinit var durationPredictor: OnnxSession
    private lateinit var vectorEstimator: OnnxSession  // May be part of autoencoder
    private lateinit var autoencoder: OnnxSession
    
    private val vocabulary: Map<Char, Int> = loadVocabulary()
    
    fun initialize(): Result<Unit> = runCatching {
        textEncoder = OnnxSession("$corePath/text_encoder.onnx")
        durationPredictor = OnnxSession("$corePath/duration_predictor.onnx")
        autoencoder = OnnxSession("$corePath/autoencoder.onnx")
    }
    
    fun synthesize(
        text: String,
        speakerId: Int = 0,
        speed: Float = 1.0f
    ): Result<FloatArray> = runCatching {
        // 1. Normalize text (NFKD Unicode)
        val normalizedText = java.text.Normalizer.normalize(
            text, 
            java.text.Normalizer.Form.NFKD
        )
        
        // 2. Tokenize to character IDs
        val tokens = tokenize(normalizedText)
        
        // 3. Run text encoder
        val textEncOutput = textEncoder.run(mapOf(
            "text_ids" to createLongTensor(tokens),
            "speaker_id" to createLongTensor(longArrayOf(speakerId.toLong()))
        ))
        
        // 4. Run duration predictor
        val durations = durationPredictor.run(mapOf(
            "hidden_states" to textEncOutput["hidden_states"]!!
        ))
        
        // 5. Apply speed scaling
        val scaledDurations = scaleDurations(durations, speed)
        
        // 6. Run autoencoder/vocoder
        val audio = autoencoder.run(mapOf(
            "hidden_states" to textEncOutput["hidden_states"]!!,
            "durations" to scaledDurations
        ))
        
        // 7. Extract audio samples
        return@runCatching extractAudioSamples(audio["audio"]!!)
    }
    
    private fun tokenize(text: String): LongArray {
        return text.map { vocabulary[it] ?: 0 }.map { it.toLong() }.toLongArray()
    }
    
    private fun loadVocabulary(): Map<Char, Int> {
        // Load from vocab.txt or define inline
        // Supertonic uses character-level input
        return ('a'..'z').mapIndexed { i, c -> c to i + 1 }.toMap() +
               ('A'..'Z').mapIndexed { i, c -> c to i + 27 }.toMap() +
               mapOf(' ' to 0, '.' to 53, ',' to 54, '!' to 55, '?' to 56)
    }
    
    fun getSampleRate(): Int = 24000
    
    fun dispose() {
        textEncoder.close()
        durationPredictor.close()
        autoencoder.close()
    }
}
```

#### 6.4.3 Update SupertonicTtsService.kt
Replace placeholder with ONNX Runtime inference calls.

---

### Phase 6.5: Service Integration

#### 6.5.1 Update KokoroTtsService.kt

```kotlin
// Add to class
private var sherpaInference: KokoroSherpaInference? = null

// Update initEngine()
suspend fun initEngine(corePath: String): Result<Unit> = runCatching {
    if (isInitialized && modelPath == corePath) return Result.success(Unit)
    
    sherpaInference = KokoroSherpaInference(
        modelPath = corePath,
        voicesPath = "$corePath/voices.bin"
    )
    sherpaInference!!.initialize().getOrThrow()
    
    modelPath = corePath
    isInitialized = true
}

// Update synthesize() - replace silent audio generation with:
val samples = sherpaInference!!.synthesize(text, speakerId, speed)
val pcmData = samples.map { (it * 32767).toInt().coerceIn(-32768, 32767).toShort() }.toShortArray()
writeWavFile(tmpFile, pcmData, sherpaInference!!.getSampleRate())
```

#### 6.5.2 Update PiperTtsService.kt

```kotlin
// Add to class  
private var sherpaInference: PiperSherpaInference? = null

// Similar pattern to Kokoro
```

#### 6.5.3 Update SupertonicTtsService.kt

```kotlin
// Add to class
private var onnxInference: SupertonicInference? = null

// Update initEngine()
suspend fun initEngine(corePath: String): Result<Unit> = runCatching {
    if (isInitialized && modelPath == corePath) return Result.success(Unit)
    
    onnxInference = SupertonicInference(corePath)
    onnxInference!!.initialize().getOrThrow()
    
    modelPath = corePath
    isInitialized = true
}

// Update synthesize()
val samples = onnxInference!!.synthesize(text, speakerId, speed).getOrThrow()
val pcmData = samples.map { (it * 32767).toInt().coerceIn(-32768, 32767).toShort() }.toShortArray()
writeWavFile(tmpFile, pcmData, onnxInference!!.getSampleRate())
```

---

### Phase 6.6: Testing Strategy

#### 6.6.1 Unit Tests
- `SherpaOnnxWrapperTest.kt` - Test sherpa-onnx initialization
- `OnnxSessionTest.kt` - Test ONNX Runtime loading
- `SupertonicInferenceTest.kt` - Test tokenization and pipeline

#### 6.6.2 Integration Tests
- Download models, init engines, synthesize short text
- Verify WAV files are valid and non-silent
- Test cancellation during synthesis

#### 6.6.3 Device Testing
- Test on physical device (emulator may not support NNAPI)
- Monitor memory usage with large models
- Test model hot-swapping (unload/reload)
- Compare audio quality between engines

---

## File Changes Summary

### New Files to Create
```
packages/platform_android_tts/android/src/main/kotlin/com/example/platform_android_tts/
├── sherpa/
│   ├── KokoroSherpaInference.kt   # Kokoro via sherpa-onnx
│   └── PiperSherpaInference.kt    # Piper via sherpa-onnx
├── onnx/
│   ├── OnnxSession.kt             # ONNX Runtime wrapper
│   └── SupertonicInference.kt     # Supertonic 4-stage pipeline
```

### Files to Modify
```
packages/platform_android_tts/android/build.gradle.kts  # Add both dependencies
packages/platform_android_tts/android/src/main/kotlin/.../services/
├── KokoroTtsService.kt         # Integrate KokoroSherpaInference
├── PiperTtsService.kt          # Integrate PiperSherpaInference
└── SupertonicTtsService.kt     # Integrate SupertonicInference
```

---

## Risk Assessment

### High Risk
1. **sherpa-onnx Model Compatibility**: Downloaded models must match sherpa-onnx expected format
   - Mitigation: Verify model file structure matches sherpa-onnx requirements
   - May need to adjust download manifest or model paths

2. **Supertonic Pipeline Accuracy**: 4-stage pipeline must be implemented correctly
   - Mitigation: Reference official Supertonic Java example code
   - Test with simple inputs first

### Medium Risk
3. **Memory Pressure**: Multiple ONNX sessions may cause OOM
   - Mitigation: Implement LRU model unloading, test on 2GB RAM devices

4. **sherpa-onnx AAR Size**: Library may significantly increase APK size
   - Mitigation: Use ABI splits, consider dynamic feature modules

### Low Risk
5. **Performance**: INT8 models should be fast enough on modern devices
   - Mitigation: Add inference timing logging

---

## Implementation Order (Recommended)

1. **Week 1**: Phase 6.1 (Dependencies) + Phase 6.2 (Piper - simplest sherpa-onnx integration)
2. **Week 2**: Phase 6.3 (Kokoro - multi-speaker sherpa-onnx)
3. **Week 3**: Phase 6.4 (Supertonic - ONNX Runtime pipeline)
4. **Week 4**: Phase 6.5 (Service Integration) + Phase 6.6 (Testing)

---

## Success Criteria

- [ ] `flutter build apk` succeeds with both dependencies
- [ ] Piper synthesizes "Hello world" to a playable WAV file via sherpa-onnx
- [ ] Kokoro synthesizes text with correct voice embeddings via sherpa-onnx
- [ ] Supertonic synthesizes text via ONNX Runtime 4-stage pipeline
- [ ] No memory leaks after repeated synthesis/unload cycles
- [ ] Synthesis completes in <5 seconds for 100-word passages

---

## References

- [sherpa-onnx GitHub](https://github.com/k2-fsa/sherpa-onnx)
- [sherpa-onnx Maven](https://mvnrepository.com/artifact/com.bihe0832.android/lib-sherpa-onnx)
- [ONNX Runtime Android Guide](https://onnxruntime.ai/docs/get-started/with-java.html)
- [Supertonic GitHub](https://github.com/supertone-inc/supertonic)
- [Supertonic Architecture (DeepWiki)](https://deepwiki.com/supertone-inc/supertonic/2-core-architecture)
- [Supertonic Paper](https://arxiv.org/html/2503.23108v1)
- [Piper TTS GitHub](https://github.com/rhasspy/piper)
- [Kokoro TTS GitHub](https://github.com/nazdridoy/kokoro-tts)
- Existing manifest: `packages/downloads/lib/manifests/voices_manifest.json`

---

**Last Updated:** 2026-01-05
**Status:** Planning Complete - Ready for Implementation