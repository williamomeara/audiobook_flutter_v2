# Implementation Plan Improvements & Recommendations

## CRITICAL: NO BACKWARDS COMPATIBILITY

**This plan is designed to completely replace the old download system.** We are NOT maintaining compatibility with legacy bulk downloads. The old system will be discarded entirely.

- ✋ No legacy detection
- ✋ No migration helpers
- ✋ No fallback to bulk downloads
- ✋ No version-aware state loading
- ✋ Clean slate on app update

Users with old downloads can simply re-download voices in the new system. This keeps implementation clean and prevents technical debt.

---

## 1. MANIFEST STRUCTURE OBSERVATIONS & IMPROVEMENTS

### Current Issues:
- Piper and Kokoro models have inconsistent structures (cores vs individual voices)
- Piper models listed as "cores" but they're actually self-contained voice models
- Inconsistent "required" flags (all marked true, but not all should be)
- Duplicate file download info in Piper entries (url field + files array)
- SHA256 checksums are placeholders

### Recommendations:

**1a. Clarify "required" semantics**
- Add `required: true` only to actual engine cores:
  - `kokoro_model_v1`: YES (all Kokoro voices need this)
  - `kokoro_voices_v1`: YES (all Kokoro voices need this)
  - `espeak_ng_data_v1`: YES (all Kokoro voices need this)
  - Piper voice models: NO (user selects which voices)
  - Supertonic components: NO (user may not want Supertonic)

**1b. Add explicit "type" field**
```json
{
  "id": "kokoro_model_v1",
  "type": "engine_core",
  "engineType": "kokoro",
  ...
}
```
Types: `engine_core`, `voice_model`, `engine_dependency`

**1c. Simplify file structures**
- Remove duplicate URLs from Piper entries
- Use single consistent pattern:
  ```json
  {
    "id": "piper_alan_gb_v1",
    "type": "voice_model",
    "displayName": "Piper - Alan (British)",
    "files": [
      {
        "name": "en_GB-alan-medium.onnx",
        "url": "https://huggingface.co/...",
        "size": 31457280,
        "sha256": "actual_hash_here"
      },
      {
        "name": "en_GB-alan-medium.onnx.json",
        "url": "https://huggingface.co/...",
        "size": 2048,
        "sha256": "actual_hash_here"
      }
    ]
  }
  ```

**1d. Fix placeholder checksums**
- Add real SHA256 hashes for all files
- Consider automated checksum validation in CI/CD
- Document how to generate/verify checksums

---

## 2. STATE MANAGEMENT DESIGN IMPROVEMENTS

### Current Plan Issues:
- Separate `coreStates` and `voiceStates` Maps create synchronization complexity
- Voice dependencies on cores must be checked manually in UI
- Potential for inconsistent state (voice marked ready but core missing)

### Recommendations:

**2a. Create wrapper state classes**

Wrap dependent relationships:
```dart
class CoreDownloadState {
  final String coreId;
  final String displayName;
  final DownloadStatus status;
  final double progress;
  final String? error;
  
  bool get isReady => status == DownloadStatus.ready;
}

class VoiceDownloadState {
  final String voiceId;
  final String displayName;
  final DownloadStatus status;
  final double progress;
  final List<CoreDownloadState> requiredCores;
  final String? error;
  
  bool get canDownload => requiredCores.every((c) => c.isReady);
  bool get allDependenciesMet => requiredCores.every((c) => c.isReady);
  
  DownloadStatus get effectiveStatus {
    if (status == DownloadStatus.ready && !allDependenciesMet) {
      return DownloadStatus.failed; // Core was deleted
    }
    return status;
  }
}
```

**2b. Create computed state provider**

Single source of truth:
```dart
final computedDownloadStateProvider = Provider((ref) {
  final rawState = ref.watch(granularDownloadManagerProvider);
  final manifest = ref.watch(voiceManifestProvider);
  
  return ComputedDownloadState(
    cores: buildCoreStates(rawState, manifest),
    voices: buildVoiceStates(rawState, manifest),
    coredependencies: buildDependencyGraph(manifest),
  );
});
```

