import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:core_domain/core_domain.dart';

/// Settings state.
class SettingsState {
  const SettingsState({
    this.darkMode = false,
    this.selectedVoice = VoiceIds.kokoroAfDefault,
    this.autoAdvanceChapters = true,
    this.defaultPlaybackRate = 1.0,
    this.smartSynthesisEnabled = true,
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

  SettingsState copyWith({
    bool? darkMode,
    String? selectedVoice,
    bool? autoAdvanceChapters,
    double? defaultPlaybackRate,
    bool? smartSynthesisEnabled,
  }) {
    return SettingsState(
      darkMode: darkMode ?? this.darkMode,
      selectedVoice: selectedVoice ?? this.selectedVoice,
      autoAdvanceChapters: autoAdvanceChapters ?? this.autoAdvanceChapters,
      defaultPlaybackRate: defaultPlaybackRate ?? this.defaultPlaybackRate,
      smartSynthesisEnabled: smartSynthesisEnabled ?? this.smartSynthesisEnabled,
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
      selectedVoice: _prefs?.getString(_keySelectedVoice) ?? VoiceIds.kokoroAfDefault,
      autoAdvanceChapters: _prefs?.getBool(_keyAutoAdvance) ?? true,
      defaultPlaybackRate: _prefs?.getDouble(_keyPlaybackRate) ?? 1.0,
      smartSynthesisEnabled: _prefs?.getBool(_keySmartSynthesis) ?? true,
    );
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
}

/// Settings provider.
final settingsProvider = NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);
