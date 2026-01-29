# Downloads Improvements - Step-by-Step Implementation Plan

## Overview

This is a complete, step-by-step implementation guide for the granular downloads system. **No backwards compatibility** - we're building a clean, new system from scratch.

## Summary of Changes

Replace bulk engine downloads with granular core + voice downloads:
- Users download exactly what they need (not all-or-nothing)
- Auto-download dependencies when selecting a voice
- Better progress tracking and error handling
- Clean file organization with registry tracking

---

## Phase 1: Core Infrastructure (Steps 1-10)

### Step 1: Update Manifest Structure

**File:** `packages/downloads/lib/manifests/voices_manifest.json`

**Changes:**
1. Add `type` field to cores: `"engine_core"`, `"voice_model"`, `"engine_dependency"`
2. Fix `required` flags - only Kokoro cores are truly required (shared by all Kokoro voices)
3. Remove duplicate URL fields (Piper entries have both `url` and `files`)
4. Add real SHA256 checksums (or remove if not available)

**Result:** Cleaner manifest with clear semantics about what each item is.

---

### Step 2: Create Domain Models for Manifest

**File:** `packages/downloads/lib/src/models/manifest_models.dart` (new)

**Create:**
```dart
/// Type of downloadable asset
enum AssetType {
  engineCore,      // Shared core (e.g., Kokoro model)
  voiceModel,      // Self-contained voice (e.g., Piper Alan)
  engineDependency // Supporting files (e.g., eSpeak data)
}

/// Core asset specification
class CoreSpec {
  final String id;
  final AssetType type;
  final String engineType;
  final String displayName;
  final String? url;
  final int sizeBytes;
  final String? sha256;
  final List<FileSpec> files;
  
  // Computed
  int get totalSize => files.isEmpty ? sizeBytes : files.fold(0, (a, f) => a + f.sizeBytes);
}

/// File within a multi-file download
class FileSpec {
  final String filename;
  final String url;
  final int sizeBytes;
  final String? sha256;
}

/// Voice specification
class VoiceSpec {
  final String id;
  final String engineId;
  final String displayName;
  final String language;
  final String gender;
  final List<String> coreRequirements;
  final int? speakerId;
  final String? modelKey;
}

/// Parsed manifest
class VoiceManifest {
  final int version;
  final DateTime lastUpdated;
  final List<CoreSpec> cores;
  final List<VoiceSpec> voices;
}
```

---

### Step 3: Create Manifest Parser & Service

**File:** `packages/downloads/lib/src/manifest_service.dart` (new)

**Create:**
```dart
class ManifestService {
  final VoiceManifest manifest;
  
  // Indexed lookups (O(1))
  late final Map<String, CoreSpec> _coresById;
  late final Map<String, VoiceSpec> _voicesById;
  late final Map<String, List<VoiceSpec>> _voicesByEngine;
  
  ManifestService(this.manifest) {
    _coresById = {for (var c in manifest.cores) c.id: c};
    _voicesById = {for (var v in manifest.voices) v.id: v};
    _voicesByEngine = {};
    for (final v in manifest.voices) {
      _voicesByEngine.putIfAbsent(v.engineId, () => []).add(v);
    }
  }
  
  // Core queries
  CoreSpec? getCore(String coreId) => _coresById[coreId];
  List<CoreSpec> getCoresForEngine(String engineId) =>
    manifest.cores.where((c) => c.engineType == engineId).toList();
  
  // Voice queries
  VoiceSpec? getVoice(String voiceId) => _voicesById[voiceId];
  List<VoiceSpec> getVoicesForEngine(String engineId) => _voicesByEngine[engineId] ?? [];
  
  // Dependency queries
  List<CoreSpec> getRequiredCores(String voiceId) {
    final voice = getVoice(voiceId);
    if (voice == null) return [];
    return voice.coreRequirements.map((id) => _coresById[id]).whereType<CoreSpec>().toList();
  }
  
  // Size estimation
  int estimateVoiceDownloadSize(String voiceId, Set<String> alreadyDownloaded) {
    final cores = getRequiredCores(voiceId);
    return cores
      .where((c) => !alreadyDownloaded.contains(c.id))
      .fold(0, (sum, c) => sum + c.totalSize);
  }
}
```

**Also:** Add manifest loading from JSON file with error handling.

---

### Step 4: Create Download State Models

**File:** `packages/downloads/lib/src/models/download_state_models.dart` (new)

