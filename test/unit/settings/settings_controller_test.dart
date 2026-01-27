import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/app/settings_controller.dart';

void main() {
  group('SettingsState', () {
    test('has sensible defaults', () {
      const state = SettingsState();
      
      expect(state.darkMode, false);
      expect(state.selectedVoice, 'none');
      expect(state.autoAdvanceChapters, true);
      expect(state.defaultPlaybackRate, 1.0);
      expect(state.smartSynthesisEnabled, true);
      expect(state.cacheQuotaGB, 2.0);
      expect(state.showBookCoverBackground, true);
      expect(state.hapticFeedbackEnabled, true);
      expect(state.synthesisMode, SynthesisMode.auto);
      expect(state.showBufferIndicator, true);
      expect(state.compressOnSynthesize, true);
    });

    test('copyWith creates new instance with updated values', () {
      const original = SettingsState();
      
      final updated = original.copyWith(
        darkMode: true,
        selectedVoice: 'kokoro-v1-en-us',
        defaultPlaybackRate: 1.5,
        cacheQuotaGB: 4.0,
      );
      
      // Updated values
      expect(updated.darkMode, true);
      expect(updated.selectedVoice, 'kokoro-v1-en-us');
      expect(updated.defaultPlaybackRate, 1.5);
      expect(updated.cacheQuotaGB, 4.0);
      
      // Unchanged values
      expect(updated.autoAdvanceChapters, original.autoAdvanceChapters);
      expect(updated.smartSynthesisEnabled, original.smartSynthesisEnabled);
      expect(updated.showBookCoverBackground, original.showBookCoverBackground);
      expect(updated.hapticFeedbackEnabled, original.hapticFeedbackEnabled);
      expect(updated.synthesisMode, original.synthesisMode);
      expect(updated.showBufferIndicator, original.showBufferIndicator);
      expect(updated.compressOnSynthesize, original.compressOnSynthesize);
    });

    test('copyWith with no arguments returns equivalent state', () {
      const original = SettingsState(
        darkMode: true,
        selectedVoice: 'piper-voice-1',
        autoAdvanceChapters: false,
        defaultPlaybackRate: 2.0,
        smartSynthesisEnabled: false,
        cacheQuotaGB: 1.0,
        showBookCoverBackground: false,
        hapticFeedbackEnabled: false,
        synthesisMode: SynthesisMode.performance,
        showBufferIndicator: false,
        compressOnSynthesize: false,
      );
      
      final copied = original.copyWith();
      
      expect(copied.darkMode, original.darkMode);
      expect(copied.selectedVoice, original.selectedVoice);
      expect(copied.autoAdvanceChapters, original.autoAdvanceChapters);
      expect(copied.defaultPlaybackRate, original.defaultPlaybackRate);
      expect(copied.smartSynthesisEnabled, original.smartSynthesisEnabled);
      expect(copied.cacheQuotaGB, original.cacheQuotaGB);
      expect(copied.showBookCoverBackground, original.showBookCoverBackground);
      expect(copied.hapticFeedbackEnabled, original.hapticFeedbackEnabled);
      expect(copied.synthesisMode, original.synthesisMode);
      expect(copied.showBufferIndicator, original.showBufferIndicator);
      expect(copied.compressOnSynthesize, original.compressOnSynthesize);
    });
  });

  group('SynthesisMode', () {
    test('has three modes', () {
      expect(SynthesisMode.values.length, 3);
      expect(SynthesisMode.values, contains(SynthesisMode.auto));
      expect(SynthesisMode.values, contains(SynthesisMode.performance));
      expect(SynthesisMode.values, contains(SynthesisMode.efficiency));
    });

    test('enum names are correct for persistence', () {
      expect(SynthesisMode.auto.name, 'auto');
      expect(SynthesisMode.performance.name, 'performance');
      expect(SynthesisMode.efficiency.name, 'efficiency');
    });
  });

  group('SettingsState edge cases', () {
    test('copyWith handles all synthesis modes', () {
      const state = SettingsState();
      
      final autoMode = state.copyWith(synthesisMode: SynthesisMode.auto);
      final perfMode = state.copyWith(synthesisMode: SynthesisMode.performance);
      final effMode = state.copyWith(synthesisMode: SynthesisMode.efficiency);
      
      expect(autoMode.synthesisMode, SynthesisMode.auto);
      expect(perfMode.synthesisMode, SynthesisMode.performance);
      expect(effMode.synthesisMode, SynthesisMode.efficiency);
    });

    test('playback rate can be set to various values', () {
      const state = SettingsState();
      
      final slow = state.copyWith(defaultPlaybackRate: 0.5);
      final normal = state.copyWith(defaultPlaybackRate: 1.0);
      final fast = state.copyWith(defaultPlaybackRate: 2.0);
      
      expect(slow.defaultPlaybackRate, 0.5);
      expect(normal.defaultPlaybackRate, 1.0);
      expect(fast.defaultPlaybackRate, 2.0);
    });

    test('cache quota accepts boundary values', () {
      const state = SettingsState();
      
      final minQuota = state.copyWith(cacheQuotaGB: 0.5);
      final maxQuota = state.copyWith(cacheQuotaGB: 4.0);
      
      expect(minQuota.cacheQuotaGB, 0.5);
      expect(maxQuota.cacheQuotaGB, 4.0);
    });
  });
}
