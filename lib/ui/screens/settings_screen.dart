import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playback/playback.dart';
import 'package:tts_engines/tts_engines.dart';

import '../../app/granular_download_manager.dart';
import '../../app/playback_providers.dart';
import '../../app/settings_controller.dart';
import '../../app/tts_providers.dart';
import '../../app/voice_preview_service.dart';
import '../theme/app_colors.dart';
import 'package:core_domain/core_domain.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: colors.backgroundSecondary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.headerBackground,
                border: Border(bottom: BorderSide(color: colors.border, width: 1)),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => context.pop(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.chevron_left, color: colors.text),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Appearance section
                    _SectionCard(
                      title: 'Appearance',
                      children: [
                        _SettingsRow(
                          label: 'Dark mode',
                          subLabel: 'Use dark theme',
                          trailing: Switch(
                            value: settings.darkMode,
                            onChanged: ref.read(settingsProvider.notifier).setDarkMode,
                          ),
                        ),
                        const Divider(height: 1),
                        _SettingsRow(
                          label: 'Book cover background',
                          subLabel: 'Show cover art behind text in playback',
                          trailing: Switch(
                            value: settings.showBookCoverBackground,
                            onChanged: ref.read(settingsProvider.notifier).setShowBookCoverBackground,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Voice section
                    _SectionCard(
                      title: 'Voice',
                      children: [
                        _SettingsRow(
                          label: 'Selected voice',
                          subLabel: _voiceDisplayName(settings.selectedVoice),
                          trailing: Icon(Icons.chevron_right, color: colors.textTertiary),
                          onTap: () => _showVoicePicker(context, ref),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Voice Downloads section
                    _SectionCard(
                      title: 'Voice Downloads',
                      children: [
                        _SettingsRow(
                          label: 'Manage Voice Downloads',
                          subLabel: 'Download and manage voice models',
                          trailing: Icon(Icons.chevron_right, color: colors.textTertiary),
                          onTap: () => context.push('/settings/downloads'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Playback section
                    _SectionCard(
                      title: 'Playback',
                      children: [
                        _SettingsRow(
                          label: 'Smart synthesis',
                          subLabel: 'Pre-synthesize audio for instant playback',
                          trailing: Switch(
                            value: settings.smartSynthesisEnabled,
                            onChanged: ref.read(settingsProvider.notifier).setSmartSynthesisEnabled,
                          ),
                        ),
                        const Divider(height: 1),
                        _SettingsRow(
                          label: 'Auto-advance chapters',
                          subLabel: 'Automatically move to next chapter',
                          trailing: Switch(
                            value: settings.autoAdvanceChapters,
                            onChanged: ref.read(settingsProvider.notifier).setAutoAdvanceChapters,
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Default playback rate',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: colors.text,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Slider(
                                value: settings.defaultPlaybackRate,
                                min: 0.5,
                                max: 3.0,
                                divisions: 10,
                                label: '${settings.defaultPlaybackRate.toStringAsFixed(2)}x',
                                onChanged: ref.read(settingsProvider.notifier).setDefaultPlaybackRate,
                                activeColor: colors.primary,
                              ),
                              Center(
                                child: Text(
                                  '${settings.defaultPlaybackRate.toStringAsFixed(2)}x',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Engine Optimization section (Phase 4: Auto-tuning)
                    _SectionCard(
                      title: 'Engine Optimization',
                      children: [
                        _EngineOptimizationRow(colors: colors),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Storage section (Phase 3: Cache management)
                    _SectionCard(
                      title: 'Storage',
                      children: [
                        _CacheStorageRow(colors: colors),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // About section
                    _SectionCard(
                      title: 'About',
                      children: [
                        _SettingsRow(
                          label: 'Version',
                          trailing: Text(
                            '1.0.0',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Developer section
                    _SectionCard(
                      title: 'Developer',
                      children: [
                        _SettingsRow(
                          label: 'Developer Options',
                          subLabel: 'TTS testing and diagnostics',
                          trailing: Icon(Icons.chevron_right, color: colors.textTertiary),
                          onTap: () => context.push('/settings/developer'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _voiceDisplayName(String voiceId) {
    if (voiceId == VoiceIds.device) return 'Device TTS';
    if (VoiceIds.isKokoro(voiceId)) {
      final parts = voiceId.replaceFirst('kokoro_', '').split('_');
      final prefix = parts[0].toUpperCase();
      final name = parts.length > 1
          ? parts.sublist(1).map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w).join(' ')
          : 'Default';
      return 'Kokoro $prefix $name';
    }
    if (VoiceIds.isSupertonic(voiceId)) {
      final suffix = voiceId.replaceFirst('supertonic_', '');
      final isMale = suffix.startsWith('m');
      final num = suffix.substring(1);
      return 'Supertonic ${isMale ? 'Male' : 'Female'} $num';
    }
    if (VoiceIds.isPiper(voiceId)) {
      final key = VoiceIds.piperModelKey(voiceId);
      return 'Piper ${key ?? voiceId}';
    }
    return voiceId;
  }

  void _showVoicePicker(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Consumer(
              builder: (context, ref, _) {
                final downloadState = ref.watch(granularDownloadManagerProvider);
                
                // Get ready voice IDs
                final readyVoiceIds = downloadState.maybeWhen(
                  data: (state) => state.readyVoices.map((v) => v.voiceId).toSet(),
                  orElse: () => <String>{},
                );
                
                // Filter voices by engine to only include downloaded ones
                final readyKokoroVoices = VoiceIds.kokoroVoices
                    .where((id) => readyVoiceIds.contains(id))
                    .toList();
                final readyPiperVoices = VoiceIds.piperVoices
                    .where((id) => readyVoiceIds.contains(id))
                    .toList();
                final readySupertonicVoices = VoiceIds.supertonicVoices
                    .where((id) => readyVoiceIds.contains(id))
                    .toList();
                
                final hasNoDownloadedVoices = readyKokoroVoices.isEmpty &&
                    readyPiperVoices.isEmpty &&
                    readySupertonicVoices.isEmpty;
                
                return Column(
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
                        'Select Voice',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                    ),
                    Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        // Device TTS - disabled until implemented
                        // _VoiceOption(
                        //   name: 'Device TTS',
                        //   description: 'Uses your device\'s built-in voice',
                        //   voiceId: VoiceIds.device,
                        // ),
                        // Piper voices first (fastest engine)
                        if (readyPiperVoices.isNotEmpty) ...[
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text(
                              'Piper Voices',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                          for (final voiceId in readyPiperVoices)
                            _VoiceOption(
                              name: _voiceDisplayName(voiceId),
                              voiceId: voiceId,
                            ),
                        ],
                        // Supertonic voices second
                        if (readySupertonicVoices.isNotEmpty) ...[
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text(
                              'Supertonic Voices',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                          for (final voiceId in readySupertonicVoices)
                            _VoiceOption(
                              name: _voiceDisplayName(voiceId),
                              voiceId: voiceId,
                            ),
                        ],
                        // Kokoro voices last (slowest, requires flagship device)
                        if (readyKokoroVoices.isNotEmpty) ...[
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Kokoro Voices',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded,
                                        size: 14, color: Colors.orange.shade700),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'High quality but slow. Requires a modern flagship device.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          for (final voiceId in readyKokoroVoices)
                            _VoiceOption(
                              name: _voiceDisplayName(voiceId),
                              voiceId: voiceId,
                            ),
                        ],
                        // Link to download more voices
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              context.push('/settings/downloads');
                            },
                            icon: Icon(Icons.download, color: colors.primary),
                            label: Text(
                              hasNoDownloadedVoices
                                  ? 'Download Voices to Get Started'
                                  : 'Download More Voices',
                              style: TextStyle(color: colors.primary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    this.subLabel,
    this.trailing,
    this.onTap,
  });

  final String label;
  final String? subLabel;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: colors.text,
                    ),
                  ),
                  if (subLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subLabel!,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _VoiceOption extends ConsumerStatefulWidget {
  const _VoiceOption({
    required this.name,
    required this.voiceId,
    this.description,
  });

  final String name;
  final String voiceId;
  final String? description;

  @override
  ConsumerState<_VoiceOption> createState() => _VoiceOptionState();
}

class _VoiceOptionState extends ConsumerState<_VoiceOption> {
  bool _hasPreview = false;

  @override
  void initState() {
    super.initState();
    _checkPreviewAvailability();
  }

  Future<void> _checkPreviewAvailability() async {
    final hasPreview = await ref.read(voicePreviewProvider.notifier).hasPreview(widget.voiceId);
    if (mounted) {
      setState(() => _hasPreview = hasPreview);
    }
  }

  Future<void> _togglePreview() async {
    final notifier = ref.read(voicePreviewProvider.notifier);
    final currentlyPlaying = ref.read(voicePreviewProvider);
    
    if (currentlyPlaying == widget.voiceId) {
      await notifier.stop();
    } else {
      await notifier.playPreview(widget.voiceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final settings = ref.watch(settingsProvider);
    final isSelected = settings.selectedVoice == widget.voiceId;
    
    // Watch the currently playing preview to reactively update UI
    final currentlyPlaying = ref.watch(voicePreviewProvider);
    final isPlaying = currentlyPlaying == widget.voiceId;
    
    return InkWell(
      onTap: () {
        // Stop any playing preview before selecting
        ref.read(voicePreviewProvider.notifier).stop();
        ref.read(settingsProvider.notifier).setSelectedVoice(widget.voiceId);
        Navigator.of(context).pop();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // Preview button - wrapped in GestureDetector to prevent tap propagation
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _hasPreview ? _togglePreview : null,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  isPlaying ? Icons.stop_circle : Icons.play_circle_outline,
                  size: 28,
                  color: isPlaying 
                      ? colors.primary 
                      : (_hasPreview ? colors.textSecondary : colors.textTertiary),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Voice name and description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.name, style: TextStyle(color: colors.text, fontSize: 16)),
                  if (widget.description != null)
                    Text(
                      widget.description!,
                      style: TextStyle(color: colors.textSecondary, fontSize: 14),
                    ),
                ],
              ),
            ),
            // Selection checkmark
            if (isSelected)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.check_circle, color: colors.primary),
              ),
          ],
        ),
      ),
    );
  }
}

/// Engine optimization settings row with device profiling.
class _EngineOptimizationRow extends ConsumerStatefulWidget {
  const _EngineOptimizationRow({required this.colors});

  final AppThemeColors colors;

  @override
  ConsumerState<_EngineOptimizationRow> createState() => _EngineOptimizationRowState();
}

class _EngineOptimizationRowState extends ConsumerState<_EngineOptimizationRow> {
  bool _isOptimizing = false;
  String? _lastResult;
  int _progress = 0;
  int _total = 0;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final voiceId = settings.selectedVoice;
    final configManager = ref.watch(engineConfigManagerProvider);

    // Get engine type from voice - profiling is per-engine, not per-voice
    final engineType = VoiceIds.engineFor(voiceId);
    final engineId = engineType.name;
    final engineDisplayName = _getEngineDisplayName(engineType);
    
    return FutureBuilder<DeviceEngineConfig?>(
      future: configManager.loadConfig(engineId),
      builder: (context, snapshot) {
        final config = snapshot.data;
        final hasBeenOptimized = config?.tunedAt != null;
        
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Optimize: $engineDisplayName',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: widget.colors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getStatusText(hasBeenOptimized, config, engineDisplayName),
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isOptimizing)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _total > 0 ? _progress / _total : null,
                        color: widget.colors.primary,
                      ),
                    )
                  else
                    TextButton(
                      onPressed: () => _runOptimization(voiceId),
                      child: Text(
                        hasBeenOptimized ? 'Re-optimize' : 'Optimize',
                        style: TextStyle(color: widget.colors.primary),
                      ),
                    ),
                ],
              ),
              if (_lastResult != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.colors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: widget.colors.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lastResult!,
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.colors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (hasBeenOptimized && config != null) ...[
                const SizedBox(height: 12),
                _buildConfigDetails(config),
              ],
            ],
          ),
        );
      },
    );
  }

  String _getEngineDisplayName(EngineType engineType) {
    switch (engineType) {
      case EngineType.piper:
        return 'Piper';
      case EngineType.kokoro:
        return 'Kokoro';
      case EngineType.supertonic:
        return 'Supertonic';
      case EngineType.device:
        return 'Device TTS';
    }
  }

  String _getStatusText(bool hasBeenOptimized, DeviceEngineConfig? config, String engineName) {
    if (_isOptimizing) {
      return 'Running optimization test ($_progress/$_total)...';
    }
    if (!hasBeenOptimized) {
      return 'Optimize $engineName engine for your device';
    }
    final tunedAt = config?.tunedAt;
    if (tunedAt != null) {
      final daysAgo = DateTime.now().difference(tunedAt).inDays;
      final tierName = _getTierDisplayName(config!.deviceTier);
      if (daysAgo == 0) {
        return 'Optimized today • $tierName performance';
      }
      return 'Optimized $daysAgo days ago • $tierName performance';
    }
    return 'Optimized for $engineName';
  }

  String _getTierDisplayName(DevicePerformanceTier tier) {
    switch (tier) {
      case DevicePerformanceTier.flagship:
        return 'Excellent';
      case DevicePerformanceTier.midRange:
        return 'Good';
      case DevicePerformanceTier.budget:
        return 'Moderate';
      case DevicePerformanceTier.legacy:
        return 'Limited';
    }
  }

  Widget _buildConfigDetails(DeviceEngineConfig config) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _buildChip('RTF: ${config.measuredRTF.toStringAsFixed(2)}x'),
        _buildChip('Prefetch: ${config.prefetchWindowSize} segments'),
        if (config.prefetchConcurrency > 1)
          _buildChip('Parallel: ${config.prefetchConcurrency}x'),
      ],
    );
  }

  Widget _buildChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: widget.colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.colors.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: widget.colors.textSecondary,
        ),
      ),
    );
  }

  Future<void> _runOptimization(String voiceId) async {
    setState(() {
      _isOptimizing = true;
      _lastResult = null;
      _progress = 0;
      _total = 0;
    });

    try {
      final engine = await ref.read(ttsRoutingEngineProvider.future);
      final profiler = ref.read(deviceProfilerProvider);
      final configManager = ref.read(engineConfigManagerProvider);
      final playbackRate = ref.read(settingsProvider).defaultPlaybackRate;

      final profile = await profiler.profileEngine(
        engine: engine,
        voiceId: voiceId,
        playbackRate: playbackRate,
        onProgress: (current, total) {
          setState(() {
            _progress = current;
            _total = total;
          });
        },
      );

      final config = profiler.createConfigFromProfile(profile);
      await configManager.saveConfig(config);

      setState(() {
        _lastResult = 'Detected ${config.deviceTier.name.toUpperCase()} device '
            '(RTF: ${profile.rtf.toStringAsFixed(2)}x)';
      });
    } catch (e) {
      setState(() {
        _lastResult = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Optimization failed: $e')),
        );
      }
    } finally {
      setState(() {
        _isOptimizing = false;
      });
    }
  }
}

/// Cache storage settings with quota slider and usage display.
class _CacheStorageRow extends ConsumerStatefulWidget {
  const _CacheStorageRow({required this.colors});

  final AppThemeColors colors;

  @override
  ConsumerState<_CacheStorageRow> createState() => _CacheStorageRowState();
}

class _CacheStorageRowState extends ConsumerState<_CacheStorageRow> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final cacheStats = ref.watch(cacheUsageStatsProvider);
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quota slider
          Text(
            'Audio cache limit',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: widget.colors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Maximum storage for synthesized audio',
            style: TextStyle(
              fontSize: 13,
              color: widget.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Slider(
            value: settings.cacheQuotaGB,
            min: 0.5,
            max: 10.0,
            divisions: 19, // 0.5 GB steps
            label: '${settings.cacheQuotaGB.toStringAsFixed(1)} GB',
            onChanged: (value) {
              ref.read(settingsProvider.notifier).setCacheQuotaGB(value);
              _updateCacheQuota(value);
            },
            activeColor: widget.colors.primary,
          ),
          Center(
            child: Text(
              '${settings.cacheQuotaGB.toStringAsFixed(1)} GB',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: widget.colors.text,
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Usage display
          cacheStats.when(
            data: (stats) => _buildUsageDisplay(stats),
            loading: () => const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (e, _) => Text(
              'Failed to load cache stats',
              style: TextStyle(color: widget.colors.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          
          // Clear cache button
          TextButton.icon(
            onPressed: () => _showClearCacheDialog(),
            icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 18),
            label: Text(
              'Clear Audio Cache',
              style: TextStyle(color: Colors.red.shade400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageDisplay(CacheUsageStats stats) {
    final usagePercent = stats.usagePercent;
    final isWarning = usagePercent > 90;
    final barColor = isWarning ? Colors.orange : widget.colors.primary;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Used: ${stats.totalSizeFormatted}',
              style: TextStyle(
                fontSize: 13,
                color: widget.colors.text,
              ),
            ),
            Text(
              'of ${stats.quotaSizeFormatted}',
              style: TextStyle(
                fontSize: 13,
                color: widget.colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: usagePercent / 100,
            minHeight: 8,
            backgroundColor: widget.colors.border,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${stats.entryCount} cached segments',
          style: TextStyle(
            fontSize: 12,
            color: widget.colors.textSecondary,
          ),
        ),
      ],
    );
  }

  Future<void> _updateCacheQuota(double quotaGB) async {
    try {
      final manager = await ref.read(intelligentCacheManagerProvider.future);
      await manager.setQuotaSettings(CacheQuotaSettings.fromGB(quotaGB));
      // Refresh stats
      ref.invalidate(cacheUsageStatsProvider);
    } catch (e) {
      // Ignore errors during quota update
    }
  }

  Future<void> _showClearCacheDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Audio Cache?'),
        content: const Text(
          'This will delete all cached audio files. '
          'Audio will need to be synthesized again when playing books.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Clear',
              style: TextStyle(color: Colors.red.shade400),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _clearCache();
    }
  }

  Future<void> _clearCache() async {
    try {
      final manager = await ref.read(intelligentCacheManagerProvider.future);
      await manager.clear();
      ref.invalidate(cacheUsageStatsProvider);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio cache cleared')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear cache: $e')),
        );
      }
    }
  }
}

