import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core_domain/core_domain.dart';
import 'package:playback/playback.dart';

import '../../app/playback_providers.dart';
import '../../app/settings_controller.dart';
import '../../app/tts_providers.dart';

/// Dialog that prompts users to optimize a TTS engine for their device.
/// 
/// Shows on first use of an unoptimized engine, offering to run a quick
/// profiling test to determine optimal synthesis settings.
class OptimizationPromptDialog extends ConsumerStatefulWidget {
  const OptimizationPromptDialog({
    required this.engineType,
    required this.voiceId,
    super.key,
  });

  final EngineType engineType;
  final String voiceId;

  /// Show the optimization prompt dialog.
  /// Returns true if optimization was run and completed.
  static Future<bool> show(BuildContext context, EngineType engineType, String voiceId) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => OptimizationPromptDialog(
        engineType: engineType,
        voiceId: voiceId,
      ),
    );
    return result ?? false;
  }

  /// Check if engine needs optimization and show prompt if needed.
  /// Returns true if engine is ready (either already optimized or just optimized).
  static Future<bool> promptIfNeeded(
    BuildContext context,
    WidgetRef ref,
    String voiceId,
  ) async {
    final engineType = VoiceIds.engineFor(voiceId);
    
    // Device TTS doesn't need optimization
    if (engineType == EngineType.device) {
      return true;
    }
    
    final configManager = ref.read(engineConfigManagerProvider);
    final engineId = DevicePerformanceProfiler.engineIdFromVoice(voiceId);
    final config = await configManager.loadConfig(engineId);
    
    // Already optimized
    if (config?.tunedAt != null) {
      return true;
    }
    
    // Show optimization prompt
    if (context.mounted) {
      return await show(context, engineType, voiceId);
    }
    
    return false;
  }

  @override
  ConsumerState<OptimizationPromptDialog> createState() => _OptimizationPromptDialogState();
}

class _OptimizationPromptDialogState extends ConsumerState<OptimizationPromptDialog> {
  bool _isOptimizing = false;
  int _progress = 0;
  int _total = 0;
  DeviceEngineConfig? _result;
  String? _error;

  String get _engineName {
    switch (widget.engineType) {
      case EngineType.piper:
        return 'Piper';
      case EngineType.kokoro:
        return 'Kokoro';
      case EngineType.supertonic:
        return 'Supertonic';
      case EngineType.device:
        return 'Device TTS';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.speed, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isOptimizing
                  ? 'Optimizing $_engineName...'
                  : _result != null
                      ? 'Optimization Complete!'
                      : 'Optimize $_engineName?',
            ),
          ),
        ],
      ),
      content: _buildContent(theme),
      actions: _buildActions(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_result != null) {
      return _buildResultContent(theme);
    }
    
    if (_isOptimizing) {
      return _buildOptimizingContent(theme);
    }
    
    return _buildPromptContent(theme);
  }

  Widget _buildPromptContent(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Run a quick test to optimize audio synthesis for your device. '
          'This only takes a few seconds and improves playback performance.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        _buildBenefitRow(
          Icons.flash_on,
          'Faster audio preparation',
          theme,
        ),
        const SizedBox(height: 8),
        _buildBenefitRow(
          Icons.pause_circle_outline,
          'Eliminate buffering during playback',
          theme,
        ),
        const SizedBox(height: 8),
        _buildBenefitRow(
          Icons.battery_saver,
          'Better battery efficiency',
          theme,
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOptimizingContent(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: _total > 0 ? _progress / _total : null,
                strokeWidth: 4,
              ),
              if (_total > 0)
                Text(
                  '$_progress/$_total',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Running synthesis test...',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'This will take a few seconds',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildResultContent(ThemeData theme) {
    final config = _result!;
    final tierName = _getTierDisplayName(config.deviceTier);
    final tierColor = _getTierColor(config.deviceTier);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tierColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tierColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(
                _getTierIcon(config.deviceTier),
                color: tierColor,
                size: 40,
              ),
              const SizedBox(height: 8),
              Text(
                tierName,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: tierColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'RTF: ${config.measuredRTF.toStringAsFixed(2)}x',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Optimal settings applied for your device.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            _buildSettingChip('Prefetch: ${config.prefetchWindowSize} segments', theme),
            if (config.prefetchConcurrency > 1)
              _buildSettingChip('Parallel: ${config.prefetchConcurrency}x', theme),
          ],
        ),
      ],
    );
  }

  Widget _buildBenefitRow(IconData icon, String text, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingChip(String text, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  List<Widget> _buildActions(ThemeData theme) {
    if (_result != null) {
      return [
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Done'),
        ),
      ];
    }
    
    if (_isOptimizing) {
      return []; // No actions while optimizing
    }
    
    return [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Skip'),
      ),
      FilledButton(
        onPressed: _runOptimization,
        child: const Text('Optimize Now'),
      ),
    ];
  }

  String _getTierDisplayName(DevicePerformanceTier tier) {
    switch (tier) {
      case DevicePerformanceTier.flagship:
        return 'Excellent Performance';
      case DevicePerformanceTier.midRange:
        return 'Good Performance';
      case DevicePerformanceTier.budget:
        return 'Moderate Performance';
      case DevicePerformanceTier.legacy:
        return 'Limited Performance';
    }
  }

  Color _getTierColor(DevicePerformanceTier tier) {
    switch (tier) {
      case DevicePerformanceTier.flagship:
        return Colors.green;
      case DevicePerformanceTier.midRange:
        return Colors.blue;
      case DevicePerformanceTier.budget:
        return Colors.orange;
      case DevicePerformanceTier.legacy:
        return Colors.red;
    }
  }

  IconData _getTierIcon(DevicePerformanceTier tier) {
    switch (tier) {
      case DevicePerformanceTier.flagship:
        return Icons.rocket_launch;
      case DevicePerformanceTier.midRange:
        return Icons.speed;
      case DevicePerformanceTier.budget:
        return Icons.directions_walk;
      case DevicePerformanceTier.legacy:
        return Icons.hourglass_bottom;
    }
  }

  Future<void> _runOptimization() async {
    setState(() {
      _isOptimizing = true;
      _error = null;
      _progress = 0;
      _total = 0;
    });

    try {
      final engine = await ref.read(ttsRoutingEngineProvider.future);
      final profiler = ref.read(deviceProfilerProvider);
      final configManager = ref.read(engineConfigManagerProvider);
      final playbackRate = ref.read(settingsProvider).defaultPlaybackRate;

      final profile = await profiler.profileEngine(
        engine: engine,
        voiceId: widget.voiceId,
        playbackRate: playbackRate,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _progress = current;
              _total = total;
            });
          }
        },
      );

      final config = profiler.createConfigFromProfile(profile);
      await configManager.saveConfig(config);

      if (mounted) {
        setState(() {
          _result = config;
          _isOptimizing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Optimization failed: $e';
          _isOptimizing = false;
        });
      }
    }
  }
}