Benefits:
- UI only checks `voice.canDownload` instead of checking all cores
- Prevents inconsistent state display
- Easier to test and debug

**2c. Replace raw Map states with typed collections**

Instead of:
```dart
final Map<String, DownloadStatus> voiceStates;
```

Use:
```dart
final Map<String, VoiceDownloadState> voiceStates;
```

This moves validation logic to the state class.

---

## 3. DOWNLOAD MANAGER IMPLEMENTATION STRATEGY

### Current Plan Issues:
- Plan mentions sequential downloads but no queue management
- No concurrent download limits specified
- Missing download prioritization strategy
- No handling for auto-downloading dependencies

### Recommendations:

**3a. Implement download queue with limits**

```dart
class DownloadQueue {
  final int maxConcurrent = 2; // Limit network + disk I/O
  final List<QueuedDownload> queue = [];
  final Set<String> downloading = {};
  
  Future<void> enqueue(String itemId, Future Function() downloadFn);
  void prioritize(String itemId); // Move to front
  Future<void> cancel(String itemId);
  Stream<DownloadQueueState> watchQueue();
}
```

Reasoning:
- 1-2 concurrent downloads balances speed vs network stability
- Prevents overwhelming device resources
- Allows cancellation mid-download

**3b. Automatic prerequisite downloading**

```dart
Future<void> downloadVoice(String voiceId) async {
  final voice = manifest.getVoice(voiceId);
  final missingCores = voice.coreRequirements
    .where((id) => !isCoreDownloaded(id))
    .toList();
  
  if (missingCores.isNotEmpty) {
    // Auto-download missing cores first
    state = state.copyWith(currentDownload: 'Auto-downloading cores...');
    for (final coreId in missingCores) {
      await downloadCore(coreId);
    }
  }
  
  state = state.copyWith(currentDownload: 'Downloading $voiceId');
  await _downloadVoiceImpl(voiceId);
}
```

Benefits:
- User selects voice, system handles dependencies
- No confusing "core not found" errors
- Clear progress indication for all steps

**3c. Batch download operations**

```dart
Future<void> downloadMultiple(List<String> voiceIds) async {
  // Collect unique cores needed
  final allCoresNeeded = voiceIds
    .expand((vid) => manifest.getVoice(vid)?.coreRequirements ?? [])
    .toSet();
  
  // Download unique cores once (deduplication)
  for (final coreId in allCoresNeeded) {
    if (!isCoreDownloaded(coreId)) {
      await downloadCore(coreId);
    }
  }
  
  // Then download voices
  for (final voiceId in voiceIds) {
    if (!isVoiceDownloaded(voiceId)) {
      await downloadVoice(voiceId);
    }
  }
}
```

Use case: "Download all Kokoro voices" button

**3d. Download state persistence**

Store queue across app restarts:
```dart
class PersistentDownloadQueue {
  Future<void> saveQueueState(List<QueuedDownload> items);
  Future<List<QueuedDownload>> loadQueueState();
}
```

---

## 4. ERROR HANDLING & RECOVERY IMPROVEMENTS

### Current Plan Issues:
- Generic error messages mentioned but no error categorization
- No differentiation between retryable errors (network) vs fatal (permissions)
- Missing multi-file download atomicity (Piper, Supertonic have 2+ files)
- No resume capability for large downloads

### Recommendations:

**4a. Error categorization & recovery strategy**

```dart
enum DownloadErrorType {
  networkTimeout,      // → Retry with exponential backoff
  networkUnreachable,  // → Retry with backoff
  noSpace,             // → User action: delete files or settings
  checksumMismatch,    // → Delete + retry (corrupted download)
  filePermissions,     // → Fatal: user must fix system
  interrupted,         // → Resume or retry
  manifestError,       // → User must update app
  unknown;             // → Log for support
  
  bool get isRetryable => !{filePermissions, manifestError}.contains(this);
  Duration getRetryDelay(int attemptNumber) {
    if (!isRetryable) return Duration.zero;
    return Duration(seconds: pow(2, attemptNumber.clamp(0, 5)).toInt());
  }
}

class DownloadException implements Exception {
  final DownloadErrorType type;
  final String message;
  final int? attemptNumber;
  
  bool get shouldRetry => type.isRetryable && (attemptNumber ?? 0) < 5;
}
```

