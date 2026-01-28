import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// Bottom sheet picker for selecting sleep timer duration.
/// 
/// Returns the selected duration in minutes, or null if timer should be off.
class SleepTimerPicker extends StatelessWidget {
  const SleepTimerPicker({
    super.key,
    required this.currentMinutes,
  });

  /// Currently selected sleep timer minutes (null = off).
  final int? currentMinutes;

  /// Sleep timer options.
  static const List<int?> options = [null, 5, 10, 15, 30, 60];
  
  /// Labels for each option.
  static const List<String> labels = ['Off', '5 min', '10 min', '15 min', '30 min', '1 hour'];

  /// Shows the sleep timer picker and returns the selected value.
  /// Returns null if user dismissed without selecting.
  static Future<int?> show(BuildContext context, {int? currentMinutes}) async {
    return showModalBottomSheet<int?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SleepTimerPicker(currentMinutes: currentMinutes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Sleep Timer',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(options.length, (i) {
                      final value = options[i];
                      final isSelected = currentMinutes == value;
                      return InkWell(
                        onTap: () => Navigator.pop(context, value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  labels[i],
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isSelected ? colors.primary : colors.text,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle, color: colors.primary, size: 20),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
