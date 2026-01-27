import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';

/// Previous chapter button.
class PreviousChapterButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;
  
  const PreviousChapterButton({
    super.key,
    required this.enabled,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            Icons.skip_previous,
            size: 24,
            color: enabled ? colors.text : colors.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// Next chapter button.
class NextChapterButton extends StatelessWidget {
  final VoidCallback? onTap;
  
  const NextChapterButton({
    super.key,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            Icons.skip_next,
            size: 24,
            color: colors.text,
          ),
        ),
      ),
    );
  }
}
