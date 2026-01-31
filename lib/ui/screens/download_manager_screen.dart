import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:downloads/downloads.dart';

import '../../app/granular_download_manager.dart';
import '../../app/settings_controller.dart';
import '../../app/voice_preview_service.dart';
import '../theme/app_colors.dart';

/// Screen for managing voice downloads with granular control.
class DownloadManagerScreen extends ConsumerWidget {
  const DownloadManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final downloadState = ref.watch(granularDownloadManagerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: downloadState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (state) => _DownloadContent(state: state),
        ),
      ),
    );
  }
}

class _DownloadContent extends ConsumerStatefulWidget {
  const _DownloadContent({required this.state});
  final GranularDownloadState state;

  @override
  ConsumerState<_DownloadContent> createState() => _DownloadContentState();
}

class _DownloadContentState extends ConsumerState<_DownloadContent> {
  final Set<String> _expandedEngines = {};

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = widget.state;

    // Calculate stats
    final totalVoices = state.voices.length;
    final readyVoices = state.voices.values
        .where((v) => v.allCoresReady(state.cores))
        .length;
    
    // Calculate per-engine storage
    final engineSizes = <String, int>{};
    for (final core in state.cores.values) {
      if (core.isReady) {
        engineSizes[core.engineType] = 
            (engineSizes[core.engineType] ?? 0) + core.sizeBytes;
      }
    }

    return Column(
      children: [
        // Header
        _buildHeader(context, colors),

        // Stats Row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: _StorageStatCard(
                  totalBytes: state.totalInstalledSize,
                  engineSizes: engineSizes,
                  colors: colors,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Voices Ready',
                  value: '$readyVoices / $totalVoices',
                  colors: colors,
                ),
              ),
            ],
          ),
        ),
        
        // WiFi-only toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: _WifiOnlyToggle(colors: colors),
        ),

        // Engine Sections
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              // Piper section (fastest)
              _EngineSection(
                engineId: 'piper',
                displayName: 'Piper',
                description: 'Fast and lightweight',
                state: state,
                isExpanded: _expandedEngines.contains('piper'),
                onToggle: () => _toggleEngine('piper'),
              ),
              const SizedBox(height: 12),

              // Supertonic section
              _EngineSection(
                engineId: 'supertonic',
                displayName: 'Supertonic',
                description: 'Advanced voice cloning',
                state: state,
                isExpanded: _expandedEngines.contains('supertonic'),
                onToggle: () => _toggleEngine('supertonic'),
              ),
              const SizedBox(height: 12),

              // Kokoro section (at bottom with warning)
              _EngineSection(
                engineId: 'kokoro',
                displayName: 'Kokoro',
                description: 'High-quality neural voice synthesis',
                state: state,
                isExpanded: _expandedEngines.contains('kokoro'),
                onToggle: () => _toggleEngine('kokoro'),
                warningText: 'Requires high-end device',
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _toggleEngine(String engineId) {
    setState(() {
      if (_expandedEngines.contains(engineId)) {
        _expandedEngines.remove(engineId);
      } else {
        _expandedEngines.add(engineId);
      }
    });
  }

  Widget _buildHeader(BuildContext context, AppThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.arrow_back, color: colors.text, size: 20),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Voice Downloads',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 36), // Balance the back button
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Storage stat card with expandable per-engine breakdown.
class _StorageStatCard extends StatefulWidget {
  const _StorageStatCard({
    required this.totalBytes,
    required this.engineSizes,
    required this.colors,
  });

  final int totalBytes;
  final Map<String, int> engineSizes;
  final AppThemeColors colors;

  @override
  State<_StorageStatCard> createState() => _StorageStatCardState();
}

class _StorageStatCardState extends State<_StorageStatCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.colors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Storage Used',
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.colors.textSecondary,
                  ),
                ),
                if (widget.engineSizes.isNotEmpty)
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: widget.colors.textSecondary,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatBytes(widget.totalBytes),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: widget.colors.text,
              ),
            ),
            if (_expanded && widget.engineSizes.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...widget.engineSizes.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _capitalizeFirst(e.key),
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.colors.textSecondary,
                      ),
                    ),
                    Text(
                      _formatBytes(e.value),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: widget.colors.text,
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }
  
  String _capitalizeFirst(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

class _EngineSection extends ConsumerWidget {
  const _EngineSection({
    required this.engineId,
    required this.displayName,
    required this.description,
    required this.state,
    required this.isExpanded,
    required this.onToggle,
    this.warningText,
  });

  final String engineId;
  final String displayName;
  final String description;
  final GranularDownloadState state;
  final bool isExpanded;
  final VoidCallback onToggle;
  final String? warningText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final voices = state.getVoicesForEngine(engineId);
    final cores = state.getCoresForEngine(engineId);
    final readyCount = voices.where((v) => v.allCoresReady(state.cores)).length;

    // Piper voices are self-contained (no separate shared core)
    // So we hide the core section and never show coreRequired banner for Piper
    final isPiper = engineId == 'piper';
    final showCores = cores.isNotEmpty && !isPiper;
    final coreRequired = showCores && !cores.every((c) => c.isReady);

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header (clickable)
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_outlined,
                    color: colors.textSecondary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colors.text,
                              ),
                            ),
                            if (warningText != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      size: 12,
                                      color: Colors.amber.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      warningText!,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$readyCount/${voices.length} voices ready • $description',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (isExpanded) ...[
            Divider(height: 1, color: colors.border),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Core Components section (hidden for Piper since voices are self-contained)
                  if (showCores) ...[
                    Text(
                      'CORE COMPONENTS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...cores.map((core) => _CoreTile(core: core)),
                    const SizedBox(height: 20),
                  ],

                  // Core Required Banner
                  if (coreRequired) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: Colors.amber.shade600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                                children: [
                                  const TextSpan(text: 'Install '),
                                  TextSpan(
                                    text: '$displayName TTS Core',
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const TextSpan(text: ' to download voices'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Voices section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'VOICES',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (!coreRequired)
                        GestureDetector(
                          onTap: () => ref
                              .read(granularDownloadManagerProvider.notifier)
                              .downloadAllForEngine(engineId),
                          child: Text(
                            'Download All',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...voices.map(
                    (voice) => _VoiceTile(
                      voice: voice,
                      cores: state.cores,
                      isLocked: coreRequired,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoreTile extends ConsumerWidget {
  const _CoreTile({required this.core});
  final CoreDownloadState core;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            Icons.cloud_outlined,
            size: 20,
            color: core.isReady ? colors.primary : colors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  core.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  core.statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: _getStatusColor(colors),
                  ),
                ),
              ],
            ),
          ),
          _buildAction(ref, colors, context),
        ],
      ),
    );
  }
  
  Color _getStatusColor(AppThemeColors colors) {
    switch (core.status) {
      case DownloadStatus.failed:
        return Colors.red.shade600;
      case DownloadStatus.downloading:
      case DownloadStatus.extracting:
        return colors.primary;
      default:
        return colors.textSecondary;
    }
  }

  Widget _buildAction(WidgetRef ref, AppThemeColors colors, BuildContext context) {
    switch (core.status) {
      case DownloadStatus.notDownloaded:
        return _DownloadButton(
          onPressed: () => ref
              .read(granularDownloadManagerProvider.notifier)
              .downloadCore(core.coreId),
          colors: colors,
        );
      case DownloadStatus.failed:
        return _RetryButton(
          onPressed: () => ref
              .read(granularDownloadManagerProvider.notifier)
              .downloadCore(core.coreId),
          colors: colors,
        );
      case DownloadStatus.queued:
        return _QueuedIndicator(colors: colors);
      case DownloadStatus.downloading:
        return _DownloadProgressIndicator(
          progress: core.progress,
          colors: colors,
          onCancel: () => ref
              .read(granularDownloadManagerProvider.notifier)
              .cancelDownload(core.coreId),
        );
      case DownloadStatus.extracting:
        return _ExtractingIndicator(colors: colors);
      case DownloadStatus.ready:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check, size: 16, color: Colors.green.shade600),
            ),
            const SizedBox(width: 8),
            _DeleteButton(
              onPressed: () => _confirmDelete(context, ref),
              colors: colors,
            ),
          ],
        );
    }
  }
  
  void _confirmDelete(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('Delete ${core.displayName}?', style: TextStyle(color: colors.text)),
        content: Text(
          'This will remove the downloaded model (${_formatBytes(core.sizeBytes)}). '
          'Voices using this engine will no longer work until re-downloaded.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(granularDownloadManagerProvider.notifier).deleteCore(core.coreId);
            },
            child: Text('Delete', style: TextStyle(color: Colors.red.shade600)),
          ),
        ],
      ),
    );
  }
}

