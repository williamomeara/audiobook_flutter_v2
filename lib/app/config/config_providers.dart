import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'runtime_playback_config.dart';
import 'system_channel.dart';

export 'runtime_playback_config.dart';
export 'system_channel.dart';

/// Provider for runtime playback configuration.
///
/// This provider manages the runtime-configurable playback settings,
/// including persistence to SQLite.
///
/// Usage:
/// ```dart
/// // Read current config
/// final config = ref.watch(runtimePlaybackConfigProvider).value;
///
/// // Update config
/// await ref.read(runtimePlaybackConfigProvider.notifier).updateConfig(
///   (current) => current.copyWith(prefetchMode: PrefetchMode.aggressive),
/// );
///
/// // Reset to defaults
/// await ref.read(runtimePlaybackConfigProvider.notifier).reset();
/// ```
final runtimePlaybackConfigProvider =
    AsyncNotifierProvider<RuntimePlaybackConfigNotifier, RuntimePlaybackConfig>(
  RuntimePlaybackConfigNotifier.new,
);

/// Notifier for managing runtime playback configuration state.
class RuntimePlaybackConfigNotifier
    extends AsyncNotifier<RuntimePlaybackConfig> {
  @override
  Future<RuntimePlaybackConfig> build() async {
    return RuntimePlaybackConfig.load();
  }

  /// Update configuration using a transformation function.
  ///
  /// The transformation receives the current config and should return
  /// the modified config. Changes are automatically persisted.
  ///
  /// Example:
  /// ```dart
  /// await ref.read(runtimePlaybackConfigProvider.notifier).updateConfig(
  ///   (config) => config.copyWith(cacheBudgetMB: 1024),
  /// );
  /// ```
  Future<void> updateConfig(
    RuntimePlaybackConfig Function(RuntimePlaybackConfig current) updater,
  ) async {
    final current = state.value ?? RuntimePlaybackConfig();
    final updated = updater(current);

    // Only save if actually changed
    if (updated != current) {
      await updated.save();
      state = AsyncValue.data(updated);
    }
  }

  /// Update a single setting without affecting others.
  ///
  /// Convenience method for updating individual settings.
  Future<void> setCacheBudgetMB(int? budgetMB) async {
    await updateConfig((config) => config.copyWith(cacheBudgetMB: budgetMB));
  }

  /// Update cache max age in days.
  Future<void> setCacheMaxAgeDays(int? days) async {
    await updateConfig((config) => config.copyWith(cacheMaxAgeDays: days));
  }

  /// Update prefetch mode.
  Future<void> setPrefetchMode(PrefetchMode mode) async {
    await updateConfig((config) => config.copyWith(prefetchMode: mode));
  }

  /// Update resume delay.
  Future<void> setResumeDelayMs(int delayMs) async {
    await updateConfig((config) => config.copyWith(resumeDelayMs: delayMs));
  }

  /// Update rate-independent synthesis setting.
  Future<void> setRateIndependentSynthesis(bool enabled) async {
    await updateConfig(
        (config) => config.copyWith(rateIndependentSynthesis: enabled));
  }

  /// Reset configuration to defaults.
  ///
  /// Clears all customizations and saves the default configuration.
  Future<void> reset() async {
    final defaults = RuntimePlaybackConfig();
    await defaults.save();
    state = AsyncValue.data(defaults);
    developer.log(
      'RuntimePlaybackConfig: Reset to defaults',
      name: 'RuntimePlaybackConfigNotifier',
    );
  }

  /// Auto-configure cache budget based on available storage.
  ///
  /// This is a placeholder that should be called with actual storage
  /// information from the platform. The cache manager will provide
  /// the auto-configuration logic.
  Future<void> autoConfigure({
    required int availableStorageBytes,
    required int currentCacheSizeBytes,
  }) async {
    // Calculate suggested budget: 10% of free space, clamped to 100 MB - 4 GB
    var suggestedMB = availableStorageBytes ~/ (10 * 1024 * 1024);
    suggestedMB = suggestedMB.clamp(100, 4096);

    // If current cache is larger than suggested but not by much, keep it
    final currentCacheMB = currentCacheSizeBytes ~/ (1024 * 1024);
    if (currentCacheMB > suggestedMB && currentCacheMB < suggestedMB * 2) {
      suggestedMB = currentCacheMB;
    }

    developer.log(
      'RuntimePlaybackConfig: Auto-configured cache to $suggestedMB MB '
      '(available: ${availableStorageBytes ~/ (1024 * 1024)} MB)',
      name: 'RuntimePlaybackConfigNotifier',
    );

    await updateConfig((config) => config.copyWith(cacheBudgetMB: suggestedMB));
  }
}

/// Convenience provider for accessing just the prefetch mode.
///
/// Useful for widgets that only care about prefetch mode.
final prefetchModeProvider = Provider<PrefetchMode>((ref) {
  final config = ref.watch(runtimePlaybackConfigProvider).value;
  return config?.prefetchMode ?? PrefetchMode.adaptive;
});

/// Convenience provider for checking if prefetch is enabled.
final isPrefetchEnabledProvider = Provider<bool>((ref) {
  final mode = ref.watch(prefetchModeProvider);
  return mode != PrefetchMode.off;
});

/// Convenience provider for the effective resume delay.
final resumeDelayProvider = Provider<Duration>((ref) {
  final config = ref.watch(runtimePlaybackConfigProvider).value;
  return config?.effectiveResumeDelay ?? const Duration(milliseconds: 500);
});

// ═══════════════════════════════════════════════════════════════════════════
// System Channel Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the system channel singleton.
///
/// Initializes the channel on first access and provides access to
/// memory pressure events and storage information.
final systemChannelProvider = Provider<SystemChannel>((ref) {
  final channel = SystemChannel.instance;
  channel.initialize();
  ref.onDispose(() => channel.dispose());
  return channel;
});

/// Provider for memory pressure events.
///
/// Streams memory pressure levels from the platform.
/// Use this to trigger cache eviction or reduce prefetch aggressiveness.
final memoryPressureProvider = StreamProvider<MemoryPressure>((ref) {
  final channel = ref.watch(systemChannelProvider);
  return channel.memoryPressure;
});

/// Provider for storage information.
///
/// Fetches current storage stats from the platform.
/// Use this for cache auto-configuration.
final storageInfoProvider = FutureProvider<StorageInfo>((ref) async {
  final channel = ref.watch(systemChannelProvider);
  return channel.getStorageInfo();
});

