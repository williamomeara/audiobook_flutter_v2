import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:core_domain/core_domain.dart';

import 'database/app_database.dart';
import 'database/daos/settings_dao.dart';
import 'quick_settings_service.dart';

/// Synthesis speed mode - how aggressively to synthesize ahead.
///
/// These are user preferences that affect buffer behavior:
/// - Auto: Adapts to device and listening (recommended)
/// - Performance: Maximum speed, uses more battery
/// - Efficiency: Minimum resource usage, may pause briefly
enum SynthesisMode {
  /// Auto-calibrates based on device capability and demand.
  /// Saves battery when ahead, speeds up when needed.
  auto,

  /// Maximum synthesis speed. Uses more battery.
  /// Good for older devices that need aggressive buffering.
  performance,

  /// Minimum resource usage. May briefly pause on seeks.
  /// Good for battery-conscious users.
  efficiency,
}

/// Settings state.
class SettingsState {
  const SettingsState({
    this.darkMode = false,
    this.selectedVoice = VoiceIds.none,
    this.autoAdvanceChapters = true,
    this.defaultPlaybackRate = 1.0,
    this.smartSynthesisEnabled = true,
    this.cacheQuotaGB = 2.0,
    this.showBookCoverBackground = true,
    this.hapticFeedbackEnabled = true,
    this.synthesisMode = SynthesisMode.auto,
    this.showBufferIndicator = true,
    this.compressOnSynthesize = true,
  });

  /// Whether dark mode is enabled.
  final bool darkMode;

  /// Currently selected voice ID.
  final String selectedVoice;

  /// Whether to auto-advance to next chapter.
  final bool autoAdvanceChapters;

  /// Default playback rate.
  final double defaultPlaybackRate;

  /// Whether smart synthesis (first-segment pre-synthesis) is enabled.
  final bool smartSynthesisEnabled;

  /// Audio cache quota in GB (0.5 to 4.0).
  final double cacheQuotaGB;

  /// Whether to show book cover as faded background in playback screen.
  final bool showBookCoverBackground;

  /// Whether haptic feedback is enabled for playback controls.
  final bool hapticFeedbackEnabled;

  /// Synthesis speed mode (auto/performance/efficiency).
  final SynthesisMode synthesisMode;

  /// Whether to show buffer indicator in playback screen.
  final bool showBufferIndicator;

  /// Whether to automatically compress audio after synthesis (saves ~90% space).
  final bool compressOnSynthesize;

  SettingsState copyWith({
    bool? darkMode,
    String? selectedVoice,
    bool? autoAdvanceChapters,
    double? defaultPlaybackRate,
    bool? smartSynthesisEnabled,
    double? cacheQuotaGB,
    bool? showBookCoverBackground,
    bool? hapticFeedbackEnabled,
    SynthesisMode? synthesisMode,
    bool? showBufferIndicator,
    bool? compressOnSynthesize,
  }) {
    return SettingsState(
      darkMode: darkMode ?? this.darkMode,
      selectedVoice: selectedVoice ?? this.selectedVoice,
      autoAdvanceChapters: autoAdvanceChapters ?? this.autoAdvanceChapters,
      defaultPlaybackRate: defaultPlaybackRate ?? this.defaultPlaybackRate,
      smartSynthesisEnabled: smartSynthesisEnabled ?? this.smartSynthesisEnabled,
      cacheQuotaGB: cacheQuotaGB ?? this.cacheQuotaGB,
      showBookCoverBackground: showBookCoverBackground ?? this.showBookCoverBackground,
      hapticFeedbackEnabled: hapticFeedbackEnabled ?? this.hapticFeedbackEnabled,
      synthesisMode: synthesisMode ?? this.synthesisMode,
      showBufferIndicator: showBufferIndicator ?? this.showBufferIndicator,
      compressOnSynthesize: compressOnSynthesize ?? this.compressOnSynthesize,
    );
  }
}

/// Settings controller using SQLite for persistence.
///
/// Only dark_mode uses SharedPreferences (via QuickSettingsService) for
/// instant theme loading at startup. All other settings use SQLite.
class SettingsController extends Notifier<SettingsState> {
  SettingsDao? _settingsDao;

  @override
  SettingsState build() {
    _loadFromSqlite();
    // Return default state immediately; actual values loaded async
    // Use QuickSettingsService for initial dark mode if available
    final initialDarkMode = QuickSettingsService.isInitialized
        ? QuickSettingsService.instance.darkMode
        : false;
    return SettingsState(darkMode: initialDarkMode);
  }