class _VoiceTile extends ConsumerWidget {
  const _VoiceTile({
    required this.voice,
    required this.cores,
    required this.isLocked,
  });

  final VoiceDownloadState voice;
  final Map<String, CoreDownloadState> cores;
  final bool isLocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final isReady = voice.allCoresReady(cores);
    final isDownloading = voice.anyDownloading(cores);
    final previewState = ref.watch(voicePreviewProvider);
    final isPlayingThis = previewState.isPlayingVoice(voice.voiceId);
    final isLoadingThis = previewState.isLoadingVoice(voice.voiceId);
    final hasError = previewState.isError && previewState.voiceId == voice.voiceId;
    
    // Get the status text from the first required core
    final statusText = _getStatusText(isReady, isDownloading);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            Icons.mic_outlined,
            size: 20,
            color: isReady
                ? colors.primary
                : isLocked
                    ? colors.textTertiary
                    : colors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  voice.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isLocked ? colors.textTertiary : colors.text,
                  ),
                ),
                if (statusText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: _getStatusColor(colors, isReady, isDownloading),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Preview button
          _PreviewButton(
            voiceId: voice.voiceId,
            isPlaying: isPlayingThis,
            isLoading: isLoadingThis,
            hasError: hasError,
            colors: colors,
          ),
          const SizedBox(width: 8),
          
          // Download/status
          _buildAction(ref, isReady, isDownloading, colors),
        ],
      ),
    );
  }
  
  String? _getStatusText(bool isReady, bool isDownloading) {
    if (isReady) return null; // Don't show "Ready" text for voices
    
    // Find the first non-ready required core and show its status
    for (final coreId in voice.requiredCoreIds) {
      final core = cores[coreId];
      if (core != null && !core.isReady) {
        return core.statusText;
      }
    }
    return null;
  }
  
  Color _getStatusColor(AppThemeColors colors, bool isReady, bool isDownloading) {
    if (isReady) return colors.textSecondary;
    
    // Check if any core is extracting
    for (final coreId in voice.requiredCoreIds) {
      final core = cores[coreId];
      if (core != null) {
        if (core.isFailed) return Colors.red.shade600;
        if (core.isExtracting || core.isDownloading) return colors.primary;
      }
    }
    return colors.textSecondary;
  }

  Widget _buildAction(
    WidgetRef ref,
    bool isReady,
    bool isDownloading,
    AppThemeColors colors,
  ) {
    if (isReady) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check, size: 16, color: Colors.green.shade600),
      );
    }

    // Check if any core is extracting (show spinner instead of progress bar)
    final isExtracting = voice.requiredCoreIds.any((id) => 
      cores[id]?.isExtracting ?? false);
    
    if (isExtracting) {
      return _ExtractingIndicator(colors: colors);
    }

    if (isDownloading) {
      return _DownloadProgressIndicator(
        progress: voice.getDownloadProgress(cores),
        colors: colors,
        onCancel: null, // Voice download cancel would need to cancel all cores
      );
    }

    if (isLocked) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.textTertiary.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.lock, size: 16, color: colors.textTertiary),
      );
    }

    return _DownloadButton(
      onPressed: () => ref
          .read(granularDownloadManagerProvider.notifier)
          .downloadVoice(voice.voiceId),
      colors: colors,
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({
    required this.onPressed,
    required this.colors,
  });

  final VoidCallback onPressed;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.download, size: 16, color: Colors.white),
      ),
    );
  }
}