**Create typed state classes:**
```dart
/// State of a single core download
class CoreDownloadState {
  final String coreId;
  final String displayName;
  final DownloadStatus status;
  final double progress;
  final int sizeBytes;
  final String? error;
  
  bool get isReady => status == DownloadStatus.ready;
  bool get isDownloading => status == DownloadStatus.downloading || status == DownloadStatus.queued;
}

/// State of a voice (includes dependency info)
class VoiceDownloadState {
  final String voiceId;
  final String displayName;
  final String engineId;
  final DownloadStatus status;
  final double progress;
  final List<CoreDownloadState> requiredCores;
  final String? error;
  
  bool get allCoresReady => requiredCores.every((c) => c.isReady);
  bool get canUse => allCoresReady; // For Piper, voice IS the core; for Kokoro, need cores
  bool get anyDownloading => requiredCores.any((c) => c.isDownloading);
  
  /// Effective status considering dependencies
  DownloadStatus get effectiveStatus {
    if (!allCoresReady && status == DownloadStatus.ready) {
      return DownloadStatus.failed; // Core was deleted after voice marked ready
    }
    return status;
  }
}

/// Combined download state for UI
class GranularDownloadState {
  final Map<String, CoreDownloadState> cores;
  final Map<String, VoiceDownloadState> voices;
  final String? currentDownload;
  final String? error;
  
  List<VoiceDownloadState> get readyVoices => 
    voices.values.where((v) => v.canUse).toList();
  
  List<VoiceDownloadState> getVoicesForEngine(String engineId) =>
    voices.values.where((v) => v.engineId == engineId).toList();
  
  bool isCoreReady(String coreId) => cores[coreId]?.isReady ?? false;
  bool isVoiceReady(String voiceId) => voices[voiceId]?.canUse ?? false;
}
```

---

### Step 5: Create Download Queue

**File:** `packages/downloads/lib/src/download_queue.dart` (new)

**Create queue manager for controlled concurrent downloads:**
```dart
class DownloadQueue {
  final int maxConcurrent;
  final List<_QueuedDownload> _queue = [];
  final Set<String> _active = {};
  final _stateController = StreamController<DownloadQueueState>.broadcast();
  
  DownloadQueue({this.maxConcurrent = 1});
  
  /// Add download to queue
  Future<void> enqueue(String id, Future<void> Function() downloadFn) async {
    if (_active.contains(id) || _queue.any((q) => q.id == id)) return;
    
    final completer = Completer<void>();
    _queue.add(_QueuedDownload(id, downloadFn, completer));
    _notifyState();
    _processQueue();
    return completer.future;
  }
  
  /// Cancel a queued or active download
  void cancel(String id) {
    _queue.removeWhere((q) => q.id == id);
    // Note: Can't cancel active downloads without CancelToken support
    _notifyState();
  }
  
  /// Move download to front of queue
  void prioritize(String id) {
    final idx = _queue.indexWhere((q) => q.id == id);
    if (idx > 0) {
      final item = _queue.removeAt(idx);
      _queue.insert(0, item);
    }
  }
  
  Stream<DownloadQueueState> get stateStream => _stateController.stream;
  
  void _processQueue() async {
    while (_active.length < maxConcurrent && _queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      _active.add(item.id);
      _notifyState();
      
      try {
        await item.downloadFn();
        item.completer.complete();
      } catch (e) {
        item.completer.completeError(e);
      } finally {
        _active.remove(item.id);
        _notifyState();
        _processQueue(); // Process next
      }
    }
  }
  
  void _notifyState() {
    _stateController.add(DownloadQueueState(
      queued: _queue.map((q) => q.id).toList(),
      active: _active.toList(),
    ));
  }
  
  void dispose() => _stateController.close();
}

class _QueuedDownload {
  final String id;
  final Future<void> Function() downloadFn;
  final Completer<void> completer;
  _QueuedDownload(this.id, this.downloadFn, this.completer);
}

class DownloadQueueState {
  final List<String> queued;
  final List<String> active;
  DownloadQueueState({required this.queued, required this.active});
}
```

---

### Step 6: Update AtomicAssetManager for Multi-File Downloads

**File:** `packages/downloads/lib/src/atomic_asset_manager.dart`

**Add multi-file atomic download support:**
```dart
/// Download multiple files atomically (all succeed or all fail)
Future<void> downloadMultiFile({
  required String key,
  required List<FileSpec> files,
  void Function(double progress)? onProgress,
}) async {
  if (_activeDownloads.contains(key)) return;
  _activeDownloads.add(key);
  
  final targetDir = Directory('${baseDir.path}/$key');
  final tmpDir = Directory('${baseDir.path}/$key.tmp');
  
  try {
    _updateState(key, DownloadState(status: DownloadStatus.queued));
    
    // Clean up any previous attempt
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
    await tmpDir.create(recursive: true);
    
    // Download each file
    var totalDownloaded = 0;
    final totalSize = files.fold(0, (sum, f) => sum + f.sizeBytes);
    
    for (final file in files) {
      final destFile = File('${tmpDir.path}/${file.filename}');
      await _downloadFile(
        url: file.url,
        destFile: destFile,
        expectedSha256: file.sha256,
        onProgress: (downloaded, total) {
          final overallProgress = (totalDownloaded + downloaded) / totalSize;
          _updateState(key, DownloadState(
            status: DownloadStatus.downloading,
            progress: overallProgress,
            downloadedBytes: totalDownloaded + downloaded,
            totalBytes: totalSize,
          ));
          onProgress?.call(overallProgress);
        },
      );
      totalDownloaded += file.sizeBytes;
    }
    
    // Atomic install: move tmp to final
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await tmpDir.rename(targetDir.path);
    
    // Write manifest
    await _writeManifest(targetDir);
    
    _updateState(key, DownloadState.ready);
  } catch (e) {
    // Cleanup on failure
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
    _updateState(key, DownloadState(
      status: DownloadStatus.failed,
      error: e.toString(),
    ));
    rethrow;
  } finally {
    _activeDownloads.remove(key);
  }
}
```

