# Downloads Improvements Implementation Plan

## Overview

This document outlines the implementation plan for improving the downloads system to support individual core and voice downloads, replacing the current bulk engine download approach.

## Current System Limitations

- **Bulk Downloads**: Entire TTS engines are downloaded as packages (all voices or none)
- **No Granularity**: Cannot choose specific voices to save space
- **No Selective Installation**: All voices for an engine are downloaded together
- **Poor UX**: Users cannot preview or selectively install voices

## Proposed System Architecture

### Core Principles

1. **Hierarchical Downloads**: Cores first, then individual voices
2. **Dependency Management**: Voices require their core to be downloaded
3. **Selective Installation**: Users choose exactly what they want
4. **Space Efficiency**: Only download what you need

### New Download Flow

```
User selects voice in settings
    ↓
System checks if core is downloaded
    ↓ (if not)
Download core → Install core → Download voice → Install voice
    ↓ (if yes)
Download voice → Install voice
```

## Implementation Components

### 1. Enhanced Download Manager UI

#### New Settings Screen Structure

```
Settings
├── Voice Selection (existing)
├── Voice Downloads (enhanced)
│   ├── Core Downloads
│   │   ├── Kokoro Core (94MB)
│   │   ├── Piper Core (varies)
│   │   └── Supertonic Core (200MB)
│   └── Voice Downloads
│       ├── Kokoro Voices (requires Kokoro Core)
│       │   ├── AF Bella
│       │   ├── AF Nicole
│       │   └── AM Adam
│       ├── Piper Voices (requires Piper Core)
│       │   ├── Alan (British)
│       │   └── Lessac (American)
│       └── Supertonic Voices (requires Supertonic Core)
│           ├── Male 1
│           └── Female 1
```

#### UI Components

- **DownloadManagerScreen**: New dedicated screen for downloads
- **CoreDownloadCard**: Shows core status and download button
- **VoiceDownloadCard**: Shows voice status, dependencies, and download button
- **DependencyIndicator**: Visual indicator showing core requirements
- **ProgressOverlay**: Real-time download progress with cancel option
- **VoicePicker (updated)**: Filter to show only downloaded voices, add download navigation

### 2. State Management Updates

#### Enhanced TtsDownloadState

```dart
class TtsDownloadState {
  // Existing engine-level states (for backwards compatibility)
  final DownloadStatus kokoroState;
  final DownloadStatus piperState;
  final DownloadStatus supertonicState;

  // New granular states
  final Map<String, DownloadStatus> coreStates;      // coreId -> status
  final Map<String, DownloadStatus> voiceStates;     // voiceId -> status
  final Map<String, double> downloadProgress;        // itemId -> progress
  final String? currentDownload;
  final String? error;

  // Computed properties
  bool isCoreReady(String coreId) => coreStates[coreId] == DownloadStatus.ready;
  bool isVoiceReady(String voiceId) => voiceStates[voiceId] == DownloadStatus.ready;
  bool canDownloadVoice(String voiceId); // checks core dependency
}
```

#### New Download Manager

```dart
class GranularDownloadManager extends AsyncNotifier<TtsDownloadState> {
  final AtomicAssetManager _assetManager;
  final VoiceManifestV2 _manifest;

  // Core download methods
  Future<void> downloadCore(String coreId);
  Future<void> deleteCore(String coreId);

  // Voice download methods
  Future<void> downloadVoice(String voiceId);
  Future<void> deleteVoice(String voiceId);

  // Utility methods
  List<String> getAvailableCores();
  List<String> getAvailableVoicesForCore(String coreId);
  bool isCoreRequiredForVoice(String voiceId);
}
```

### 3. Download Logic Implementation

#### Manifest Integration

```dart
class VoiceManifestService {
  final VoiceManifestV2 manifest;

  // Get all cores
  List<CoreRequirement> getAllCores() => manifest.cores;

  // Get voices for a specific core
  List<VoiceSpec> getVoicesForCore(String coreId) {
    return manifest.voices.where((voice) =>
      voice.coreRequirements.contains(coreId)
    ).toList();
  }

  // Check if voice can be downloaded
  bool canDownloadVoice(String voiceId) {
    final voice = manifest.getVoice(voiceId);
    if (voice == null) return false;

    return voice.coreRequirements.every((coreId) =>
      isCoreDownloaded(coreId)
    );
  }
}
```

#### Asset Download Updates

