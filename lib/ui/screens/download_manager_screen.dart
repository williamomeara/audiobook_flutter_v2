import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:downloads/downloads.dart';

import '../../app/granular_download_manager.dart';
import '../theme/app_colors.dart';

/// Screen for managing voice downloads with granular control.
class DownloadManagerScreen extends ConsumerWidget {
  const DownloadManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final downloadState = ref.watch(granularDownloadManagerProvider);

    return Scaffold(
      backgroundColor: colors.backgroundSecondary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _Header(colors: colors),

            // Content
            Expanded(
              child: downloadState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorView(error: e.toString()),
                data: (state) => _DownloadContent(state: state),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.colors});
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.headerBackground,
        border: Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => context.pop(),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.backgroundSecondary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.chevron_left, color: colors.text),
            ),
          ),
          const Spacer(),
          Text(
            'Voice Downloads',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.danger),
            const SizedBox(height: 16),
            Text(
              'Failed to load downloads',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadContent extends ConsumerWidget {
  const _DownloadContent({required this.state});
  final GranularDownloadState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary card
        _SummaryCard(state: state),
        const SizedBox(height: 20),

        // Kokoro section
        _EngineSection(
          engineId: 'kokoro',
          displayName: 'Kokoro',
          description: 'High-quality neural voice synthesis',
          state: state,
        ),
        const SizedBox(height: 16),

        // Piper section
        _EngineSection(
          engineId: 'piper',
          displayName: 'Piper',
          description: 'Fast and lightweight',
          state: state,
        ),
        const SizedBox(height: 16),

        // Supertonic section
        _EngineSection(
          engineId: 'supertonic',
          displayName: 'Supertonic',
          description: 'Advanced voice cloning',
          state: state,
        ),
        const SizedBox(height: 24),

        // Delete all button
        if (state.readyVoiceCount > 0)
          _DeleteAllButton(state: state),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});
  final GranularDownloadState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final totalSize = state.totalInstalledSize;
    final readyCount = state.readyVoiceCount;
    final totalCount = state.totalVoiceCount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Storage Used',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatBytes(totalSize),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 50,
            color: colors.border,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Voices Ready',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$readyCount / $totalCount',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
              ],
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
  });

  final String engineId;
  final String displayName;
  final String description;
  final GranularDownloadState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final voices = state.getVoicesForEngine(engineId);
    final cores = state.getCoresForEngine(engineId);

    final readyCount = voices.where((v) => v.allCoresReady(state.cores)).length;
    final anyDownloading = cores.any((c) => c.isDownloading);

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: _buildStatusIcon(anyDownloading, readyCount == voices.length, colors),
          title: Text(
            displayName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
          subtitle: Text(
            '$readyCount/${voices.length} voices ready • $description',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          children: [
            const Divider(height: 1),

            // Cores section (for engines with shared cores)
            if (engineId != 'piper' && cores.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Core Components',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
              ...cores.map((core) => _CoreDownloadTile(core: core)),
              const Divider(height: 1),
            ],

            // Voices section
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Voices',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (readyCount < voices.length)
                    TextButton(
                      onPressed: () => _downloadAll(ref),
                      child: const Text('Download All'),
                    ),
                ],
              ),
            ),
            ...voices.map((voice) => _VoiceDownloadTile(
              voice: voice,
              cores: state.cores,
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(bool downloading, bool allReady, AppThemeColors colors) {
    if (downloading) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colors.primary,
        ),
      );
    }
    if (allReady) {
      return Icon(Icons.check_circle, color: Colors.green.shade600);
    }
    return Icon(Icons.cloud_download_outlined, color: colors.textSecondary);
  }

  void _downloadAll(WidgetRef ref) {
    ref.read(granularDownloadManagerProvider.notifier).downloadAllForEngine(engineId);
  }
}

class _CoreDownloadTile extends ConsumerWidget {
  const _CoreDownloadTile({required this.core});
  final CoreDownloadState core;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;