---

### Step 7: Create GranularDownloadManager Provider

**File:** `lib/app/granular_download_manager.dart` (new)

**Create the main download manager:**
```dart
final granularDownloadManagerProvider = 
  AsyncNotifierProvider<GranularDownloadManager, GranularDownloadState>(() {
    return GranularDownloadManager();
  });

class GranularDownloadManager extends AsyncNotifier<GranularDownloadState> {
  late AtomicAssetManager _assetManager;
  late ManifestService _manifestService;
  late DownloadQueue _queue;
  
  @override
  FutureOr<GranularDownloadState> build() async {
    final paths = await ref.watch(appPathsProvider.future);
    _assetManager = AtomicAssetManager(baseDir: paths.voiceAssetsDir);
    _manifestService = await _loadManifest();
    _queue = DownloadQueue(maxConcurrent: 1);
    
    ref.onDispose(() {
      _assetManager.dispose();
      _queue.dispose();
    });
    
    // Scan installed assets and build initial state
    return await _scanInstalledState();
  }
  
  /// Download a voice (auto-downloads required cores first)
  Future<void> downloadVoice(String voiceId) async {
    final voice = _manifestService.getVoice(voiceId);
    if (voice == null) throw Exception('Unknown voice: $voiceId');
    
    // Get required cores
    final requiredCores = _manifestService.getRequiredCores(voiceId);
    
    // Download missing cores first
    for (final core in requiredCores) {
      if (!state.value!.isCoreReady(core.id)) {
        await downloadCore(core.id);
      }
    }
    
    // For Piper voices, the voice IS the core, so we're done
    // For Kokoro voices, they use speakerId with shared cores, so cores are enough
    // Update state to mark voice as ready
    _updateVoiceState(voiceId, DownloadStatus.ready);
  }
  
  /// Download a specific core
  Future<void> downloadCore(String coreId) async {
    final core = _manifestService.getCore(coreId);
    if (core == null) throw Exception('Unknown core: $coreId');
    
    await _queue.enqueue(coreId, () async {
      _updateCoreState(coreId, DownloadStatus.downloading, 0.0);
      
      if (core.files.isNotEmpty) {
        // Multi-file download
        await _assetManager.downloadMultiFile(
          key: _coreKey(core),
          files: core.files,
          onProgress: (p) => _updateCoreState(coreId, DownloadStatus.downloading, p),
        );
      } else {
        // Single file download
        await _assetManager.download(AssetSpec(
          key: _coreKey(core),
          downloadUrl: core.url!,
          sizeBytes: core.sizeBytes,
          checksum: core.sha256,
        ));
      }
      
      _updateCoreState(coreId, DownloadStatus.ready, 1.0);
    });
  }
  
  /// Delete a core (and mark dependent voices as unavailable)
  Future<void> deleteCore(String coreId) async {
    await _assetManager.delete(_coreKey(_manifestService.getCore(coreId)!));
    _updateCoreState(coreId, DownloadStatus.notDownloaded, 0.0);
    
    // Update all voices that depended on this core
    for (final voice in _manifestService.manifest.voices) {
      if (voice.coreRequirements.contains(coreId)) {
        _updateVoiceState(voice.id, DownloadStatus.notDownloaded);
      }
    }
  }
  
  /// Get file path for a core (for TTS engines to use)
  String? getCoreDirectory(String coreId) {
    if (!state.value!.isCoreReady(coreId)) return null;
    final core = _manifestService.getCore(coreId);
    if (core == null) return null;
    return '${_assetManager.baseDir.path}/${_coreKey(core)}';
  }
  
  // Helper to generate consistent file keys
  String _coreKey(CoreSpec core) => '${core.engineType}/${core.id}';
  
  // State update helpers
  void _updateCoreState(String coreId, DownloadStatus status, double progress) {
    final current = state.value!;
    final core = _manifestService.getCore(coreId)!;
    final newCores = Map<String, CoreDownloadState>.from(current.cores);
    newCores[coreId] = CoreDownloadState(
      coreId: coreId,
      displayName: core.displayName,
      status: status,
      progress: progress,
      sizeBytes: core.totalSize,
    );
    state = AsyncData(current.copyWith(cores: newCores));
  }
  
  void _updateVoiceState(String voiceId, DownloadStatus status) {
    // Build VoiceDownloadState with current core states
    final current = state.value!;
    final voice = _manifestService.getVoice(voiceId)!;
    final requiredCores = voice.coreRequirements
      .map((id) => current.cores[id])
      .whereType<CoreDownloadState>()
      .toList();
    
    final newVoices = Map<String, VoiceDownloadState>.from(current.voices);
    newVoices[voiceId] = VoiceDownloadState(
      voiceId: voiceId,
      displayName: voice.displayName,
      engineId: voice.engineId,
      status: status,
      progress: status == DownloadStatus.ready ? 1.0 : 0.0,
      requiredCores: requiredCores,
    );
    state = AsyncData(current.copyWith(voices: newVoices));
  }
}
```

