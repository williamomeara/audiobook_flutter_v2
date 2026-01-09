import 'package:flutter/material.dart';

class AppPalette {
  static const neutral50 = Color(0xFFF9FAFB);
  static const neutral100 = Color(0xFFF3F4F6);
  static const neutral200 = Color(0xFFE5E7EB);
  static const neutral300 = Color(0xFFD1D5DB);
  static const neutral400 = Color(0xFF9CA3AF);
  static const neutral500 = Color(0xFF6B7280);
  static const neutral600 = Color(0xFF4B5563);
  static const neutral700 = Color(0xFF374151);
  static const neutral800 = Color(0xFF1F2937);
  static const neutral900 = Color(0xFF111827);
  static const neutral950 = Color(0xFF030712);

  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo300 = Color(0xFFA5B4FC);
  static const indigo400 = Color(0xFF818CF8);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo700 = Color(0xFF4338CA);
  static const indigo800 = Color(0xFF3730A3);
  static const indigo900 = Color(0xFF312E81);

  // Slate palette (from Figma design)
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);

  // Amber palette (accent color from Figma design)
  static const amber400 = Color(0xFFFBBF24);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);

  // Light mode colors (from Figma Improve Colour Palette)
  static const lightPrimary = Color(0xFF030213);       // Near black primary
  static const lightMuted = Color(0xFFECECF0);         // Muted background
  static const lightMutedForeground = Color(0xFF717182); // Muted text
  static const lightAccent = Color(0xFFE9EBEF);        // Accent background
  static const lightInputBg = Color(0xFFF3F3F5);       // Input field background
  static const lightPageBg = Color(0xFFF5F5F5);        // Page background
  static const lightBorder = Color(0x1A000000);        // 10% black border
  static const lightDestructive = Color(0xFFD4183D);   // Red destructive

  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
  static const red = Color(0xFFEF4444);
}