```dart
class AtomicAssetManager {
  // Existing methods...

  // New methods for granular downloads
  Future<void> downloadCore(CoreRequirement core);
  Future<void> downloadVoice(VoiceSpec voice);

  // Enhanced state tracking
  Stream<DownloadState> watchCoreState(String coreId);
  Stream<DownloadState> watchVoiceState(String voiceId);
}
```

### 4. File System Organization

#### Updated Directory Structure

```
<app_cache>/voice_assets/
├── cores/
│   ├── kokoro_model_v1/
│   │   ├── model.onnx
│   │   └── .manifest
│   ├── piper_alan_gb_v1/
│   │   ├── model.onnx
│   │   ├── model.onnx.json
│   │   └── .manifest
│   └── supertonic_core_v1/
│       ├── autoencoder.onnx
│       ├── text_encoder.onnx
│       ├── duration_predictor.onnx
│       └── .manifest
└── voices/
    ├── kokoro_af_bella/
    │   ├── voice_style.bin (if separate)
    │   └── .manifest
    └── piper_en_GB_alan_medium/
        ├── model.onnx
        ├── model.onnx.json
        └── .manifest
```

### 5. User Experience Flow

#### Voice Selection Integration

1. **Voice Picker Filtering**:
   - Only show voices that are downloaded and ready to use
   - Filter out unavailable voices from the selection list
   - Display clear messaging when no voices are available for an engine
   - Add "Download More Voices" option linking to download manager

2. **Download Navigation**:
   ```
   No Kokoro voices available.
   [Download Kokoro Voices] → Navigate to Download Manager
   ```

3. **Background Downloads**:
   - Downloads run in background
   - Progress shown in notification area
   - Cancel option available

### 6. Error Handling & Recovery

#### Download Failures

- **Network Issues**: Automatic retry with exponential backoff
- **Storage Issues**: Clear error messages with space requirements
- **Corruption**: Automatic cleanup and re-download
- **Dependency Issues**: Clear messaging about core requirements

#### Recovery Options

- **Resume Downloads**: Continue interrupted downloads
- **Retry Failed**: One-click retry for failed downloads
- **Cleanup**: Remove corrupted downloads automatically

### 7. Migration Strategy

#### Backwards Compatibility

1. **Existing Installations**:
   - Detect bulk downloads and mark as "legacy"
   - Allow migration to granular system
   - Preserve existing functionality

2. **Gradual Rollout**:
   - Keep bulk download option as fallback
   - Allow users to opt into new system
   - Maintain old UI until migration complete

### 8. Testing Strategy

#### Unit Tests

- **Download Logic**: Test individual core/voice downloads
- **State Management**: Test granular state updates
- **Dependency Resolution**: Test core requirement checking

#### Integration Tests

- **End-to-End Downloads**: Test complete download flows
- **UI Integration**: Test download manager interface
- **Error Scenarios**: Test failure recovery

#### Manual Testing

- **Real Device Testing**: Test on actual Android devices
- **Network Conditions**: Test with poor connectivity
- **Storage Scenarios**: Test with limited storage

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1-2)
- [ ] Update TtsDownloadState for granular tracking
- [ ] Create GranularDownloadManager
- [ ] Update AtomicAssetManager for individual downloads
- [ ] Parse manifest for cores and voices

### Phase 2: UI Implementation (Week 3-4)
- [ ] Create DownloadManagerScreen
- [ ] Implement CoreDownloadCard and VoiceDownloadCard
- [ ] Add dependency indicators
- [ ] Update settings navigation

### Phase 3: Integration & Testing (Week 5-6)
- [ ] Integrate with voice selection (filter picker to show only downloaded voices)
- [ ] Add download navigation from voice picker
- [ ] Implement error handling
- [ ] Comprehensive testing

### Phase 4: Migration & Polish (Week 7-8)
- [ ] Backwards compatibility
- [ ] Performance optimization
- [ ] User experience refinements
- [ ] Documentation updates

## Success Metrics

- **User Experience**: Reduced download times for individual voices
- **Storage Efficiency**: 50%+ reduction in storage for single voice usage
- **Error Recovery**: <5% download failure rate
- **Performance**: <2 second UI response times

## Risks & Mitigations

- **Complexity**: Mitigated by phased implementation
- **Backwards Compatibility**: Comprehensive migration strategy
- **Storage Fragmentation**: Automatic cleanup and optimization
- **Network Issues**: Robust retry and resume logic

This implementation will provide users with fine-grained control over their voice downloads while maintaining system reliability and performance.</content>
<parameter name="filePath">/home/william/Projects/audiobook_flutter_v2/docs/features/downloads-improvements/IMPLEMENTATION_PLAN.md