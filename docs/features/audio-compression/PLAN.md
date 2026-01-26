# Audio Cache Compression Feature Plan

## Problem Statement

TTS synthesis generates WAV audio files (uncompressed PCM) which consume significant storage:
- WAV at 24kHz 16-bit mono: ~2.88 MB/minute
- A 10-hour audiobook: ~1.7 GB in WAV format
- Same content in AAC at 64kbps: ~29 MB (17x compression)

Users need a way to compress cached audio to reclaim storage space while preserving playback quality.

## Research Summary

### Format Recommendation: **AAC in M4A container**

| Factor | AAC/M4A | Opus |
|--------|---------|------|
| Speech quality at 64kbps | Excellent | Excellent |
| iOS native playback | ✅ Yes | ❌ No (needs libs) |
| Android native playback | ✅ Yes | ✅ Yes |
| just_audio support | ✅ Native | ❌ Requires FFI |
| Integration complexity | Low | High |
| File size (speech) | Good | Better |
| Licensing | Minimal | Royalty-free |

**Decision: Use AAC/M4A** - Native playback support on both platforms via just_audio, no additional libraries needed.

### Recommended Settings for TTS Speech
- **Codec:** AAC (Advanced Audio Coding)
- **Container:** M4A
- **Bitrate:** 64 kbps (excellent quality for speech, 17x compression vs WAV)
- **Channels:** Mono
- **Sample rate:** Preserve original (24kHz)

## Implementation Approach

### ~~Option A: ffmpeg_kit_flutter_audio~~ (Rejected)
**Pros:**
- Mature, well-documented
- Handles AAC encoding natively on both platforms
- Background processing support
- Progress callbacks

**Cons:**
- Adds ~15-30 MB to APK (audio-only variant)
- Requires separate iOS/Android variants
- Package retired in 2025 - maintenance risk
- Software CPU encoding (higher battery drain)
- Inferior AAC quality at low bitrates vs native

### Option B: flutter_audio_toolkit (Chosen)
**Pros:**
- Uses native OS encoders (MediaCodec on Android, AVFoundation on iOS)
- **Zero app size impact** - uses OS built-in codecs
- Hardware-accelerated encoding (faster, less battery)
- Better quality at low bitrates (native codecs optimized for speech)
- Actively maintained, modern Flutter API
- Progress callbacks

**Cons:**
- Newer package (less community examples)

**Decision: Use flutter_audio_toolkit** - Native codecs with zero size impact and better quality.

## Workplan

### Phase 1: Foundation ✅
- [x] Add flutter_audio_toolkit dependency
- [x] Create AacCompressionService in tts_engines package
- [x] Add compressed file detection to AudioCache (support .m4a files)
- [x] Implement playableFileFor() for transparent WAV/M4A playback

### Phase 2: Compression Engine
- [x] Implement WAV to M4A conversion with progress callbacks
- [x] Add batch compression with concurrency control
- [x] Implement abort/cancel support
- [ ] Add compression statistics tracking (space saved)

### Phase 3: Settings UI
- [ ] Add "Compress Cache" button in Storage section of settings
- [ ] Show compression progress dialog
- [ ] Display space saved after compression
- [ ] Add option to auto-compress on cache fill (optional, Phase 4)

### Phase 4: Cache Integration (Future)
- [ ] Auto-compress old entries when cache approaches limit
- [ ] Prefer evicting WAV over compressed when trimming cache
- [ ] Add setting: "Compress synthesized audio" (on-the-fly compression)

## Technical Details

### Native Conversion API
```dart
await audioToolkit.convertAudio(
  inputPath: '/path/to/input.wav',
  outputPath: '/path/to/output.m4a',
  format: AudioFormat.m4a,
  bitRate: 64,      // 64 kbps - excellent for speech
  sampleRate: 24000, // Match TTS output
  onProgress: (progress) {
    print('${(progress * 100).toInt()}%');
  },
);
```

### Dart Implementation Sketch
```dart
class CacheCompressionService {
  Future<CompressionResult> compressCache({
    required Directory cacheDir,
    void Function(int done, int total)? onProgress,
  }) async {
    final wavFiles = cacheDir.listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.wav'))
        .toList();
    
    int spaceSaved = 0;
    for (int i = 0; i < wavFiles.length; i++) {
      final result = await _compressFile(wavFiles[i]);
      spaceSaved += result.spaceSaved;
      onProgress?.call(i + 1, wavFiles.length);
    }
    
    return CompressionResult(spaceSaved: spaceSaved);
  }
  
  Future<FileCompressionResult> _compressFile(File wav) async {
    final m4aPath = wav.path.replaceAll('.wav', '.m4a');
    final command = '-i "${wav.path}" -c:a aac -b:a 64k "$m4aPath"';
    
    final session = await FFmpegKit.execute(command);
    if (ReturnCode.isSuccess(await session.getReturnCode())) {
      final originalSize = await wav.length();
      final compressedSize = await File(m4aPath).length();
      await wav.delete();
      return FileCompressionResult(
        spaceSaved: originalSize - compressedSize,
        success: true,
      );
    }
    return FileCompressionResult(spaceSaved: 0, success: false);
  }
}
```

### Cache Metadata Migration
The cache stores metadata in `.cache_metadata.json`. When compressing:
1. Update file path entries from `.wav` to `.m4a`
2. Keep all other metadata (access count, timestamps, positions)
3. No need to invalidate cache keys

### just_audio Compatibility
`just_audio` supports M4A/AAC natively - no changes needed to playback code. The `setFilePath()` method works with both .wav and .m4a files.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| FFmpeg adds APK bloat | Use audio-only variant (~15MB vs ~80MB full) |
| Compression is slow | Show progress, allow cancellation, run in background |
| Partially compressed cache | Atomic: only delete WAV after M4A verified |
| iOS App Store rejection | ffmpeg_kit is statically linked, no issues |

## Acceptance Criteria

1. User can tap "Compress Cache" in Settings → Storage
2. Progress dialog shows conversion status (X of Y files)
3. On completion, shows total space saved
4. Compressed audio plays identically to original
5. New synthesis continues to produce WAV (compression is opt-in)
6. Cache eviction works normally with mixed WAV/M4A files

## Estimated Effort

- Phase 1: 2-3 hours (foundation)
- Phase 2: 3-4 hours (compression engine)  
- Phase 3: 2-3 hours (UI)
- **Total: ~8-10 hours**

## Dependencies

```yaml
dependencies:
  ffmpeg_kit_flutter_audio: ^6.0.3
```

iOS Podfile (if not already present):
```ruby
pod 'ffmpeg-kit-ios-audio', '~> 6.0'
```
