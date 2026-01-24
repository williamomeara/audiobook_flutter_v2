import 'dart:async';

import 'package:flutter/material.dart';
import 'package:playback/playback.dart';
import 'package:tts_engines/tts_engines.dart';

/// Dialog for calibrating TTS engine performance.
///
/// Shows progress during calibration and displays results.
/// Call [showCalibrationDialog] to display this dialog.
class CalibrationDialog extends StatefulWidget {
  const CalibrationDialog({
    required this.routingEngine,
    required this.voiceId,
    required this.engineType,
    required this.audioCache,
    super.key,
  });

  final RoutingEngine routingEngine;
  final String voiceId;
  final String engineType;
  final AudioCache audioCache;

  @override
  State<CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<CalibrationDialog> {
  bool _isCalibrating = true;
  String _progressMessage = 'Preparing calibration...';
  int _currentStep = 0;
  int _totalSteps = 3;
  CalibrationResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runCalibration();
  }

  Future<void> _runCalibration() async {
    try {
      final service = EngineCalibrationService();
      final result = await service.calibrateEngine(
        routingEngine: widget.routingEngine,
        voiceId: widget.voiceId,
        onProgress: (step, total, message) {
          if (mounted) {
            setState(() {
              _currentStep = step;
              _totalSteps = total;
              _progressMessage = message;
            });
          }
        },
        clearCacheFunc: () => widget.audioCache.clear(),
      );

      if (mounted) {
        setState(() {
          _isCalibrating = false;
          _result = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCalibrating = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isCalibrating
                ? Icons.tune
                : (_error != null ? Icons.error_outline : Icons.check_circle),
            color: _error != null ? theme.colorScheme.error : null,
          ),
          const SizedBox(width: 12),
          Text(
            _isCalibrating
                ? 'Optimizing ${_getEngineDisplayName()}'
                : (_error != null ? 'Calibration Failed' : 'Optimization Complete'),
          ),
        ],
      ),
      content: _isCalibrating
          ? _buildProgressContent(theme)
          : (_error != null
              ? _buildErrorContent(theme)
              : _buildResultContent(theme)),
      actions: [
        if (!_isCalibrating)
          TextButton(
            onPressed: () => Navigator.of(context).pop(_result),
            child: const Text('OK'),
          ),
      ],
    );
  }

  Widget _buildProgressContent(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Testing synthesis performance...',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: _totalSteps > 0 ? _currentStep / _totalSteps : null,
        ),
        const SizedBox(height: 8),
        Text(
          _progressMessage,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Step $_currentStep of $_totalSteps',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorContent(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Could not complete calibration.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? 'Unknown error',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
    );
  }

  Widget _buildResultContent(ThemeData theme) {
    final result = _result!;
    final speedupPercent = ((result.expectedSpeedup - 1) * 100).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.speed,
              color: theme.colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              speedupPercent > 0
                  ? '$speedupPercent% faster synthesis'
                  : 'No speedup achieved',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildResultRow(
          theme,
          'Optimal concurrency',
          '${result.optimalConcurrency}x parallel',
        ),
        _buildResultRow(
          theme,
          'Real-time factor',
          '${result.rtfAtOptimal.toStringAsFixed(2)}x',
        ),
        _buildResultRow(
          theme,
          'Calibration time',
          '${(result.calibrationDurationMs / 1000).toStringAsFixed(1)}s',
        ),
        if (result.hasWarnings) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.tertiary,
                size: 16,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  result.warningMessage ?? 'Some concurrency levels had issues',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildResultRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _getEngineDisplayName() {
    return switch (widget.engineType.toLowerCase()) {
      'kokoro' => 'Kokoro',
      'piper' => 'Piper',
      'supertonic' => 'Supertonic',
      _ => widget.engineType,
    };
  }
}

/// Show calibration dialog and return the result.
///
/// Returns [CalibrationResult] if calibration succeeded, null if cancelled or failed.
Future<CalibrationResult?> showCalibrationDialog({
  required BuildContext context,
  required RoutingEngine routingEngine,
  required String voiceId,
  required String engineType,
  required AudioCache audioCache,
}) {
  return showDialog<CalibrationResult>(
    context: context,
    barrierDismissible: false, // Must complete or cancel explicitly
    builder: (context) => CalibrationDialog(
      routingEngine: routingEngine,
      voiceId: voiceId,
      engineType: engineType,
      audioCache: audioCache,
    ),
  );
}
