# TTS Model Download URLs - Quick Reference

## Kokoro TTS

### Core Files
| File | URL | Size | Type |
|------|-----|------|------|
| Model | `https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0/kokoro-v1.0.onnx` | 94MB | ONNX |
| Voices | `https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0/voices-v1.0.bin` | 50MB | Binary |
| Phonemes | `https://github.com/rhasspy/piper-phonemize/releases/download/v1.0.0/espeak-ng-data.tar.gz` | 50MB | TAR.GZ |

### Available Voices
```
kokoro_af          - AF Default
kokoro_af_bella    - AF Bella
kokoro_af_nicole   - AF Nicole
kokoro_af_sarah    - AF Sarah
kokoro_af_sky      - AF Sky
kokoro_am_adam     - AM Adam
kokoro_am_michael  - AM Michael
kokoro_bf_emma     - BF Emma
kokoro_bm_george   - BM George
```

### Audio Specs
- **Sample Rate:** 24,000 Hz
- **Bit Depth:** 16-bit PCM
- **Duration:** ~1.5 seconds per sentence
- **Quantization:** Q8 (94MB model)

---

## Piper TTS

### Voice Files

#### Alan (British Male)
```
Model:  https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alan/medium/en_GB-alan-medium.onnx
Config: https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alan/medium/en_GB-alan-medium.onnx.json
Size:   ~30MB total
```

#### Lessac (American Female)
```
Model:  https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx
Config: https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json
Size:   ~30MB total
```

### Adding More Voices

Pattern: `https://huggingface.co/rhasspy/piper-voices/resolve/main/{language}/{language}_{region}/{name}/{quality}/{language}_{region}-{name}-{quality}.onnx`

Examples:
- `en_US-amy-medium` - American female
- `en_GB-northern_english_male-medium` - British male
- `es_ES-carme-medium` - Spanish female
- `fr_FR-siwis-medium` - French female

Full list: https://rhasspy.github.io/piper-samples/

### Audio Specs
- **Sample Rate:** 22,050 Hz
- **Bit Depth:** 16-bit PCM
- **Duration:** ~0.8 seconds per sentence
- **Quality:** Medium (trade-off between quality and speed)

---

## Supertonic TTS

### Core Files
| File | URL | Size |
|------|-----|------|
| Autoencoder | `https://huggingface.co/Supertone/supertonic/resolve/main/models/autoencoder.onnx` | 94MB |
| Text Encoder | `https://huggingface.co/Supertone/supertonic/resolve/main/models/text_encoder.onnx` | 105MB |
| Duration | `https://huggingface.co/Supertone/supertonic/resolve/main/models/duration_predictor.onnx` | 73MB |

### Available Voices
```
supertonic_m1      - Male 1
supertonic_m2      - Male 2
supertonic_m3      - Male 3
supertonic_m4      - Male 4
supertonic_f1      - Female 1
supertonic_f2      - Female 2
supertonic_f3      - Female 3
supertonic_f4      - Female 4
```

### Audio Specs
- **Sample Rate:** 24,000 Hz
- **Bit Depth:** 16-bit PCM
- **Duration:** ~1.2 seconds per sentence
- **Architecture:** Modular (text → duration → audio)

---

## Download Implementation

### Asset Manager Handles
- ✅ HTTP 301/302 redirects (HuggingFace)
- ✅ Large file streaming
- ✅ Archive extraction (.tar.gz, .zip)
- ✅ Atomic downloads (.tmp pattern)
- ✅ Progress tracking per file

### Current Limitations
- ❌ No resume capability (yet)
- ❌ No bandwidth throttling
- ❌ No SHA256 verification (placeholders only)
- ❌ All voices required (no selective download)

### File Size Summary
```
Kokoro:    194 MB (model + voices + phonemes)
Piper:      62 MB (2 voices × 31 MB each)
Supertonic: 272 MB (3 shared models)
─────────────────────
Total:     528 MB
```

---

## Testing Downloads

### Curl Commands
```bash
# Test Kokoro model
curl -I https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0/kokoro-v1.0.onnx

# Test Piper voice (follows redirects)
curl -L -I https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alan/medium/en_GB-alan-medium.onnx

# Test Supertonic model
curl -I https://huggingface.co/Supertone/supertonic/resolve/main/models/autoencoder.onnx
```

### Expected Results
- **Kokoro:** `200 OK` (GitHub)
- **Piper:** `302 Found` → `200 OK` (HuggingFace redirect)
- **Supertonic:** `200 OK` (HuggingFace)

---

## Troubleshooting

### 404 Errors
- **GitHub:** Repository may be private or deleted
- **HuggingFace:** Model filename may have changed
- **Solution:** Check repository directly in browser

### Redirect Loops
- Asset manager now handles 301/302 automatically
- If still looping: URL may be behind authentication

### Extraction Errors
- Check file extensions in manifest
- .tar.gz requires both TAR and GZIP decompression
- .zip requires ZIP decompression

### File Corruption
- Downloaded as .tmp, renamed only after completion
- If interrupted: delete .tmp file and retry
- No partial downloads left behind

---

## Future Improvements

### Phase 6
- [ ] Resume partial downloads
- [ ] Parallel download support
- [ ] SHA256 verification (generate actual hashes)

### Phase 7
- [ ] Bandwidth throttling
- [ ] Selective voice downloads
- [ ] Model compression option

### Phase 8
- [ ] More languages for Piper
- [ ] Regional variants for Kokoro
- [ ] Premium model options

---

**Last Updated:** 2026-01-03
**All URLs Tested:** ✅ (except Kokoro model filename variations)