---

### Step 8: Create Registry for Space Tracking

**File:** `packages/downloads/lib/src/download_registry.dart` (new)

**Create:**
```dart
/// Registry tracking all installed downloads
class DownloadRegistry {
  static const String _filename = '.registry';
  
  final Directory baseDir;
  List<RegistryEntry> entries = [];
  
  DownloadRegistry(this.baseDir);
  
  Future<void> load() async {
    final file = File('${baseDir.path}/$_filename');
    if (await file.exists()) {
      final json = jsonDecode(await file.readAsString());
      entries = (json['downloads'] as List)
        .map((e) => RegistryEntry.fromJson(e))
        .toList();
    }
  }
  
  Future<void> save() async {
    final file = File('${baseDir.path}/$_filename');
    await file.writeAsString(jsonEncode({
      'version': 1,
      'lastUpdated': DateTime.now().toIso8601String(),
      'downloads': entries.map((e) => e.toJson()).toList(),
      'totalSize': totalSize,
    }));
  }
  
  void addEntry(String id, String path, int size) {
    entries.removeWhere((e) => e.id == id);
    entries.add(RegistryEntry(
      id: id,
      path: path,
      size: size,
      status: 'ready',
      timestamp: DateTime.now(),
    ));
  }
  
  void removeEntry(String id) {
    entries.removeWhere((e) => e.id == id);
  }
  
  int get totalSize => entries.fold(0, (sum, e) => sum + e.size);
  
  bool isInstalled(String id) => entries.any((e) => e.id == id && e.status == 'ready');
}

class RegistryEntry {
  final String id;
  final String path;
  final int size;
  final String status;
  final DateTime timestamp;
  
  RegistryEntry({
    required this.id,
    required this.path,
    required this.size,
    required this.status,
    required this.timestamp,
  });
  
  factory RegistryEntry.fromJson(Map<String, dynamic> json) => RegistryEntry(
    id: json['id'],
    path: json['path'],
    size: json['size'],
    status: json['status'],
    timestamp: DateTime.parse(json['timestamp']),
  );
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'size': size,
    'status': status,
    'timestamp': timestamp.toIso8601String(),
  };
}
```

---

### Step 9: Create Error Types

**File:** `packages/downloads/lib/src/download_error.dart` (new)

**Create:**
```dart
enum DownloadErrorType {
  networkTimeout,
  networkUnreachable,
  noSpace,
  checksumMismatch,
  filePermissions,
  interrupted,
  manifestError,
  unknown;
  
  bool get isRetryable => !{filePermissions, manifestError}.contains(this);
  
  Duration getRetryDelay(int attempt) {
    if (!isRetryable) return Duration.zero;
    return Duration(seconds: min(32, pow(2, attempt).toInt()));
  }
  
  String get userMessage {
    switch (this) {
      case networkTimeout: return 'Network timed out. Check your connection.';
      case networkUnreachable: return 'Cannot reach server. Check your internet.';
      case noSpace: return 'Not enough storage space.';
      case checksumMismatch: return 'Download corrupted. Please try again.';
      case filePermissions: return 'Permission denied. Check app settings.';
      case interrupted: return 'Download was interrupted.';
      case manifestError: return 'Invalid configuration. Update the app.';
      case unknown: return 'An unexpected error occurred.';
    }
  }
}

class DownloadException implements Exception {
  final DownloadErrorType type;
  final String message;
  final int attemptNumber;
  
  DownloadException(this.type, this.message, {this.attemptNumber = 0});
  
  bool get shouldRetry => type.isRetryable && attemptNumber < 3;
  
  @override
  String toString() => 'DownloadException: ${type.userMessage} ($message)';
}
```

---

### Step 10: Write Unit Tests for Core Infrastructure

**File:** `packages/downloads/test/manifest_service_test.dart` (new)

