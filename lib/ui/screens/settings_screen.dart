import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/settings_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/voice_download_manager.dart';
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
                            activeColor: colors.primary,
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
                      children: const [
                        VoiceDownloadManager(),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Playback section
                    _SectionCard(
                      title: 'Playback',
                      children: [
                        _SettingsRow(
                          label: 'Auto-advance chapters',
                          subLabel: 'Automatically move to next chapter',
                          trailing: Switch(
                            value: settings.autoAdvanceChapters,
                            onChanged: ref.read(settingsProvider.notifier).setAutoAdvanceChapters,
                            activeColor: colors.primary,
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
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
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
                    _VoiceOption(
                      name: 'Device TTS',
                      description: 'Uses your device\'s built-in voice',
                      voiceId: VoiceIds.device,
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        'Kokoro Voices',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    for (final voiceId in VoiceIds.kokoroVoices)
                      _VoiceOption(
                        name: _voiceDisplayName(voiceId),
                        voiceId: voiceId,
                      ),
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
                    for (final voiceId in VoiceIds.piperVoices)
                      _VoiceOption(
                        name: _voiceDisplayName(voiceId),
                        voiceId: voiceId,
                      ),
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
                    for (final voiceId in VoiceIds.supertonicVoices)
                      _VoiceOption(
                        name: _voiceDisplayName(voiceId),
                        voiceId: voiceId,
                      ),
                  ],
                ),
              ),
            ],
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

class _VoiceOption extends ConsumerWidget {
  const _VoiceOption({
    required this.name,
    required this.voiceId,
    this.description,
  });

  final String name;
  final String voiceId;
  final String? description;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final settings = ref.watch(settingsProvider);
    final isSelected = settings.selectedVoice == voiceId;
    
    return ListTile(
      title: Text(name, style: TextStyle(color: colors.text)),
      subtitle: description != null
          ? Text(description!, style: TextStyle(color: colors.textSecondary))
          : null,
      trailing: isSelected
          ? Icon(Icons.check_circle, color: colors.primary)
          : null,
      onTap: () {
        ref.read(settingsProvider.notifier).setSelectedVoice(voiceId);
        Navigator.of(context).pop();
      },
    );
  }
}
