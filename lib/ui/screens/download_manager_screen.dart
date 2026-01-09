import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:downloads/downloads.dart';

import '../../app/granular_download_manager.dart';
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
                child: _StatCard(
                  label: 'Storage Used',
                  value: _formatBytes(state.totalInstalledSize),
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
                Text(
                  _formatBytes(core.sizeBytes),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _buildAction(ref, colors),
        ],
      ),
    );
  }

  Widget _buildAction(WidgetRef ref, AppThemeColors colors) {
    switch (core.status) {
      case DownloadStatus.notDownloaded:
      case DownloadStatus.failed:
        return _DownloadButton(
          onPressed: () => ref
              .read(granularDownloadManagerProvider.notifier)
              .downloadCore(core.coreId),
          colors: colors,
        );
      case DownloadStatus.downloading:
      case DownloadStatus.extracting:
        return _ProgressIndicator(
          progress: core.progress,
          colors: colors,
        );
      case DownloadStatus.ready:
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check, size: 16, color: Colors.green.shade600),
        );
      default:
        return const SizedBox.shrink();
    }
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
    final currentlyPlaying = ref.watch(voicePreviewProvider);
    final isPlayingThis = currentlyPlaying == voice.voiceId;

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
            child: Text(
              voice.displayName,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isLocked ? colors.textTertiary : colors.text,
              ),
            ),
          ),
          
          // Preview button
          IconButton(
            icon: Icon(
              isPlayingThis ? Icons.stop : Icons.play_circle_outline,
              color: isPlayingThis ? colors.primary : colors.textSecondary,
              size: 22,
            ),
            onPressed: () {
              if (isPlayingThis) {
                ref.read(voicePreviewProvider.notifier).stop();
              } else {
                ref.read(voicePreviewProvider.notifier).playPreview(voice.voiceId);
              }
            },
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 8),
          
          // Download/status
          _buildAction(ref, isReady, isDownloading, colors),
        ],
      ),
    );
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

    if (isDownloading) {
      return _ProgressIndicator(
        progress: voice.getDownloadProgress(cores),
        colors: colors,
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

class _ProgressIndicator extends StatelessWidget {
  const _ProgressIndicator({
    required this.progress,
    required this.colors,
  });

  final double progress;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
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