**Create tests:**
```dart
void main() {
  group('ManifestService', () {
    late ManifestService service;
    
    setUp(() {
      service = ManifestService(_createTestManifest());
    });
    
    test('getCore returns correct core', () {
      final core = service.getCore('kokoro_model_v1');
      expect(core, isNotNull);
      expect(core!.displayName, contains('Kokoro'));
    });
    
    test('getVoice returns correct voice', () {
      final voice = service.getVoice('kokoro_af');
      expect(voice, isNotNull);
      expect(voice!.engineId, equals('kokoro'));
    });
    
    test('getRequiredCores returns all dependencies', () {
      final cores = service.getRequiredCores('kokoro_af');
      expect(cores, hasLength(3));
      expect(cores.map((c) => c.id), containsAll([
        'kokoro_model_v1',
        'kokoro_voices_v1', 
        'espeak_ng_data_v1',
      ]));
    });
    
    test('getVoicesForEngine groups correctly', () {
      final kokoroVoices = service.getVoicesForEngine('kokoro');
      final piperVoices = service.getVoicesForEngine('piper');
      
      expect(kokoroVoices.every((v) => v.engineId == 'kokoro'), true);
      expect(piperVoices.every((v) => v.engineId == 'piper'), true);
    });
    
    test('estimateVoiceDownloadSize excludes already downloaded', () {
      final fullSize = service.estimateVoiceDownloadSize('kokoro_af', {});
      final partialSize = service.estimateVoiceDownloadSize(
        'kokoro_af', 
        {'kokoro_model_v1'},
      );
      
      expect(partialSize, lessThan(fullSize));
    });
  });
  
  group('DownloadQueue', () {
    test('respects maxConcurrent limit', () async {
      final queue = DownloadQueue(maxConcurrent: 2);
      var concurrent = 0;
      var maxConcurrent = 0;
      
      final futures = List.generate(5, (i) {
        return queue.enqueue('dl_$i', () async {
          concurrent++;
          maxConcurrent = max(maxConcurrent, concurrent);
          await Future.delayed(Duration(milliseconds: 50));
          concurrent--;
        });
      });
      
      await Future.wait(futures);
      expect(maxConcurrent, lessThanOrEqualTo(2));
    });
  });
}
```

---

## Phase 2: UI Implementation (Steps 11-17)

### Step 11: Create DownloadManagerScreen

**File:** `lib/ui/screens/download_manager_screen.dart` (new)

**Create dedicated screen for managing downloads:**
```dart
class DownloadManagerScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(granularDownloadManagerProvider);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Downloads')),
      body: downloadState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (state) => ListView(
          children: [
            // Kokoro Section
            _EngineSection(
              engineId: 'kokoro',
              displayName: 'Kokoro (High Quality)',
              voices: state.getVoicesForEngine('kokoro'),
              cores: state.cores.values
                .where((c) => c.coreId.startsWith('kokoro'))
                .toList(),
            ),
            const Divider(),
            
            // Piper Section
            _EngineSection(
              engineId: 'piper',
              displayName: 'Piper (Fast)',
              voices: state.getVoicesForEngine('piper'),
              cores: state.cores.values
                .where((c) => c.coreId.startsWith('piper'))
                .toList(),
            ),
            const Divider(),
            
            // Supertonic Section
            _EngineSection(
              engineId: 'supertonic',
              displayName: 'Supertonic (Advanced)',
              voices: state.getVoicesForEngine('supertonic'),
              cores: state.cores.values
                .where((c) => c.coreId.startsWith('supertonic'))
                .toList(),
            ),
            
            // Space info
            const SizedBox(height: 24),
            _SpaceInfoCard(state: state),
          ],
        ),
      ),
    );
  }
}
```

---

### Step 12: Create CoreDownloadCard Widget

**File:** `lib/ui/widgets/core_download_card.dart` (new)

**Create:**
```dart
class CoreDownloadCard extends ConsumerWidget {
  final CoreDownloadState core;
  
  const CoreDownloadCard({required this.core});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: _buildStatusIcon(),
        title: Text(core.displayName),
        subtitle: _buildSubtitle(),
        trailing: _buildAction(context, ref),
      ),
    );
  }
  
  Widget _buildStatusIcon() {
    switch (core.status) {
      case DownloadStatus.ready:
        return const Icon(Icons.check_circle, color: Colors.green);
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: core.progress > 0 ? core.progress : null,
            strokeWidth: 2,
          ),
        );
      case DownloadStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
      default:
        return const Icon(Icons.cloud_download_outlined);
    }
  }
  
  Widget _buildSubtitle() {
    final sizeStr = _formatBytes(core.sizeBytes);
    switch (core.status) {
      case DownloadStatus.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${(core.progress * 100).toStringAsFixed(0)}% of $sizeStr'),
            LinearProgressIndicator(value: core.progress),
          ],
        );
      case DownloadStatus.ready:
        return Text('Installed • $sizeStr');
      case DownloadStatus.failed:
        return Text(core.error ?? 'Download failed', 
          style: const TextStyle(color: Colors.red));
      default:
        return Text(sizeStr);
    }
  }
  
  Widget? _buildAction(BuildContext context, WidgetRef ref) {
    switch (core.status) {
      case DownloadStatus.notDownloaded:
      case DownloadStatus.failed:
        return IconButton(
          icon: const Icon(Icons.download),
          onPressed: () => ref
            .read(granularDownloadManagerProvider.notifier)
            .downloadCore(core.coreId),
        );
      case DownloadStatus.ready:
        return IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _confirmDelete(context, ref),
        );
      default:
        return null; // Downloading - no action
    }
  }
  
  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Download?'),
        content: Text('Delete ${core.displayName}? You can re-download later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(granularDownloadManagerProvider.notifier)
                .deleteCore(core.coreId);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
```

