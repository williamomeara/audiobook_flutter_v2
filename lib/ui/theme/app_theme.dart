import 'package:flutter/material.dart';

import 'app_colors.dart';

ThemeData buildLightTheme() {
  final colors = AppThemeColors.light;
  return ThemeData(
    useMaterial3: false,
    brightness: Brightness.light,
    scaffoldBackgroundColor: colors.background,
    extensions: const [AppThemeColors.light],
    appBarTheme: AppBarTheme(
      backgroundColor: colors.headerBackground,
      foregroundColor: colors.text,
      elevation: 0,
    ),
    colorScheme: ColorScheme.light(
      primary: colors.primary,
      onPrimary: colors.primaryForeground,
      surface: colors.card,
      onSurface: colors.text,
      error: colors.danger,
      onError: colors.primaryForeground,
      outline: colors.border,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.text; // Dark color when on
        }
        return colors.textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.text.withValues(alpha: 0.3);
        }
        return colors.border;
      }),
    ),
    textTheme: const TextTheme(),
  );
}

ThemeData buildDarkTheme() {
  final colors = AppThemeColors.dark;
  return ThemeData(
    useMaterial3: false,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: colors.background,
    extensions: const [AppThemeColors.dark],
    appBarTheme: AppBarTheme(
      backgroundColor: colors.headerBackground,
      foregroundColor: colors.text,
      elevation: 0,
    ),
    colorScheme: ColorScheme.dark(
      primary: colors.primary,
      onPrimary: colors.primaryForeground,
      surface: colors.card,
      onSurface: colors.text,
      error: colors.danger,
      onError: colors.primaryForeground,
      outline: colors.border,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.text; // Light color when on
        }
        return colors.textSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colors.text.withValues(alpha: 0.3);
        }
        return colors.border;
      }),
    ),
  );
}