@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.background,
    required this.backgroundSecondary,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.primaryForeground,
    required this.accent,
    required this.accentForeground,
    required this.card,
    required this.border,
    required this.inputBackground,
    required this.danger,
    required this.warning,
    required this.headerBackground,
    required this.tabBarBackground,
    required this.voiceBadgeBackground,
    required this.voiceBadgeText,
    required this.chapterItemBg,
    required this.textHighlight,
    required this.textPast,
    required this.controlBackground,
  });

  final Color background;
  final Color backgroundSecondary;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color primary;
  final Color primaryForeground;
  final Color accent;
  final Color accentForeground;
  final Color card;
  final Color border;
  final Color inputBackground;
  final Color danger;
  final Color warning;

  final Color headerBackground;
  final Color tabBarBackground;
  final Color voiceBadgeBackground;
  final Color voiceBadgeText;
  final Color chapterItemBg;
  final Color textHighlight;
  final Color textPast;
  final Color controlBackground;

  static const light = AppThemeColors(
    background: AppPalette.lightPageBg,
    backgroundSecondary: AppPalette.white,
    text: AppPalette.lightPrimary,
    textSecondary: AppPalette.lightMutedForeground,
    textTertiary: AppPalette.neutral400,
    primary: AppPalette.lightPrimary,
    primaryForeground: AppPalette.white,
    accent: AppPalette.lightAccent,
    accentForeground: AppPalette.lightPrimary,
    card: AppPalette.white,
    border: AppPalette.lightBorder,
    inputBackground: AppPalette.lightInputBg,
    danger: AppPalette.lightDestructive,
    warning: AppPalette.amber600,
    headerBackground: AppPalette.white,
    tabBarBackground: AppPalette.white,
    voiceBadgeBackground: AppPalette.lightMuted,
    voiceBadgeText: AppPalette.lightPrimary,
    chapterItemBg: AppPalette.lightMuted,
    textHighlight: AppPalette.lightPrimary,
    textPast: AppPalette.neutral400,
    controlBackground: AppPalette.lightInputBg,
  );

  static const dark = AppThemeColors(
    background: AppPalette.slate900,
    backgroundSecondary: AppPalette.slate800,
    text: AppPalette.white,
    textSecondary: AppPalette.slate400,
    textTertiary: AppPalette.slate600,
    primary: AppPalette.amber500,
    primaryForeground: AppPalette.slate900,
    accent: AppPalette.amber500,
    accentForeground: AppPalette.slate900,
    card: AppPalette.slate800,
    border: AppPalette.slate700,
    inputBackground: AppPalette.slate700,
    danger: AppPalette.red,
    warning: AppPalette.amber500,
    headerBackground: AppPalette.slate900,
    tabBarBackground: AppPalette.slate900,
    voiceBadgeBackground: Color(0x33F59E0B),
    voiceBadgeText: AppPalette.amber400,
    chapterItemBg: AppPalette.slate800,
    textHighlight: AppPalette.amber400,
    textPast: AppPalette.slate500,
    controlBackground: AppPalette.slate700,
  );

  @override
  AppThemeColors copyWith({
    Color? background,
    Color? backgroundSecondary,
    Color? text,
    Color? textSecondary,
    Color? textTertiary,
    Color? primary,
    Color? primaryForeground,
    Color? accent,
    Color? accentForeground,
    Color? card,
    Color? border,
    Color? inputBackground,
    Color? danger,
    Color? warning,
    Color? headerBackground,
    Color? tabBarBackground,
    Color? voiceBadgeBackground,
    Color? voiceBadgeText,
    Color? chapterItemBg,
    Color? textHighlight,
    Color? textPast,
    Color? controlBackground,
  }) {
    return AppThemeColors(
      background: background ?? this.background,
      backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      primary: primary ?? this.primary,
      primaryForeground: primaryForeground ?? this.primaryForeground,
      accent: accent ?? this.accent,
      accentForeground: accentForeground ?? this.accentForeground,
      card: card ?? this.card,
      border: border ?? this.border,
      inputBackground: inputBackground ?? this.inputBackground,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      headerBackground: headerBackground ?? this.headerBackground,
      tabBarBackground: tabBarBackground ?? this.tabBarBackground,
      voiceBadgeBackground: voiceBadgeBackground ?? this.voiceBadgeBackground,
      voiceBadgeText: voiceBadgeText ?? this.voiceBadgeText,
      chapterItemBg: chapterItemBg ?? this.chapterItemBg,
      textHighlight: textHighlight ?? this.textHighlight,
      textPast: textPast ?? this.textPast,
      controlBackground: controlBackground ?? this.controlBackground,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      background: Color.lerp(background, other.background, t)!,
      backgroundSecondary: Color.lerp(backgroundSecondary, other.backgroundSecondary, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryForeground: Color.lerp(primaryForeground, other.primaryForeground, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentForeground: Color.lerp(accentForeground, other.accentForeground, t)!,
      card: Color.lerp(card, other.card, t)!,
      border: Color.lerp(border, other.border, t)!,
      inputBackground: Color.lerp(inputBackground, other.inputBackground, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      headerBackground: Color.lerp(headerBackground, other.headerBackground, t)!,
      tabBarBackground: Color.lerp(tabBarBackground, other.tabBarBackground, t)!,
      voiceBadgeBackground: Color.lerp(voiceBadgeBackground, other.voiceBadgeBackground, t)!,
      voiceBadgeText: Color.lerp(voiceBadgeText, other.voiceBadgeText, t)!,
      chapterItemBg: Color.lerp(chapterItemBg, other.chapterItemBg, t)!,
      textHighlight: Color.lerp(textHighlight, other.textHighlight, t)!,
      textPast: Color.lerp(textPast, other.textPast, t)!,
      controlBackground: Color.lerp(controlBackground, other.controlBackground, t)!,
    );
  }
}

extension AppThemeColorsX on BuildContext {
  AppThemeColors get appColors => Theme.of(this).extension<AppThemeColors>()!;
}
