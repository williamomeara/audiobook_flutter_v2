import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings_controller.dart';
import '../theme/app_colors.dart';

/// A picker for synthesis speed mode (Auto/Performance/Efficiency).
///
/// Uses RadioListTile for accessibility and Material Design compliance.
/// Shows descriptions to help users understand the tradeoffs.
class SynthesisModePicker extends ConsumerWidget {
  const SynthesisModePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final currentMode = ref.watch(settingsProvider.select((s) => s.synthesisMode));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Synthesis Speed',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
        _SynthesisModeOption(
          mode: SynthesisMode.auto,
          title: 'Auto (Recommended)',
          description: 'Adapts to your device and listening. '
              'Saves battery when ahead, speeds up when needed.',
          icon: Icons.auto_mode,
          currentMode: currentMode,
          colors: colors,
          onSelected: () => ref
              .read(settingsProvider.notifier)
              .setSynthesisMode(SynthesisMode.auto),
        ),
        _SynthesisModeOption(
          mode: SynthesisMode.performance,
          title: 'Performance',
          description: 'Maximum speed. Uses more battery '
              'and may warm device.',
          icon: Icons.speed,
          currentMode: currentMode,
          colors: colors,
          onSelected: () => ref
              .read(settingsProvider.notifier)
              .setSynthesisMode(SynthesisMode.performance),
        ),
        _SynthesisModeOption(
          mode: SynthesisMode.efficiency,
          title: 'Efficiency',
          description: 'Minimum resource usage. '
              'May briefly pause on fast seeks.',
          icon: Icons.eco,
          currentMode: currentMode,
          colors: colors,
          onSelected: () => ref
              .read(settingsProvider.notifier)
              .setSynthesisMode(SynthesisMode.efficiency),
        ),
      ],
    );
  }
}

class _SynthesisModeOption extends StatelessWidget {
  const _SynthesisModeOption({
    required this.mode,
    required this.title,
    required this.description,
    required this.icon,
    required this.currentMode,
    required this.colors,
    required this.onSelected,
  });

  final SynthesisMode mode;
  final String title;
  final String description;
  final IconData icon;
  final SynthesisMode currentMode;
  final AppThemeColors colors;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final isSelected = mode == currentMode;

    return InkWell(
      onTap: onSelected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Radio<SynthesisMode>(
              value: mode,
              groupValue: currentMode,
              onChanged: (_) => onSelected(),
              activeColor: colors.primary,
            ),
            const SizedBox(width: 8),
            Icon(
              icon,
              size: 24,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? colors.text : colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