---

### Step 13: Create VoiceDownloadCard Widget

**File:** `lib/ui/widgets/voice_download_card.dart` (new)

**Create:**
```dart
class VoiceDownloadCard extends ConsumerWidget {
  final VoiceDownloadState voice;
  
  const VoiceDownloadCard({required this.voice});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: _buildStatusIcon(),
        title: Text(voice.displayName),
        subtitle: _buildSubtitle(),
        trailing: _buildAction(context, ref),
      ),
    );
  }
  
  Widget _buildStatusIcon() {
    if (voice.canUse) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    if (voice.anyDownloading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return const Icon(Icons.mic_outlined);
  }
  
  Widget _buildSubtitle() {
    if (voice.canUse) {
      return const Text('Ready to use');
    }
    
    final missingCores = voice.requiredCores
      .where((c) => !c.isReady)
      .map((c) => c.displayName)
      .join(', ');
    
    if (voice.anyDownloading) {
      return const Text('Downloading...');
    }
    
    return Text('Requires: $missingCores');
  }
  
  Widget? _buildAction(BuildContext context, WidgetRef ref) {
    if (voice.canUse) {
      return const Icon(Icons.check, color: Colors.green);
    }
    
    if (voice.anyDownloading) {
      return null;
    }
    
    return FilledButton.tonal(
      onPressed: () => ref
        .read(granularDownloadManagerProvider.notifier)
        .downloadVoice(voice.voiceId),
      child: const Text('Download'),
    );
  }
}
```

---

### Step 14: Create Engine Section Widget

**File:** `lib/ui/widgets/engine_section.dart` (new)

**Create:**
```dart
class _EngineSection extends StatelessWidget {
  final String engineId;
  final String displayName;
  final List<VoiceDownloadState> voices;
  final List<CoreDownloadState> cores;
  
  const _EngineSection({
    required this.engineId,
    required this.displayName,
    required this.voices,
    required this.cores,
  });
  
  @override
  Widget build(BuildContext context) {
    final readyCount = voices.where((v) => v.canUse).length;
    
    return ExpansionTile(
      title: Text(displayName),
      subtitle: Text('$readyCount/${voices.length} voices ready'),
      leading: _buildEngineIcon(),
      children: [
        // Show cores for engines that have shared cores (Kokoro, Supertonic)
        if (engineId != 'piper' && cores.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Core Components', 
              style: Theme.of(context).textTheme.titleSmall),
          ),
          ...cores.map((c) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CoreDownloadCard(core: c),
          )),
          const Divider(),
        ],
        
        // Voices
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Voices', 
            style: Theme.of(context).textTheme.titleSmall),
        ),
        ...voices.map((v) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: VoiceDownloadCard(voice: v),
        )),
      ],
    );
  }
  
  Widget _buildEngineIcon() {
    final allReady = voices.every((v) => v.canUse);
    final anyDownloading = voices.any((v) => v.anyDownloading) ||
      cores.any((c) => c.isDownloading);
    
    if (allReady) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    if (anyDownloading) {
      return const SizedBox(
        width: 24, height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return const Icon(Icons.cloud_download_outlined);
  }
}
```

---

### Step 15: Update Voice Picker to Show Only Ready Voices

**File:** `lib/ui/widgets/voice_picker.dart` (update existing or create new)

**Changes:**
```dart
class VoicePicker extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(granularDownloadManagerProvider);
    final selectedVoice = ref.watch(selectedVoiceProvider);
    
    return downloadState.when(
      loading: () => const CircularProgressIndicator(),
      error: (e, _) => Text('Error: $e'),
      data: (state) {
        final readyVoices = state.readyVoices;
        
        if (readyVoices.isEmpty) {
          return _NoVoicesPlaceholder(
            onDownloadTap: () => context.push('/settings/downloads'),
          );
        }
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Voice selector
            DropdownButton<String>(
              value: readyVoices.any((v) => v.voiceId == selectedVoice)
                ? selectedVoice
                : readyVoices.first.voiceId,
              items: readyVoices.map((v) => DropdownMenuItem(
                value: v.voiceId,
                child: Text(v.displayName),
              )).toList(),
              onChanged: (id) {
                if (id != null) {
                  ref.read(selectedVoiceProvider.notifier).state = id;
                }
              },
            ),
            
            // Link to download more
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Download more voices'),
              onPressed: () => context.push('/settings/downloads'),
            ),
          ],
        );
      },
    );
  }
}

class _NoVoicesPlaceholder extends StatelessWidget {
  final VoidCallback onDownloadTap;
  
  const _NoVoicesPlaceholder({required this.onDownloadTap});
  
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_download_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('No voices downloaded', 
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Download a voice to get started',
            style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          FilledButton.icon(
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

---

### Step 16: Add Navigation to Download Manager

**File:** `lib/main.dart` (update routes)

**Add route:**
```dart
GoRoute(
  path: '/settings/downloads',
  builder: (context, state) => const DownloadManagerScreen(),
),
```

**File:** `lib/ui/screens/settings_screen.dart` (update)

**Add navigation tile:**
```dart
ListTile(
  leading: const Icon(Icons.cloud_download),
  title: const Text('Voice Downloads'),
  subtitle: Consumer(
    builder: (context, ref, _) {
      final state = ref.watch(granularDownloadManagerProvider);
      return state.when(
        loading: () => const Text('Loading...'),
        error: (_, __) => const Text('Error'),
        data: (s) {
          final ready = s.readyVoices.length;
          final total = s.voices.length;
          return Text('$ready/$total voices ready');
        },
      );
    },
  ),
  trailing: const Icon(Icons.chevron_right),
  onTap: () => context.push('/settings/downloads'),
),
```

---

### Step 17: Add Space Info Card

**File:** `lib/ui/widgets/space_info_card.dart` (new)

**Create:**
```dart
class _SpaceInfoCard extends StatelessWidget {
  final GranularDownloadState state;
  