**4b. Multi-file download atomicity**

For Piper and Supertonic (2+ file downloads):

```dart
Future<void> downloadMultiFile(List<FileSpec> files, String destDir) async {
  final tmpDir = '$destDir.tmp';
  
  try {
    // 1. Download all files to .tmp
    await Directory(tmpDir).create(recursive: true);
    for (final file in files) {
      await _downloadFile(file.url, '$tmpDir/${file.name}');
    }
    
    // 2. Verify ALL checksums
    for (final file in files) {
      final path = '$tmpDir/${file.name}';
      final hash = await _sha256File(path);
      if (hash != file.sha256) {
        throw DownloadException(
          type: DownloadErrorType.checksumMismatch,
          message: 'File ${file.name} corrupted',
        );
      }
    }
    
    // 3. Atomic move (all or nothing)
    await Directory(destDir).delete(recursive: true);
    await Directory(tmpDir).rename(destDir);
    
    // 4. Write success marker
    File('$destDir/.manifest').writeAsStringSync(
      jsonEncode({'status': 'ready', 'timestamp': DateTime.now().toIso8601String()})
    );
  } catch (e) {
    // Cleanup on failure
    await Directory(tmpDir).delete(recursive: true);
    rethrow;
  }
}
```

**4c. Resume capability**

For resumable downloads, store metadata:
```dart
class PartialDownload {
  final String itemId;
  final String url;
  final String tmpPath;
  final int downloadedBytes;
  final int totalBytes;
  final DateTime startTime;
  
  bool get isExpired => DateTime.now().difference(startTime).inHours > 24;
}

Future<void> resumeDownload(String itemId) async {
  final partial = await _loadPartialDownload(itemId);
  if (partial.isExpired) {
    // Delete and restart
    await File(partial.tmpPath).delete();
    await downloadFresh(itemId);
  } else {
    // Resume from where we left off
    await _downloadFile(
      partial.url,
      partial.tmpPath,
      resumeFromByte: partial.downloadedBytes,
    );
  }
}
```

---

## 5. FILE SYSTEM ORGANIZATION IMPROVEMENTS

