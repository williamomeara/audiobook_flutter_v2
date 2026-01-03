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

  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
  static const red = Color(0xFFEF4444);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
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
  });

  final Color background;
  final Color backgroundSecondary;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color primary;
  final Color primaryForeground;
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

  static const light = AppThemeColors(
    background: AppPalette.white,
    backgroundSecondary: AppPalette.neutral50,
    text: AppPalette.neutral900,
    textSecondary: AppPalette.neutral500,
    textTertiary: AppPalette.neutral400,
    primary: AppPalette.indigo500,
    primaryForeground: AppPalette.white,
    card: AppPalette.white,
    border: AppPalette.neutral200,
    inputBackground: AppPalette.neutral100,
    danger: AppPalette.red,
    warning: AppPalette.amber600,
    headerBackground: AppPalette.white,
    tabBarBackground: AppPalette.white,
    voiceBadgeBackground: AppPalette.indigo100,
    voiceBadgeText: AppPalette.indigo700,
    chapterItemBg: AppPalette.neutral50,
  );

  static const dark = AppThemeColors(
    background: AppPalette.neutral950,
    backgroundSecondary: AppPalette.neutral900,
    text: AppPalette.neutral50,
    textSecondary: AppPalette.neutral400,
    textTertiary: AppPalette.neutral600,
    primary: AppPalette.indigo500,
    primaryForeground: AppPalette.white,
    card: AppPalette.neutral900,
    border: AppPalette.neutral800,
    inputBackground: AppPalette.neutral800,
    danger: AppPalette.red,
    warning: AppPalette.amber500,
    headerBackground: AppPalette.neutral950,
    tabBarBackground: AppPalette.neutral950,
    voiceBadgeBackground: Color(0x336366F1),
    voiceBadgeText: AppPalette.indigo300,
    chapterItemBg: AppPalette.neutral900,
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
  }) {
    return AppThemeColors(
      background: background ?? this.background,
      backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      primary: primary ?? this.primary,
      primaryForeground: primaryForeground ?? this.primaryForeground,
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
    );
  }
}

extension AppThemeColorsX on BuildContext {
  AppThemeColors get appColors => Theme.of(this).extension<AppThemeColors>()!;
}