  Future<void> _loadFromSqlite() async {
    try {
      final db = await AppDatabase.instance;
      _settingsDao = SettingsDao(db);

      // Load all settings from SQLite
      final darkMode = await _settingsDao!.getBool(SettingsKeys.darkMode) ??
          (QuickSettingsService.isInitialized
              ? QuickSettingsService.instance.darkMode
              : false);
      final selectedVoice =
          await _settingsDao!.getString(SettingsKeys.selectedVoice) ??
              VoiceIds.none;
      final autoAdvanceChapters =
          await _settingsDao!.getBool(SettingsKeys.autoAdvanceChapters) ?? true;
      final defaultPlaybackRate =
          await _settingsDao!.getDouble(SettingsKeys.defaultPlaybackRate);
      final smartSynthesisEnabled =
          await _settingsDao!.getBool(SettingsKeys.smartSynthesisEnabled) ??
              true;
      final cacheQuotaGB =
          await _settingsDao!.getDouble(SettingsKeys.cacheQuotaGb);
      final showBookCoverBackground =
          await _settingsDao!.getBool(SettingsKeys.showBookCoverBackground) ??
              true;
      final hapticFeedbackEnabled =
          await _settingsDao!.getBool(SettingsKeys.hapticFeedbackEnabled) ??
              true;
      final synthesisModeStr =
          await _settingsDao!.getString(SettingsKeys.synthesisMode);
      final showBufferIndicator =
          await _settingsDao!.getBool(SettingsKeys.showBufferIndicator) ?? true;
      final compressOnSynthesize =
          await _settingsDao!.getBool(SettingsKeys.compressOnSynthesize) ?? true;

      state = SettingsState(
        darkMode: darkMode,
        selectedVoice: selectedVoice,
        autoAdvanceChapters: autoAdvanceChapters,
        defaultPlaybackRate: defaultPlaybackRate ?? 1.0,
        smartSynthesisEnabled: smartSynthesisEnabled,
        cacheQuotaGB: (cacheQuotaGB ?? 2.0).clamp(0.5, 4.0),
        showBookCoverBackground: showBookCoverBackground,
        hapticFeedbackEnabled: hapticFeedbackEnabled,
        synthesisMode: _parseSynthesisMode(synthesisModeStr),
        showBufferIndicator: showBufferIndicator,
        compressOnSynthesize: compressOnSynthesize,
      );

      developer.log(
        '📦 Settings loaded from SQLite',
        name: 'SettingsController',
      );
    } catch (e, st) {
      developer.log(
        '⚠️ Failed to load settings from SQLite: $e',
        name: 'SettingsController',
        error: e,
        stackTrace: st,
      );
    }
  }

  SynthesisMode _parseSynthesisMode(String? value) {
    switch (value) {
      case 'performance':
        return SynthesisMode.performance;
      case 'efficiency':
        return SynthesisMode.efficiency;
      default:
        return SynthesisMode.auto;
    }
  }

  Future<void> setDarkMode(bool value) async {
    state = state.copyWith(darkMode: value);
    // Write to both SharedPreferences (for instant startup) and SQLite
    if (QuickSettingsService.isInitialized) {
      await QuickSettingsService.instance.setDarkMode(value);
    }
    await _settingsDao?.setBool(SettingsKeys.darkMode, value);
  }

  Future<void> setSelectedVoice(String voiceId) async {
    state = state.copyWith(selectedVoice: voiceId);
    await _settingsDao?.setString(SettingsKeys.selectedVoice, voiceId);
  }

  Future<void> setAutoAdvanceChapters(bool value) async {
    state = state.copyWith(autoAdvanceChapters: value);
    await _settingsDao?.setBool(SettingsKeys.autoAdvanceChapters, value);
  }

  Future<void> setDefaultPlaybackRate(double rate) async {
    state = state.copyWith(defaultPlaybackRate: rate);
    await _settingsDao?.setSetting(SettingsKeys.defaultPlaybackRate, rate);
  }

  Future<void> setSmartSynthesisEnabled(bool value) async {
    state = state.copyWith(smartSynthesisEnabled: value);
    await _settingsDao?.setBool(SettingsKeys.smartSynthesisEnabled, value);
  }

  Future<void> setCacheQuotaGB(double quotaGB) async {
    state = state.copyWith(cacheQuotaGB: quotaGB);
    await _settingsDao?.setSetting(SettingsKeys.cacheQuotaGb, quotaGB);
  }

  Future<void> setShowBookCoverBackground(bool value) async {
    state = state.copyWith(showBookCoverBackground: value);
    await _settingsDao?.setBool(SettingsKeys.showBookCoverBackground, value);
  }

  Future<void> setHapticFeedbackEnabled(bool value) async {
    state = state.copyWith(hapticFeedbackEnabled: value);
    await _settingsDao?.setBool(SettingsKeys.hapticFeedbackEnabled, value);
  }

  Future<void> setSynthesisMode(SynthesisMode mode) async {
    state = state.copyWith(synthesisMode: mode);
    await _settingsDao?.setString(SettingsKeys.synthesisMode, mode.name);
  }

  Future<void> setShowBufferIndicator(bool value) async {
    state = state.copyWith(showBufferIndicator: value);
    await _settingsDao?.setBool(SettingsKeys.showBufferIndicator, value);
  }

  Future<void> setCompressOnSynthesize(bool value) async {
    state = state.copyWith(compressOnSynthesize: value);
    await _settingsDao?.setBool(SettingsKeys.compressOnSynthesize, value);
  }
}

/// Settings provider.
final settingsProvider = NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);