    return ListTile(
      dense: true,
      leading: _buildStatusIcon(colors),
      title: Text(
        core.displayName,
        style: TextStyle(
          fontSize: 14,
          color: colors.text,
        ),
      ),
      subtitle: _buildSubtitle(colors),
      trailing: _buildAction(context, ref, colors),
    );
  }

  Widget _buildStatusIcon(AppThemeColors colors) {
    switch (core.status) {
      case DownloadStatus.ready:
        return Icon(Icons.check_circle, color: Colors.green.shade600, size: 20);
      case DownloadStatus.queued:
        return Icon(Icons.schedule, color: colors.warning, size: 20);
      case DownloadStatus.downloading:
      case DownloadStatus.extracting:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            value: core.progress > 0 ? core.progress : null,
            strokeWidth: 2,
            color: colors.primary,
          ),
        );
      case DownloadStatus.failed:
        return Icon(Icons.error, color: colors.danger, size: 20);
      default:
        return Icon(Icons.cloud_download_outlined, color: colors.textSecondary, size: 20);
    }
  }

  Widget _buildSubtitle(AppThemeColors colors) {
    final sizeStr = _formatBytes(core.sizeBytes);
    switch (core.status) {
      case DownloadStatus.queued:
        return Text('Queued • $sizeStr', style: TextStyle(color: colors.warning));
      case DownloadStatus.downloading:
      case DownloadStatus.extracting:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${(core.progress * 100).toStringAsFixed(0)}% of $sizeStr'),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: core.progress,
              backgroundColor: colors.border,
              color: colors.primary,
            ),
          ],
        );
      case DownloadStatus.ready:
        return Text('Installed • $sizeStr', style: TextStyle(color: colors.textSecondary));
      case DownloadStatus.failed:
        return Text(
          core.error ?? 'Download failed',
          style: TextStyle(color: colors.danger),
        );
      default:
        return Text(sizeStr, style: TextStyle(color: colors.textSecondary));
    }
  }

  Widget? _buildAction(BuildContext context, WidgetRef ref, AppThemeColors colors) {
    switch (core.status) {
      case DownloadStatus.notDownloaded:
      case DownloadStatus.failed:
        return IconButton(
          icon: Icon(Icons.download, color: colors.primary),
          onPressed: () => ref
            .read(granularDownloadManagerProvider.notifier)
            .downloadCore(core.coreId),
        );
      case DownloadStatus.queued:
        return Text('Waiting...', style: TextStyle(color: colors.textSecondary, fontSize: 12));
      case DownloadStatus.ready:
        return IconButton(
          icon: Icon(Icons.delete_outline, color: colors.danger),
          onPressed: () => _confirmDelete(context, ref, core.coreId, core.displayName),
        );
      default:
        return null;
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String coreId, String displayName) {
    final colors = context.appColors;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Download?'),
        content: Text('This will delete "$displayName" from your device. You will need to download it again to use this voice.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(granularDownloadManagerProvider.notifier).deleteCore(coreId);
            },
            style: FilledButton.styleFrom(
              backgroundColor: colors.danger,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _VoiceDownloadTile extends ConsumerWidget {
  const _VoiceDownloadTile({
    required this.voice,
    required this.cores,
  });

  final VoiceDownloadState voice;
  final Map<String, CoreDownloadState> cores;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final isReady = voice.allCoresReady(cores);
    final isDownloading = voice.anyDownloading(cores);
    final isQueued = voice.anyQueued(cores);

    return ListTile(
      dense: true,
      leading: _buildStatusIcon(isReady, isDownloading, isQueued, colors),
      title: Text(
        voice.displayName,
        style: TextStyle(
          fontSize: 14,
          color: colors.text,
        ),
      ),
      subtitle: _buildSubtitle(isReady, isDownloading, isQueued, colors),
      trailing: _buildAction(ref, isReady, isDownloading, isQueued, colors),
    );
  }

  Widget _buildStatusIcon(bool isReady, bool isDownloading, bool isQueued, AppThemeColors colors) {
    if (isReady) {
      return Icon(Icons.check_circle, color: Colors.green.shade600, size: 20);
    }
    if (isDownloading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          value: voice.getDownloadProgress(cores),
          strokeWidth: 2,
          color: colors.primary,
        ),
      );
    }
    if (isQueued) {
      return Icon(Icons.schedule, color: colors.warning, size: 20);
    }
    return Icon(Icons.mic_outlined, color: colors.textSecondary, size: 20);
  }

  Widget _buildSubtitle(bool isReady, bool isDownloading, bool isQueued, AppThemeColors colors) {
    if (isReady) {
      return Text('Ready to use', style: TextStyle(color: colors.textSecondary));
    }
    if (isDownloading) {
      final progress = voice.getDownloadProgress(cores);
      return Text(
        'Downloading... ${(progress * 100).toStringAsFixed(0)}%',
        style: TextStyle(color: colors.textSecondary),
      );
    }
    if (isQueued) {
      return Text('Queued for download', style: TextStyle(color: colors.warning));
    }

    final missingIds = voice.getMissingCoreIds(cores);
    final missingNames = missingIds
        .map((id) => cores[id]?.displayName ?? id)
        .take(2)
        .join(', ');
    final suffix = missingIds.length > 2 ? ' +${missingIds.length - 2} more' : '';

    return Text(
      'Requires: $missingNames$suffix',
      style: TextStyle(color: colors.textSecondary),
    );
  }

  Widget? _buildAction(WidgetRef ref, bool isReady, bool isDownloading, bool isQueued, AppThemeColors colors) {
    if (isReady) {
      return Icon(Icons.check, color: Colors.green.shade600);
    }
    if (isDownloading) {
      return null;
    }
    if (isQueued) {
      return Text('Waiting...', style: TextStyle(color: colors.textSecondary, fontSize: 12));
    }

    return FilledButton.tonal(
      onPressed: () => ref
        .read(granularDownloadManagerProvider.notifier)
        .downloadVoice(voice.voiceId),
      child: const Text('Download'),
    );
  }
}

class _DeleteAllButton extends ConsumerWidget {
  const _DeleteAllButton({required this.state});
  final GranularDownloadState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final readyCores = state.cores.values.where((c) => c.isReady).length;
    final totalSize = state.totalInstalledSize;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Storage Management',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$readyCores downloaded components using ${_formatBytes(totalSize)}',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmDeleteAll(context, ref),
              icon: Icon(Icons.delete_forever, color: colors.danger),
              label: Text(
                'Delete All Downloads',
                style: TextStyle(color: colors.danger),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.danger),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAll(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Downloads?'),
        content: Text(
          'This will delete all downloaded voice models and free up ${_formatBytes(state.totalInstalledSize)} of storage. '
          'You will need to download voices again before using them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(granularDownloadManagerProvider.notifier).deleteAll();
            },
            style: FilledButton.styleFrom(
              backgroundColor: colors.danger,
            ),
            child: const Text('Delete All'),
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
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
