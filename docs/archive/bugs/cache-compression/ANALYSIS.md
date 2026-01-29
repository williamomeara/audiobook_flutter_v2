# Cache Compression System - Analysis & Issues

## Overview

The app has TWO separate cache compression systems that don't work well together:

1. **Manual Compression** - User clicks "Compress Audio Cache" button in Settings
2. **On-the-Fly Compression** - Automatic compression during synthesis if enabled

## System 1: Manual Compression (Settings Button)

### Current Implementation

**Location**: `lib/ui/screens/settings_screen.dart` lines 1298-1600

**Flow**:
1. User clicks "Compress Audio Cache" button
2. Dialog shows compression progress
3. `AacCompressionService.compressDirectory()` compresses all WAV files to M4A
4. User can cancel or run in background
5. Shows snackbar with savings

**Code Path**:
```
settings_screen._showCompressCacheDialog()
  → AacCompressionService.compressDirectory()
    → AacCompressionService.compressFile() [for each WAV]
      → flutter_audio_toolkit.convertAudio() [native codec]
```

### Problems with Manual Compression

1. **Cache Metadata NOT Updated**
   - `compressDirectory()` deletes original WAV files
   - But doesn't update metadata entries in `IntelligentCacheManager`
   - Result: Cache manager still thinks WAV files exist

2. **No Cache Manager Integration**
   - Uses `AacCompressionService` directly
   - Ignores `IntelligentCacheManager._metadata` dictionary
   - When playback reads metadata, it can't find files

3. **Metadata Inconsistency Example**:
   ```
   Before compression:
   _metadata["book1_ch1_seg0.wav"] = {sizeBytes: 100000, ...}
   
   After compression:
   File system: "book1_ch1_seg0.m4a" (5882 bytes)
   But _metadata still has: "book1_ch1_seg0.wav" (100000 bytes)
   
   Result: Cache size calculations are wrong!
   ```

4. **Playback Issues**
   - `AudioCache.getPlayableFile()` looks for files by name
   - If metadata says ".wav" but file is ".m4a", playback fails
   - Or cache reports wrong sizes, causes eviction issues

## System 2: On-the-Fly Compression

### Current Implementation

**Location**: `lib/app/tts_providers.dart` lines 263-290

**Flow**:
1. If `compressOnSynthesize` setting is TRUE
2. After synthesis complete, invoke `onSynthesisComplete` callback
3. Callback calls `AacCompressionService.compressFile()`
4. Deletes original WAV file

**Code**:
```dart
onSynthesisComplete: settings.compressOnSynthesize
    ? (filePath) async {
        final result = await compressionService.compressFile(
          wavFile,
          deleteOriginal: true,
        );
      }
    : null,
```

### Problems with On-the-Fly Compression

1. **No Metadata Updates**
   - Same issue as manual compression
   - Files are created, registered in metadata as `.wav`
   - Immediately compressed to `.m4a`
   - But metadata not updated

2. **No Integration with Cache Manager**
   - Compression happens AFTER synthesis
   - Cache manager doesn't know about it
   - `saveAudioFile()` created metadata with `.wav` filename
   - Callback changes file to `.m4a` but metadata isn't updated

3. **Race Condition Potential**
   - Synthesis creates `segment_0.wav` → registers in metadata
   - Compression callback converts to `segment_0.m4a` → deletes `.wav`
   - Meanwhile, cache manager might try to access the `.wav` file

4. **Disabled in Practice**
   - Toggle switch exists (line 217 in settings_screen)
   - But probably broken due to above issues
   - Most users likely turned it OFF

## The Core Problem

Both systems bypass the `IntelligentCacheManager` which manages cache metadata. They:

1. Directly manipulate files (create/delete)
2. Never update the metadata dictionary
3. Never update SQLite `CacheEntryMetadata` table
4. Leave metadata pointing to non-existent files

## Consequences

### Cache Corruption

```
User enables "Compress on Synthesize"

1. New synthesis creates segment_0.wav (100KB)
   → metadata["segment_0.wav"] = {sizeBytes: 100000}
   
2. Callback immediately compresses to segment_0.m4a (5KB)
   → Deletes segment_0.wav
   
3. Cache manager reads metadata
   → Still thinks it has 100KB of uncompressed data
   → Reports wrong cache size
   → Eviction calculations are wrong

4. Next time app starts
   → Cache manager loads metadata
   → Tries to access "segment_0.wav"
   → File not found!
   → Either errors or silently fails
```

### Settings Menu Issues

- "Compress Audio Cache" button probably not working
- Compression happens, but cache size doesn't update
- Metadata corruption accumulates
- Over time, cache becomes inconsistent

## Why This Broke

The recent change to add `onSynthesisComplete` callback for on-the-fly compression didn't:
1. Update the metadata after compression
2. Integrate with `IntelligentCacheManager`
3. Handle the cache metadata storage layer

## The Fix Strategy

There are two approaches:

### Approach A: Integrate Compression into Cache Manager (Recommended)

Move compression logic INTO `IntelligentCacheManager`:

```dart
class IntelligentCacheManager {
  /// Compress a file and update metadata atomically
  Future<void> compressEntry(String filename) async {
    final file = File('$_cacheDir/$filename');
    
    // 1. Compress file
    final compressedFile = await _compressionService.compressFile(file);
    
    if (compressedFile == null) return; // Failed
    
    // 2. Update metadata atomically
    final oldMeta = _metadata.remove(filename);
    if (oldMeta != null) {
      final newFilename = filename.replaceAll('.wav', '.m4a');
      final newMeta = oldMeta.copyWith(
        key: newFilename,
        sizeBytes: await compressedFile.length(),
      );
      _metadata[newFilename] = newMeta;
      await _storage.removeEntry(filename);
      await _storage.upsertEntry(newMeta);
    }
  }
  
  /// Compress all WAV files and update metadata
  Future<CompressionResult> compressAllWavFiles() async {
    for (final entry in _metadata.entries.where((e) => e.key.endsWith('.wav'))) {
      await compressEntry(entry.key);
    }
  }
}
```

### Approach B: Remove Automatic Compression, Keep Manual Only

Simplest fix - disable `compressOnSynthesize` feature:
1. Remove the callback from ttsRoutingEngineProvider
2. Keep manual "Compress Cache" button
3. Fix manual button to properly update metadata

## Recommended Solution

**Implement Approach A** because:

1. **On-the-fly compression is valuable** - Saves space during synthesis
2. **Cache manager should own all metadata** - Single source of truth
3. **More reliable** - Atomic metadata updates prevent corruption
4. **Better UX** - Users don't have to manually compress

### Implementation Plan

1. Add `compressEntry()` method to `IntelligentCacheManager`
2. Update on-the-fly compression callback to use cache manager
3. Fix manual "Compress Cache" button to use same flow
4. Update cache metadata storage to track compressed files
5. Add migration for existing corrupted metadata

## Testing Checklist

- [ ] Enable "Compress on Synthesize" toggle
- [ ] Synthesize multiple segments
- [ ] Verify files are compressed (.m4a created, .wav deleted)
- [ ] Verify metadata shows correct filenames and sizes
- [ ] Check cache size calculation is accurate
- [ ] Restart app, verify cache still works
- [ ] Click "Compress Cache" button manually
- [ ] Verify all WAV files are compressed
- [ ] Verify metadata updated correctly
- [ ] Check cache eviction works with mixed WAV/M4A files
