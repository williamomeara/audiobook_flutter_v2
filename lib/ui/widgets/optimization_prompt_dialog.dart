import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core_domain/core_domain.dart';
import 'package:playback/playback.dart';

import '../../app/playback_providers.dart';
import '../../app/settings_controller.dart';
import '../../app/tts_providers.dart';
import '../theme/app_colors.dart';

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
    final colors = context.appColors;
    
    return Dialog(
      backgroundColor: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.speed, color: colors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isOptimizing
                        ? 'Optimizing $_engineName...'
                        : _result != null
                            ? 'Optimization Complete!'
                            : 'Optimize $_engineName?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Content
            _buildContent(theme, colors),
            
            const SizedBox(height: 24),
            
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: _buildActions(theme, colors),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, AppThemeColors colors) {
    if (_result != null) {
      return _buildResultContent(theme, colors);
    }
    
    if (_isOptimizing) {
      return _buildOptimizingContent(theme, colors);
    }
    
    return _buildPromptContent(theme, colors);
  }

  Widget _buildPromptContent(ThemeData theme, AppThemeColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Run a quick test to optimize audio synthesis for your device. '
          'This only takes a few seconds and improves playback performance.',
          style: TextStyle(
            fontSize: 14,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        _buildBenefitRow(
          Icons.flash_on,
          'Faster audio preparation',
          colors,
        ),
        const SizedBox(height: 8),
        _buildBenefitRow(
          Icons.pause_circle_outline,
          'Eliminate buffering during playback',
          colors,
        ),
        const SizedBox(height: 8),
        _buildBenefitRow(
          Icons.battery_saver,
          'Better battery efficiency',
          colors,
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade400, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade400, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOptimizingContent(ThemeData theme, AppThemeColors colors) {
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
                color: colors.primary,
              ),
              if (_total > 0)
                Text(
                  '$_progress/$_total',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Running synthesis test...',
          style: TextStyle(
            fontSize: 14,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'This will take a few seconds',
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildResultContent(ThemeData theme, AppThemeColors colors) {
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
            borderRadius: BorderRadius.circular(16),
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
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: tierColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'RTF: ${config.measuredRTF.toStringAsFixed(2)}x',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Optimal settings applied for your device.',
          style: TextStyle(
            fontSize: 14,
            color: colors.text,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            _buildSettingChip('Prefetch: ${config.prefetchWindowSize} segments', colors),
            if (config.prefetchConcurrency > 1)
              _buildSettingChip('Parallel: ${config.prefetchConcurrency}x', colors),
          ],
        ),
      ],
    );
  }

  Widget _buildBenefitRow(IconData icon, String text, AppThemeColors colors) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: colors.text,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingChip(String text, AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: colors.textSecondary,
        ),
      ),
    );
  }

  List<Widget> _buildActions(ThemeData theme, AppThemeColors colors) {
    if (_result != null) {
      return [
        _buildActionButton(
          label: 'Done',
          onPressed: () => Navigator.pop(context, true),
          colors: colors,
          isPrimary: true,
        ),
      ];
    }
    
    if (_isOptimizing) {
      return []; // No actions while optimizing
    }
    
    return [
      _buildActionButton(
        label: 'Skip',
        onPressed: () => Navigator.pop(context, false),
        colors: colors,
        isPrimary: false,
      ),
      const SizedBox(width: 12),
      _buildActionButton(
        label: 'Optimize Now',
        onPressed: _runOptimization,
        colors: colors,
        isPrimary: true,
      ),
    ];
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback onPressed,
    required AppThemeColors colors,
    required bool isPrimary,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary ? colors.primary : colors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isPrimary ? Colors.white : colors.textSecondary,
          ),
        ),
      ),
    );
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