### Current Plan Issues:
- Proposed `cores/` and `voices/` structure confuses Piper models (they're both)
- No space management strategy
- No registry for tracking all downloads in one place

### Recommendations:

**5a. Cleaner hierarchical structure**

```
<cache>/voice_assets/
├── .registry                         # Single file tracking all downloads
├── kokoro/
│   ├── model_v1/
│   │   ├── model.onnx
│   │   └── .manifest
│   ├── voices_v1/
│   │   ├── voices.bin
│   │   └── .manifest
│   └── espeak_ng_data_v1/
│       ├── espeak-ng-data.tar
│       └── .manifest
├── piper/
│   ├── en_GB-alan-medium/          # Self-contained voice models
│   │   ├── model.onnx
│   │   ├── model.onnx.json
│   │   └── .manifest
│   └── en_US-lessac-medium/
│       ├── model.onnx
│       ├── model.onnx.json
│       └── .manifest
└── supertonic/
    ├── autoencoder_v1/
    │   ├── autoencoder.onnx
    │   └── .manifest
    ├── text_encoder_v1/
    │   ├── text_encoder.onnx
    │   └── .manifest
    └── duration_predictor_v1/
        ├── duration_predictor.onnx
        └── .manifest
```

**5b. Add .registry for space tracking**

```json
{
  "lastUpdated": "2026-01-05T20:01:17.784Z",
  "downloads": [
    {
      "id": "kokoro_model_v1",
      "path": "kokoro/model_v1",
      "size": 94371840,
      "status": "ready",
      "timestamp": "2026-01-05T15:00:00Z"
    },
    {
      "id": "piper_en_GB_alan_medium",
      "path": "piper/en_GB-alan-medium",
      "size": 31459328,
      "status": "ready",
      "timestamp": "2026-01-05T15:30:00Z"
    }
  ],
  "totalSize": 125831168,
  "version": 1
}
```

**5c. Implement space management**

```dart
class VoiceAssetManager {
  Future<int> estimateTotalSize(List<String> voiceIds) async {
    final cores = _getRequiredCores(voiceIds);
    final sizes = cores + voiceIds
      .map((vid) => manifest.getSize(vid))
      .fold(0, (a, b) => a + b);
    return sizes;
  }
  
  Future<void> cleanup({
    required int targetBytes,
    List<String>? protectVoiceIds,
  }) async {
    // LRU-style cleanup: delete least recently used first
    // But never delete protected voices
    final registry = await _loadRegistry();
    final candidates = registry.downloads
      .where((d) => !protectVoiceIds.contains(d.id))
      .sorted((a, b) => a.timestamp.compareTo(b.timestamp))
      .toList();
    
    var freed = 0;
    for (final item in candidates) {
      if (freed >= targetBytes) break;
      await deleteDownload(item.id);
      freed += item.size;
    }
  }
}
```

---

## 6. TESTING STRATEGY GAPS & ADDITIONS

### Current Plan Issues:
- Testing section is high-level, missing specific test scenarios
- No mock implementations for testing
- Missing edge case coverage (corrupted files, concurrent operations, etc.)

### Recommendations:

**6a. Unit test structure**

```dart
group('VoiceManifestService', () {
  test('getVoicesForCore returns only voices for that core', () {
    final service = VoiceManifestService(mockManifest);
    final kokoroVoices = service.getVoicesForCore('kokoro_model_v1');
    expect(kokoroVoices, hasLength(6));
    expect(kokoroVoices.every((v) => v.engineId == 'kokoro'), true);
  });
  
  test('getRequiredCores includes all transitive dependencies', () {
    final service = VoiceManifestService(mockManifest);
    final cores = service.getRequiredCores('kokoro_af');
    expect(cores, containsAll([
      'kokoro_model_v1',
      'kokoro_voices_v1',
      'espeak_ng_data_v1',
    ]));
  });
  
  test('canDownloadVoice returns false if any core missing', () {
    final service = VoiceManifestService(mockManifest);
    // Setup: kokoro core missing, voices present
    expect(service.canDownloadVoice('kokoro_af'), false);
  });
});

group('DownloadQueue', () {
  test('respects maxConcurrent limit', () async {
    final queue = DownloadQueue(maxConcurrent: 2);
    final results = <String>[];
    
    // Enqueue 5 downloads
    for (int i = 0; i < 5; i++) {
      queue.enqueue('download_$i', () async {
        results.add('start_$i');
        await Future.delayed(Duration(milliseconds: 100));
        results.add('end_$i');
      });
    }
    
    // Wait for completion
    await queue.waitAll();
    
    // Verify only 2 were active at any time
    // (This requires clever timing verification)
  });
  
  test('cancel removes queued download', () async {
    final queue = DownloadQueue();
    queue.enqueue('test', () async {});
    queue.cancel('test');
    
    final state = await queue.watchQueue().first;
    expect(state.queue, isEmpty);
  });
});
```

**6b. Integration test scenarios**

```dart
group('Download Flow Integration Tests', () {
  test('Download voice auto-downloads missing cores', () async {
    final manager = GranularDownloadManager();
    
    // Voice requires cores that aren't downloaded
    expect(manager.isCoreDownloaded('kokoro_model_v1'), false);
    
    // Download voice
    final state = await manager.downloadVoice('kokoro_af').first;
    
    // Should have downloaded all required cores
    expect(manager.isCoreDownloaded('kokoro_model_v1'), true);
    expect(manager.isCoreDownloaded('kokoro_voices_v1'), true);
    expect(manager.isVoiceDownloaded('kokoro_af'), true);
  });
  
  test('Partial failure with multi-file download', () async {
    final manager = GranularDownloadManager();
    
    // Mock: first file succeeds, second file fails (network error)
    mockDownloader.failOn('en_GB-alan-medium.onnx.json');
    
    // Should rollback entire download
    await expectLater(
      manager.downloadVoice('piper_en_GB_alan_medium'),
      throwsA(isA<DownloadException>()),
    );
    
    // Directory should be cleaned up
    expect(File('$voiceDir/en_GB-alan-medium/model.onnx').exists(), false);
  });
  
  test('Resume interrupted download', () async {
    final manager = GranularDownloadManager();
    
    // Start download
    final future = manager.downloadVoice('piper_en_GB_alan_medium');
    
    // Interrupt after 50%
    await Future.delayed(Duration(milliseconds: 50));
    await manager.cancel('piper_en_GB_alan_medium');
    
    // Resume
    final resumed = await manager.downloadVoice('piper_en_GB_alan_medium');
    expect(resumed.status, DownloadStatus.ready);
  });
});
```

**6c. Performance tests**

```dart
group('Performance Tests', () {
  test('Manifest parsing < 100ms for 100+ voices', () async {
    final largeManifest = _generateLargeManifest(100);
    
    final stopwatch = Stopwatch()..start();
    final service = VoiceManifestService(largeManifest);
    final cores = service.getAllCores();
    stopwatch.stop();
    
    expect(stopwatch.elapsedMilliseconds, lessThan(100));
  });
  
  test('State update performance < 16ms', () async {
    final manager = GranularDownloadManager();
    
    final stopwatch = Stopwatch()..start();
    manager.updateProgress('voice_id', 0.5);
    stopwatch.stop();
    
    expect(stopwatch.elapsedMilliseconds, lessThan(16)); // 60 FPS
  });
});
```

---

## 7. MIGRATION & BACKWARDS COMPATIBILITY STRATEGY

### ❌ REMOVED - NOT APPLICABLE

**We are NOT supporting backwards compatibility.** The old bulk download system will be completely replaced.

**App Update Strategy:**
1. Deploy new version with granular downloads only
2. Old downloads in cache are orphaned (harmless, can be manually cleared)
3. Users download voices again in new system (takes ~5 minutes per voice)
4. No confusion, no legacy code to maintain

This approach:
- ✅ Eliminates 1000+ lines of migration code
- ✅ Prevents state sync bugs between old/new systems
- ✅ Simplifies testing (only test new path)
- ✅ Makes codebase cleaner and faster
- ✅ No tech debt from supporting both systems

Users who care about their old downloads can manually copy files to new locations if needed (advanced users only).

---

---

## 8. PHASE TIMELINE ADJUSTMENTS

### Clean Slate Advantage: 4 Days Saved!

Since we're not maintaining backwards compatibility:
- ❌ No legacy detection code
- ❌ No migration tests
- ❌ No versioned state loaders
- ❌ No rollback procedures
- ✅ 4 days of implementation time saved

### Simplified Timeline:

**Phase 1: Core Infrastructure (2.5 weeks)**
- ✅ Update TtsDownloadState for granular tracking
- ✅ Create GranularDownloadManager
- ✅ Update AtomicAssetManager for individual downloads
- ✅ Parse manifest for cores and voices
- ✅ Create unit tests (dependency resolution, state machine)
- **Checkpoint**: Code review, API design approval

**Phase 2: UI & UX (3 weeks)**
- ✅ Design DownloadManagerScreen
- ✅ Implement CoreDownloadCard and VoiceDownloadCard
- ✅ Add dependency indicators and status badges
- ✅ Update settings navigation and voice picker integration
- ✅ Widget tests and visual testing
- **Checkpoint**: UX review with test users (informal, 2-3 users)

**Phase 3: Integration & Testing (2.5 weeks)**
- ✅ Integrate with voice selection (filter picker to show only ready voices)
- ✅ Add download navigation from voice picker
- ✅ Error handling and recovery scenarios
- ✅ Performance profiling (manifest parsing, state updates)
- ✅ Real device testing (Android emulator + physical device)
- **Checkpoint**: Release readiness check

**Phase 4: Polish & Release (1 week)**
- ✅ Edge case fixes
- ✅ Documentation and code comments
- ✅ Final QA pass
- ✅ Release preparation

**Total: 9 weeks** (was 8 weeks in plan, 13 with all the backwards compat work)

### Key Advantages of Clean Slate:

| Area | Old System | New System | Benefit |
|------|-----------|-----------|---------|
| **Download Logic** | Bulk engines (3 paths) | Granular cores + voices (1 unified path) | Simpler, more maintainable |
| **State Management** | 3 separate engine states | Unified granular state with computed views | Easier to reason about |
| **File Organization** | Mixed legacy/new | Clean hierarchy from day 1 | No special case handling |
| **Testing** | Test both paths | Test one path | 30% fewer tests needed |
| **Error Handling** | Generic "try again" | Categorized with specific strategies | Better UX |
| **User Experience** | All-or-nothing downloads | Pick exactly what you want | Obvious improvement |

---

## 9. VOICE PICKER INTEGRATION SPECIFICS

### Current Plan Issues:
- Assumes UI exists but doesn't specify implementation details
- No loading states during voice download from picker
- Missing "download this voice" quick action
- No indication of download progress

### Recommendations:

**9a. VoicePicker widget improvements**

```dart
class VoicePicker extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(computedDownloadStateProvider);
    final selectedVoice = ref.watch(selectedVoiceProvider);
    final readyVoices = downloadState.getReadyVoices();
    
    return Column(
      children: [
        // No voices available
        if (readyVoices.isEmpty)
          _NoVoicesPlaceholder(
            onDownloadTap: () {
              ref.read(selectedVoiceProvider.notifier).state = null;
              context.push('/settings/downloads');
            },
          ),
        
        // Voice options with download status badges
        if (readyVoices.isNotEmpty)
          SegmentedButton<String>(
            segments: readyVoices.map((voice) {
              return ButtonSegment(
                value: voice.id,
                label: Text(voice.displayName),
                // Show download icon if downloading
                icon: downloadState.isDownloading(voice.id)
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              );
            }).toList(),
            selected: {selectedVoice.id},
            onSelectionChanged: (set) {
              ref.read(selectedVoiceProvider.notifier).state = set.first;
            },
          ),
        
        // Show unavailable voices with download option
        if (downloadState.unavailableVoices.isNotEmpty)
          ExpansionTile(
            title: const Text('Download More Voices'),
            children: [
              Wrap(
                spacing: 8,
                children: downloadState.unavailableVoices.map((voice) {
                  final status = downloadState.getVoiceStatus(voice.id);
                  return FilterChip(
                    label: Text(voice.displayName),
                    onSelected: (_) => _startVoiceDownload(context, ref, voice),
                    // Show download icon
                    avatar: Icon(
                      status.isDownloading
                        ? Icons.download_outlined
                        : Icons.add,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
      ],
    );
  }
  
  void _startVoiceDownload(
    BuildContext context,
    WidgetRef ref,
    VoiceDownloadState voice,
  ) {
    ref
      .read(granularDownloadManagerProvider.notifier)
      .downloadVoice(voice.id);
    
    // Show snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading ${voice.displayName}...'),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
```

**9b. No Voices Placeholder widget**

```dart
class _NoVoicesPlaceholder extends StatelessWidget {
  final VoidCallback onDownloadTap;
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(Icons.cloud_download_outlined, size: 48),
          const SizedBox(height: 12),
          const Text(
            'No voices downloaded',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Download a voice engine to get started',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onDownloadTap,
            icon: const Icon(Icons.download),
            label: const Text('Download Voices'),
          ),
        ],
      ),
    );
  }
}
```

**9c. Long-press quick download**

```dart
class VoiceOption extends ConsumerWidget {
  final VoiceDownloadState voice;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onLongPress: voice.canDownload
        ? () => _showQuickDownloadDialog(context, ref)
        : null,
      child: ListTile(
        title: Text(voice.displayName),
        subtitle: voice.canDownload ? null : Text('Requires: ${voice.missingDependencies}'),
        trailing: voice.status == DownloadStatus.downloading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
          : null,
      ),
    );
  }
  
  void _showQuickDownloadDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Download ${voice.displayName}?'),
        content: Text('Size: ${formatBytes(voice.estimatedSize)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              ref.read(granularDownloadManagerProvider.notifier).downloadVoice(voice.id);
              Navigator.pop(context);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }
}
```

---

## 10. CONCURRENT ACCESS SAFETY

### Not Mentioned in Plan:
- What if user tries to play voice while it's downloading?
- What if voice is deleted while being used for playback?
- File locking across Android/iOS platforms

### Recommendations:

**10a. Usage tracking and locking**

```dart
class VoiceUsageManager {
  final Map<String, int> _lockCounts = {};
  
  /// Lock a voice to prevent deletion while in use
  Future<VoiceLock> lockVoice(String voiceId) async {
    _lockCounts[voiceId] = (_lockCounts[voiceId] ?? 0) + 1;
    return VoiceLock(voiceId, this);
  }
  
  /// Unlock a voice (called when done using)
  void unlockVoice(String voiceId) {
    _lockCounts[voiceId] = max(0, (_lockCounts[voiceId] ?? 0) - 1);
  }
  
  /// Check if voice is in use
  bool isLocked(String voiceId) => (_lockCounts[voiceId] ?? 0) > 0;
  
  /// Delete voice (respects locks)
  Future<void> deleteVoice(String voiceId) async {
    if (isLocked(voiceId)) {
      throw VoiceInUseException(
        'Cannot delete $voiceId while it is being played'
      );
    }
    await _deleteVoiceImpl(voiceId);
  }
}

/// RAII-style lock management
class VoiceLock {
  final String voiceId;
  final VoiceUsageManager manager;
  bool _released = false;
  
  VoiceLock(this.voiceId, this.manager);
  
  void release() {
    if (!_released) {
      manager.unlockVoice(voiceId);
      _released = true;
    }
  }
  
  ~VoiceLock() => release();
}
```

**10b. Graceful playback degradation**

```dart
class PlaybackVoiceManager {
  Future<void> playWithVoice(String voiceId) async {
    // Lock voice to prevent deletion
    final lock = await voiceUsageManager.lockVoice(voiceId);
    
    try {
      final voiceFile = await voiceManager.getVoiceFile(voiceId);
      
      if (!voiceFile.existsSync()) {
        // Voice was deleted - fallback to default
        developer.log('Voice file deleted during playback, using fallback');
        await _playWithDefaultVoice();
        return;
      }
      
      await audioPlayer.setAudioSource(voiceFile);
      await audioPlayer.play();
    } finally {
      lock.release(); // Unlocks voice when done
    }
  }
}
```

**10c. Delete confirmation for in-use voices**

```dart
class VoiceDeleteDialog extends ConsumerWidget {
  final String voiceId;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usageManager = ref.watch(voiceUsageManagerProvider);
    final isInUse = usageManager.isLocked(voiceId);
    
    if (isInUse) {
      return AlertDialog(
        title: const Text('Voice Currently In Use'),
        content: const Text(
          'This voice is currently being used for playback. '
          'Stop playback and try again.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      );
    }
    
    return AlertDialog(
      title: const Text('Delete Voice?'),
      content: const Text('This action cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: () {
            ref
              .read(granularDownloadManagerProvider.notifier)
              .deleteVoice(voiceId);
            Navigator.pop(context);
          },
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
```

---

## 11. DOCUMENTATION IMPROVEMENTS

### Current Plan Missing:

**11a. Architecture Diagrams**
- Add state transition diagram (notDownloaded → queued → downloading → extracting → ready → failed)
- Add dependency graph showing voice → cores relationships
- Add sequence diagram showing happy path + error recovery

**11b. Code Examples**

```dart
// Example 1: Download a single voice (auto-downloads cores)
final manager = ref.read(granularDownloadManagerProvider.notifier);
await manager.downloadVoice('kokoro_af').first;

// Example 2: Download all voices for an engine
await manager.downloadAllForEngine('kokoro');

// Example 3: Handle download with error recovery
try {
  await manager.downloadVoice('piper_en_GB_alan_medium');
} on DownloadException catch (e) {
  if (e.type.isRetryable) {
    await Future.delayed(e.type.getRetryDelay(0));
    await manager.downloadVoice('piper_en_GB_alan_medium');
  } else {
    // Show user-friendly error
    showErrorDialog(context, e.message);
  }
}
```

**11c. Troubleshooting Guide**

Document common issues:
- "Downloads keep failing" → Check storage space, network connection
- "Voice won't play after download" → Verify manifest, check file permissions
- "Strange state after app crash" → Explain migration process, recovery options
- "Some voices missing" → Explain manifest versioning, update procedure

---

## 12. PERFORMANCE & OPTIMIZATION CONSIDERATIONS

### Current Plan Missing:

**12a. Lazy manifest loading**

```dart
final lazyManifestProvider = FutureProvider((ref) async {
  // Only load manifest when needed
  return VoiceManifestService(
    await _loadManifest(),
  );
});

// Load only specific engine
final engineVoicesProvider = FutureProvider.family((ref, String engineId) async {
  final manifest = await ref.watch(lazyManifestProvider.future);
  return manifest.getVoicesForEngine(engineId);
});
```

**12b. Efficient state queries**

```dart
class ManifestIndex {
  late final Map<String, List<String>> _byEngine;
  late final Map<String, VoiceSpec> _voicesById;
  late final Map<String, CoreRequirement> _coresById;
  
  ManifestIndex(VoiceManifestV2 manifest) {
    // Build indices for O(1) lookups
    _byEngine = manifest.voices
      .groupBy((v) => v.engineId);
    _voicesById = {for (var v in manifest.voices) v.id: v};
    _coresById = {for (var c in manifest.cores) c.id: c};
  }
  
  List<VoiceSpec> getVoicesForEngine(String engineId) => _byEngine[engineId] ?? [];
  VoiceSpec? getVoice(String id) => _voicesById[id];
  CoreRequirement? getCore(String id) => _coresById[id];
}
```

**12c. Download optimization**

```dart
class OptimizedDownloader {
  /// Download multiple files in parallel (with limits)
  Future<void> downloadMultipleParallel(
    List<FileSpec> files,
    String destDir, {
    int maxConcurrent = 2,
  }) async {
    final queue = DownloadQueue(maxConcurrent: maxConcurrent);
    
    for (final file in files) {
      queue.enqueue(file.url, () => _downloadFile(file, destDir));
    }
    
    await queue.waitAll();
  }
  
  /// Resume-capable download
  Future<void> downloadWithResume(FileSpec file, String destPath) async {
    final existingSize = File(destPath).lengthSync();
    
    if (existingSize > 0) {
      // Try to resume
      await _downloadFile(
        file,
        destPath,
        resumeFromByte: existingSize,
      );
    } else {
      await _downloadFile(file, destPath);
    }
  }
}
```

---

## Summary of Key Improvements

| Area | Improvement | Impact |
|------|-------------|--------|
| **Manifest** | Add type/required fields, fix structure | Clearer intent, easier implementation |
| **State** | Use typed wrapper classes, computed state | Prevent inconsistent state, simpler UI |
| **Downloads** | Queue management, auto-prereq, batch ops | Better UX, deduplication, no surprise errors |
| **Errors** | Categorized errors, recovery strategies | Robust app, better diagnostics |
| **Files** | Cleaner structure, atomic multi-file, registry | Easier debugging, space tracking |
| **Testing** | Specific unit/integration/perf tests | Confidence in implementation |
| **Migration** | Version-aware loading, rollback capability | Safe upgrades, data preservation |
| **Timeline** | 13 weeks instead of 8 (realistic) | Achievable deadlines, quality output |
| **Voice Picker** | Download integration, quick actions | Better UX, discoverability |
| **Concurrency** | Usage locks, graceful degradation | Reliable playback, no crashes |

