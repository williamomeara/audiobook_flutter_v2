import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:downloads/downloads.dart';

import '../../app/tts_providers.dart';
import '../theme/app_colors.dart';

/// Widget for managing voice model downloads.
class VoiceDownloadManager extends ConsumerWidget {
  const VoiceDownloadManager({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final downloadState = ref.watch(ttsDownloadManagerProvider);

    return downloadState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e', style: TextStyle(color: colors.danger)),
      data: (state) => Column(
        children: [
          _EngineDownloadRow(
            name: 'Kokoro',
            description: 'High-quality neural voice (250MB)',
            status: state.kokoroState,
            progress: state.kokoroProgress,
            onDownload: () => ref.read(ttsDownloadManagerProvider.notifier).downloadKokoro(),
            onDelete: () => ref.read(ttsDownloadManagerProvider.notifier).deleteModel('kokoro'),
          ),
          const Divider(height: 1),
          _EngineDownloadRow(
            name: 'Piper',
            description: 'Fast lightweight voice (65MB)',
            status: state.piperState,
            progress: state.piperProgress,
            onDownload: () => ref.read(ttsDownloadManagerProvider.notifier).downloadPiper(),
            onDelete: () => ref.read(ttsDownloadManagerProvider.notifier).deleteModel('piper'),
          ),
          const Divider(height: 1),
          _EngineDownloadRow(
            name: 'Supertonic',
            description: 'Experimental voice engine',
            status: state.supertonicState,
            progress: state.supertonicProgress,
            onDownload: () => ref.read(ttsDownloadManagerProvider.notifier).downloadSupertonic(),
            onDelete: () => ref.read(ttsDownloadManagerProvider.notifier).deleteModel('supertonic'),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                state.error!,
                style: TextStyle(color: colors.danger, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EngineDownloadRow extends StatelessWidget {
  const _EngineDownloadRow({
    required this.name,
    required this.description,
    required this.status,
    required this.progress,
    required this.onDownload,
    required this.onDelete,
  });

  final String name;
  final String description;
  final DownloadStatus status;
  final double progress;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(status: status),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
                if (status == DownloadStatus.downloading ||
                    status == DownloadStatus.extracting) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: colors.border,
                    valueColor: AlwaysStoppedAnimation(colors.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status == DownloadStatus.extracting
                        ? 'Extracting...'
                        : '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _ActionButton(
            status: status,
            onDownload: onDownload,
            onDelete: onDelete,
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final DownloadStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    
    // Use green for success since there's no success color in theme
    const successColor = Color(0xFF22C55E);

    final (label, bgColor, textColor) = switch (status) {
      DownloadStatus.ready => ('Ready', successColor.withValues(alpha: 0.2), successColor),
      DownloadStatus.downloading => ('Downloading', colors.primary.withValues(alpha: 0.2), colors.primary),
      DownloadStatus.extracting => ('Installing', colors.primary.withValues(alpha: 0.2), colors.primary),
      DownloadStatus.queued => ('Queued', colors.textSecondary.withValues(alpha: 0.2), colors.textSecondary),
      DownloadStatus.failed => ('Failed', colors.danger.withValues(alpha: 0.2), colors.danger),
      DownloadStatus.notDownloaded => ('Not installed', colors.textSecondary.withValues(alpha: 0.2), colors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.status,
    required this.onDownload,
    required this.onDelete,
  });

  final DownloadStatus status;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (status == DownloadStatus.downloading ||
        status == DownloadStatus.extracting ||
        status == DownloadStatus.queued) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(colors.primary),
        ),
      );
    }

    if (status == DownloadStatus.ready) {
      return IconButton(
        icon: Icon(Icons.delete_outline, color: colors.danger),
        onPressed: onDelete,
        tooltip: 'Delete',
      );
    }

    return IconButton(
      icon: Icon(Icons.download, color: colors.primary),
      onPressed: onDownload,
      tooltip: 'Download',
    );
  }
}