  const _SpaceInfoCard({required this.state});
  
  @override
  Widget build(BuildContext context) {
    final totalSize = state.cores.values
      .where((c) => c.isReady)
      .fold(0, (sum, c) => sum + c.sizeBytes);
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Storage Used', 
              style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_formatBytes(totalSize),
              style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('${state.readyVoices.length} voices installed'),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
```

---

## Phase 3: Integration & Testing (Steps 18-22)

### Step 18: Integrate with TTS Engines

**File:** `lib/app/tts_providers.dart` (update)

**Update TTS engine providers to use granular download state:**
```dart
/// Provider that gives TTS engines access to downloaded model paths
final ttsModelPathsProvider = Provider<TtsModelPaths?>((ref) {
  final downloadState = ref.watch(granularDownloadManagerProvider);
  
  return downloadState.whenData((state) {
    return TtsModelPaths(
      kokoroModelPath: _getCorePathIfReady(state, 'kokoro_model_v1'),
      kokoroVoicesPath: _getCorePathIfReady(state, 'kokoro_voices_v1'),
      espeakDataPath: _getCorePathIfReady(state, 'espeak_ng_data_v1'),
      piperModels: _getPiperModelPaths(state),
      supertonicPaths: _getSupertonicPaths(state),
    );
  }).value;
});

String? _getCorePathIfReady(GranularDownloadState state, String coreId) {
  if (!state.isCoreReady(coreId)) return null;
  // Return path based on core id
  return '${baseDir}/${coreId}';
}
```

---

### Step 19: Delete Old Download Manager

**Files to remove or refactor:**
- `lib/ui/widgets/voice_download_manager.dart` - Remove old bulk download widget
- Update `lib/app/tts_providers.dart` - Remove old `TtsDownloadManager` class
- Update any screens using the old download widget

**Keep provider but mark deprecated:**
```dart
@Deprecated('Use granularDownloadManagerProvider instead')
final ttsDownloadManagerProvider = ...
```

---

### Step 20: Create Integration Tests

**File:** `test/integration/download_flow_test.dart` (new)

**Create:**
```dart
void main() {
  group('Download Flow Integration', () {
    testWidgets('Download voice flow works end-to-end', (tester) async {
      await tester.pumpWidget(ProviderScope(child: MyApp()));
      
      // Navigate to downloads
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voice Downloads'));
      await tester.pumpAndSettle();
      
      // Find a voice download button
      final downloadBtn = find.widgetWithText(FilledButton, 'Download');
      expect(downloadBtn, findsWidgets);
      
      // Tap download (will fail in test without network mock)
      // This is a UI test, not a real download test
    });
    
    testWidgets('Voice picker shows only ready voices', (tester) async {
      // Setup: Create mock state with some ready voices
      final container = ProviderContainer(overrides: [
        granularDownloadManagerProvider.overrideWith(() => MockDownloadManager()),
      ]);
      
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: VoicePicker()),
        ),
      );
      
      // Should show only ready voices
      expect(find.text('Kokoro - AF'), findsOneWidget); // Mock has this ready
      expect(find.text('Piper - Alan'), findsNothing); // Mock has this not ready
    });
  });
}
```

---

### Step 21: Error Handling UI

**File:** `lib/ui/widgets/download_error_banner.dart` (new)

**Create:**
```dart
class DownloadErrorBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(granularDownloadManagerProvider);
    
    return state.maybeWhen(
      data: (s) {
        if (s.error == null) return const SizedBox.shrink();
        
        return MaterialBanner(
          content: Text(s.error!),
          backgroundColor: Colors.red.shade100,
          leading: const Icon(Icons.error, color: Colors.red),
          actions: [
            TextButton(
              onPressed: () => ref
                .read(granularDownloadManagerProvider.notifier)
                .clearError(),
              child: const Text('Dismiss'),
            ),
            TextButton(
              onPressed: () => ref
                .read(granularDownloadManagerProvider.notifier)
                .retryFailed(),
              child: const Text('Retry'),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
```

---

### Step 22: Manual Testing Checklist

**Create:** `docs/features/downloads-improvements/TESTING_CHECKLIST.md`

```markdown
# Manual Testing Checklist

## Download Manager Screen
- [ ] Screen loads without errors
- [ ] All 3 engine sections display (Kokoro, Piper, Supertonic)
- [ ] Cores show correct status (not downloaded, downloading, ready)
- [ ] Voices show correct dependency status
- [ ] Space info card shows total installed size

## Download Flow
- [ ] Tap download on a Kokoro voice → downloads all 3 cores
- [ ] Progress shows for each core download
- [ ] Voice becomes "Ready to use" after cores complete
- [ ] Tap download on Piper voice → downloads only that voice model
- [ ] Cancel button works (if implemented)

## Delete Flow
- [ ] Tap delete on a core → confirmation dialog appears
- [ ] After delete, dependent voices show "Requires: ..."
- [ ] Delete removes files from disk (check with file manager)

## Voice Picker
- [ ] Only shows voices with all cores ready
- [ ] Shows "No voices downloaded" placeholder when empty
- [ ] "Download Voices" button navigates to download manager
- [ ] Selecting a voice updates the TTS engine

## Error Handling
- [ ] Turn off WiFi mid-download → shows error
- [ ] Error banner shows with retry option
- [ ] Retry resumes from failure point (if supported)

## Performance
- [ ] Download manager screen loads in < 2 seconds
- [ ] No UI jank during downloads
- [ ] App doesn't freeze when checking download status
```

---

## Phase 4: Polish & Release (Steps 23-25)

### Step 23: Performance Optimization

**Optimizations to apply:**
1. Lazy load manifest (don't parse on app start)
2. Debounce state updates during downloads (every 100ms, not every byte)
3. Use isolate for checksum verification of large files
4. Cache registry in memory after first load

---

### Step 24: Documentation

**Update these files:**
- `docs/features/downloads-improvements/DOWNLOADS_ORGANIZATION.md` - Update with new structure
- `README.md` - Add section about voice downloads
- Code comments in key files

---

### Step 25: Final Cleanup

**Tasks:**
1. Remove deprecated code (`@Deprecated` items)
2. Remove old test files for deleted code
3. Run `flutter analyze` and fix all warnings
4. Run `flutter test` and ensure all pass
5. Test on real Android device
6. Create release notes

---

## File Summary

### New Files:
| File | Description |
|------|-------------|
| `packages/downloads/lib/src/models/manifest_models.dart` | Domain models |
| `packages/downloads/lib/src/manifest_service.dart` | Manifest parsing & queries |
| `packages/downloads/lib/src/models/download_state_models.dart` | Typed state classes |
| `packages/downloads/lib/src/download_queue.dart` | Queue management |
| `packages/downloads/lib/src/download_registry.dart` | Space tracking |
| `packages/downloads/lib/src/download_error.dart` | Error types |
| `lib/app/granular_download_manager.dart` | Main provider |
| `lib/ui/screens/download_manager_screen.dart` | Downloads UI |
| `lib/ui/widgets/core_download_card.dart` | Core card |
| `lib/ui/widgets/voice_download_card.dart` | Voice card |
| `lib/ui/widgets/engine_section.dart` | Engine grouping |
| `lib/ui/widgets/space_info_card.dart` | Storage info |
| `lib/ui/widgets/download_error_banner.dart` | Error display |

### Modified Files:
| File | Changes |
|------|---------|
| `packages/downloads/lib/manifests/voices_manifest.json` | Add types, fix structure |
| `packages/downloads/lib/src/atomic_asset_manager.dart` | Multi-file support |
| `lib/ui/widgets/voice_picker.dart` | Filter to ready voices |
| `lib/ui/screens/settings_screen.dart` | Add downloads navigation |
| `lib/main.dart` | Add route |
| `lib/app/tts_providers.dart` | Use new download state |

### Deleted Files:
| File | Reason |
|------|--------|
| `lib/ui/widgets/voice_download_manager.dart` | Replaced by new system |

---

## Timeline

| Phase | Duration | Steps |
|-------|----------|-------|
| Phase 1: Core Infrastructure | 2.5 weeks | 1-10 |
| Phase 2: UI Implementation | 3 weeks | 11-17 |
| Phase 3: Integration & Testing | 2.5 weeks | 18-22 |
| Phase 4: Polish & Release | 1 week | 23-25 |
| **Total** | **9 weeks** | **25 steps** |

---

## Success Criteria

- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Manual testing checklist complete
- [ ] No `flutter analyze` warnings
- [ ] Download manager loads in < 2 seconds
- [ ] Downloads work on real Android device
- [ ] Voice picker shows only ready voices
- [ ] Error handling works for network failures