/// Indicator for downloading state with cancel option.
class _DownloadProgressIndicator extends StatelessWidget {
  const _DownloadProgressIndicator({
    required this.progress,
    required this.colors,
    this.onCancel,
  });

  final double progress;
  final AppThemeColors colors;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCancel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 50,
                height: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: colors.border,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (onCancel != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.close, size: 16, color: colors.textSecondary),
          ],
        ],
      ),
    );
  }
}

/// Spinner indicator for extracting/unpacking phase.
class _ExtractingIndicator extends StatelessWidget {
  const _ExtractingIndicator({required this.colors});

  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: colors.primary,
      ),
    );
  }
}

/// Indicator for queued state.
class _QueuedIndicator extends StatelessWidget {
  const _QueuedIndicator({required this.colors});

  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.textSecondary.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.schedule, size: 16, color: colors.textSecondary),
    );
  }
}

/// Retry button for failed downloads.
class _RetryButton extends StatelessWidget {
  const _RetryButton({
    required this.onPressed,
    required this.colors,
  });

  final VoidCallback onPressed;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.refresh, size: 16, color: Colors.red.shade600),
      ),
    );
  }
}

/// Preview button with loading, playing, and error states.
class _PreviewButton extends ConsumerWidget {
  const _PreviewButton({
    required this.voiceId,
    required this.isPlaying,
    required this.isLoading,
    required this.hasError,
    required this.colors,
  });

  final String voiceId;
  final bool isPlaying;
  final bool isLoading;
  final bool hasError;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isLoading) {
      return SizedBox(
        width: 32,
        height: 32,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.primary,
          ),
        ),
      );
    }
    
    if (hasError) {
      return SizedBox(
        width: 32,
        height: 32,
        child: Icon(
          Icons.error_outline,
          color: Colors.red.shade400,
          size: 22,
        ),
      );
    }
    
    return IconButton(
      icon: Icon(
        isPlaying ? Icons.stop : Icons.play_circle_outline,
        color: isPlaying ? colors.primary : colors.textSecondary,
        size: 22,
      ),
      onPressed: () {
        if (isPlaying) {
          ref.read(voicePreviewProvider.notifier).stop();
        } else {
          ref.read(voicePreviewProvider.notifier).playPreview(voiceId);
        }
      },
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}

/// Delete button for ready cores.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({
    required this.onPressed,
    required this.colors,
  });

  final VoidCallback onPressed;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: colors.textSecondary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.delete_outline, size: 16, color: colors.textSecondary),
      ),
    );
  }
}

/// WiFi-only download toggle.
class _WifiOnlyToggle extends ConsumerWidget {
  const _WifiOnlyToggle({required this.colors});

  final AppThemeColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wifiOnly = ref.watch(settingsProvider.select((s) => s.wifiOnlyDownloads));
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi, size: 20, color: colors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WiFi only',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.text,
                  ),
                ),
                Text(
                  'Only download voice models on WiFi',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: wifiOnly,
            onChanged: (v) => ref.read(settingsProvider.notifier).setWifiOnlyDownloads(v),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
