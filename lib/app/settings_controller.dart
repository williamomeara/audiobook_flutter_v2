import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:core_domain/core_domain.dart';

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
    );
  }
}

/// Settings controller.
class SettingsController extends Notifier<SettingsState> {
  static const _keyDarkMode = 'dark_mode';
  static const _keySelectedVoice = 'selected_voice';
  static const _keyAutoAdvance = 'auto_advance_chapters';
  static const _keyPlaybackRate = 'default_playback_rate';
  static const _keySmartSynthesis = 'smart_synthesis_enabled';
  static const _keyCacheQuotaGB = 'cache_quota_gb';
  static const _keyShowBookCoverBackground = 'show_book_cover_background';
  static const _keyHapticFeedbackEnabled = 'haptic_feedback_enabled';
  static const _keySynthesisMode = 'synthesis_mode';
  static const _keyShowBufferIndicator = 'show_buffer_indicator';

  @override
  SettingsState build() {
    _loadFromPrefs();
    return const SettingsState();
  }

  SharedPreferences? _prefs;

  Future<void> _loadFromPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    
    state = SettingsState(
      darkMode: _prefs?.getBool(_keyDarkMode) ?? false,
      selectedVoice: _prefs?.getString(_keySelectedVoice) ?? VoiceIds.none,
      autoAdvanceChapters: _prefs?.getBool(_keyAutoAdvance) ?? true,
      defaultPlaybackRate: _prefs?.getDouble(_keyPlaybackRate) ?? 1.0,
      smartSynthesisEnabled: _prefs?.getBool(_keySmartSynthesis) ?? true,
      cacheQuotaGB: (_prefs?.getDouble(_keyCacheQuotaGB) ?? 2.0).clamp(0.5, 4.0),
      showBookCoverBackground: _prefs?.getBool(_keyShowBookCoverBackground) ?? true,
      hapticFeedbackEnabled: _prefs?.getBool(_keyHapticFeedbackEnabled) ?? true,
      synthesisMode: _parseSynthesisMode(_prefs?.getString(_keySynthesisMode)),
      showBufferIndicator: _prefs?.getBool(_keyShowBufferIndicator) ?? true,
    );
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
    await _prefs?.setBool(_keyDarkMode, value);
  }

  Future<void> setSelectedVoice(String voiceId) async {
    state = state.copyWith(selectedVoice: voiceId);
    await _prefs?.setString(_keySelectedVoice, voiceId);
  }

  Future<void> setAutoAdvanceChapters(bool value) async {
    state = state.copyWith(autoAdvanceChapters: value);
    await _prefs?.setBool(_keyAutoAdvance, value);
  }

  Future<void> setDefaultPlaybackRate(double rate) async {
    state = state.copyWith(defaultPlaybackRate: rate);
    await _prefs?.setDouble(_keyPlaybackRate, rate);
  }

  Future<void> setSmartSynthesisEnabled(bool value) async {
    state = state.copyWith(smartSynthesisEnabled: value);
    await _prefs?.setBool(_keySmartSynthesis, value);
  }

  Future<void> setCacheQuotaGB(double quotaGB) async {
    state = state.copyWith(cacheQuotaGB: quotaGB);
    await _prefs?.setDouble(_keyCacheQuotaGB, quotaGB);
  }

  Future<void> setShowBookCoverBackground(bool value) async {
    state = state.copyWith(showBookCoverBackground: value);
    await _prefs?.setBool(_keyShowBookCoverBackground, value);
  }

  Future<void> setHapticFeedbackEnabled(bool value) async {
    state = state.copyWith(hapticFeedbackEnabled: value);
    await _prefs?.setBool(_keyHapticFeedbackEnabled, value);
  }

  Future<void> setSynthesisMode(SynthesisMode mode) async {
    state = state.copyWith(synthesisMode: mode);
    await _prefs?.setString(_keySynthesisMode, mode.name);
  }

  Future<void> setShowBufferIndicator(bool value) async {
    state = state.copyWith(showBufferIndicator: value);
    await _prefs?.setBool(_keyShowBufferIndicator, value);
  }
}

/// Settings provider.
final settingsProvider = NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);
