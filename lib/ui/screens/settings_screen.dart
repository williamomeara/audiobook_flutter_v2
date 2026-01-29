import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:playback/playback.dart';
import 'package:tts_engines/tts_engines.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/granular_download_manager.dart';
import '../../app/playback_providers.dart';
import '../../app/settings_controller.dart';
import '../../app/voice_preview_service.dart';
import '../theme/app_colors.dart';
import '../widgets/synthesis_mode_picker.dart';
import 'package:core_domain/core_domain.dart';

/// Provider for app package info
final packageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return PackageInfo.fromPlatform();
});

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
                          label: 'Auto-advance chapters',
                          subLabel: 'Automatically move to next chapter',
                          trailing: Switch(
                            value: settings.autoAdvanceChapters,
                            onChanged: ref.read(settingsProvider.notifier).setAutoAdvanceChapters,
                          ),
                        ),
                        const Divider(height: 1),
                        _SettingsRow(
                          label: 'Haptic feedback',
                          subLabel: 'Vibration for playback controls',
                          trailing: Switch(
                            value: settings.hapticFeedbackEnabled,
                            onChanged: ref.read(settingsProvider.notifier).setHapticFeedbackEnabled,
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

                    // Synthesis Mode section (Phase 7: Auto-calibration)
                    _SectionCard(
                      title: 'Synthesis',
                      children: [
                        const SynthesisModePicker(),
                        const Divider(height: 1),
                        _SettingsRow(
                          label: 'Show buffer indicator',
                          subLabel: 'Display buffer status during playback',
                          trailing: Switch(
                            value: settings.showBufferIndicator,
                            onChanged: ref.read(settingsProvider.notifier).setShowBufferIndicator,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Storage section (Phase 3: Cache management)
                    _SectionCard(
                      title: 'Storage',
                      children: [
                        _SettingsRow(
                          label: 'Compress synthesized audio',
                          subLabel: 'Automatically compress audio (saves ~90% space)',
                          trailing: Switch(
                            value: settings.compressOnSynthesize,
                            onChanged: ref.read(settingsProvider.notifier).setCompressOnSynthesize,
                          ),
                        ),
                        const Divider(height: 1),
                        _CacheStorageRow(colors: colors),
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
                    const SizedBox(height: 20),

                    // About section (merged)
                    _SectionCard(
                      title: 'About',
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Éist',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: colors.text,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Ebook/PDF to Audiobook',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Consumer(
                                builder: (context, ref, _) {
                                  final packageInfo = ref.watch(packageInfoProvider);
                                  return packageInfo.when(
                                    data: (info) => Text(
                                      'Version ${info.version} (${info.buildNumber})',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textTertiary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    loading: () => Text(
                                      'Version ...',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textTertiary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    error: (_, __) => Text(
                                      'Version unknown',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textTertiary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '"Éist" means "listen" in Irish 🇮🇪',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: colors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Consumer(
                          builder: (context, ref, _) {
                            final packageInfo = ref.watch(packageInfoProvider);
                            final version = packageInfo.maybeWhen(
                              data: (info) => info.version,
                              orElse: () => '1.0.0',
                            );
                            return _SettingsRow(
                              label: 'Open Source Licenses',
                              trailing: Icon(Icons.chevron_right, color: colors.textTertiary),
                              onTap: () => showLicensePage(
                                context: context,
                                applicationName: 'Éist',
                                applicationVersion: version,
                                applicationLegalese: '© 2025 Éist',
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        _SettingsRow(
                          label: 'Privacy Policy',
                          trailing: Icon(Icons.chevron_right, color: colors.textTertiary),
                          onTap: () => _showPrivacyPolicy(context),
                        ),
                        const Divider(height: 1),
                        _SettingsRow(
                          label: 'TTS Model Credits',
                          subLabel: 'Voice synthesis attributions',
                          trailing: Icon(Icons.chevron_right, color: colors.textTertiary),
                          onTap: () => _showTtsCredits(context),
                        ),
                        const Divider(height: 1),
                        _SettingsRow(
                          label: 'Project Gutenberg',
                          subLabel: 'Free ebook library attribution',
                          trailing: Icon(Icons.open_in_new, color: colors.textTertiary),
                          onTap: () async {
                            final url = Uri.parse('https://www.gutenberg.org/');
                            try {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
                            } catch (e) {
                              // Ignore errors - URL might still have opened
                            }
                          },
                        ),
                        const Divider(height: 1),
                        _SettingsRow(
                          label: 'Send Feedback',
                          subLabel: 'Report bugs or suggest features',
                          trailing: Icon(Icons.open_in_new, color: colors.textTertiary),
                          onTap: () => _showFeedbackDialog(context),
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
    if (voiceId == VoiceIds.none) return 'None - Download a voice';
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

  void _showPrivacyPolicy(BuildContext context) {
    final colors = context.appColors;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('Privacy Policy', style: TextStyle(color: colors.text)),
        content: SingleChildScrollView(
          child: Text(
            '''Éist Privacy Policy

Last updated: January 2025

Data Collection
Éist does not collect, store, or transmit any personal data. All your books, reading progress, and settings are stored locally on your device only.

Third-Party Services
• TTS voice models are downloaded from public repositories (GitHub, HuggingFace)
• Free books are fetched from Project Gutenberg
• No analytics or tracking services are used

Permissions
• Storage: To access and store your ebook files
• Internet: To download voice models and free books
• Vibration: For haptic feedback

Contact
For questions about this privacy policy, please open an issue on our GitHub repository.''',
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: colors.accent)),
          ),
        ],
      ),
    );
  }

  void _showTtsCredits(BuildContext context) {
    final colors = context.appColors;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('TTS Model Credits', style: TextStyle(color: colors.text)),
        content: SingleChildScrollView(
          child: Text(
            '''Voice Synthesis Attributions

Kokoro TTS
High-quality neural TTS model.
License: Apache 2.0
Repository: github.com/hexgrad/kokoro

Piper TTS
Fast, local neural text-to-speech.
License: MIT
Repository: github.com/rhasspy/piper

Supertonic
Multi-speaker TTS model collection.
License: Various (see model cards)
Source: HuggingFace

ONNX Runtime
Neural network inference engine.
License: MIT
Repository: github.com/microsoft/onnxruntime

Special thanks to all the open-source contributors who make these incredible voice models freely available.''',
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: colors.accent)),
          ),
        ],
      ),
    );
  }

  void _showFeedbackDialog(BuildContext context) {
    final colors = context.appColors;
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    String feedbackType = 'bug';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: colors.card,
          title: Text('Send Feedback', style: TextStyle(color: colors.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Type', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'bug', label: Text('Bug'), icon: Icon(Icons.bug_report)),
                    ButtonSegment(value: 'feature', label: Text('Feature'), icon: Icon(Icons.lightbulb)),
                  ],
                  selected: {feedbackType},
                  onSelectionChanged: (selected) => setState(() => feedbackType = selected.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  style: TextStyle(color: colors.text),
                  decoration: InputDecoration(
                    labelText: 'Subject',
                    labelStyle: TextStyle(color: colors.textSecondary),
                    hintText: feedbackType == 'bug' ? 'Brief description of the bug' : 'Feature you want to suggest',
                    hintStyle: TextStyle(color: colors.textTertiary),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: colors.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: bodyController,
                  style: TextStyle(color: colors.text),
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Details',
                    labelStyle: TextStyle(color: colors.textSecondary),
                    hintText: feedbackType == 'bug' 
                        ? 'Steps to reproduce, what happened, what you expected...'
                        : 'Describe the feature and why it would be useful...',
                    hintStyle: TextStyle(color: colors.textTertiary),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: colors.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
            ),
            TextButton(
              onPressed: () async {
                final title = titleController.text.trim();
                final body = bodyController.text.trim();
                if (title.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please enter a subject')),
                  );
                  return;
                }
                
                final prefix = feedbackType == 'bug' ? '[Bug] ' : '[Feature Request] ';
                final subject = prefix + title;
                final fullBody = body.isNotEmpty ? body : 'No additional details provided.';
                
                // Get device/app info
                final packageInfo = await PackageInfo.fromPlatform();
                final deviceInfo = '''

---
App: Éist v${packageInfo.version} (${packageInfo.buildNumber})
Sent via in-app feedback''';
                
                final emailUrl = Uri(
                  scheme: 'mailto',
                  path: 'williamomeara@proton.me',
                  query: 'subject=${Uri.encodeComponent(subject)}'
                      '&body=${Uri.encodeComponent(fullBody + deviceInfo)}',
                );
                
                if (!context.mounted) return;
                Navigator.pop(context);
                
                try {
                  await launchUrl(emailUrl);
                } catch (e) {
                  // Dialog already closed, can't show snackbar reliably
                }
              },
              child: Text('Send Email', style: TextStyle(color: colors.accent)),
            ),
          ],
        ),
      ),
    );
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
  });

  final String name;
  final String voiceId;

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


/// Cache storage settings with quota slider and usage display.
class _CacheStorageRow extends ConsumerStatefulWidget {
  const _CacheStorageRow({required this.colors});

  final AppThemeColors colors;

  @override
  ConsumerState<_CacheStorageRow> createState() => _CacheStorageRowState();
}

class _CacheStorageRowState extends ConsumerState<_CacheStorageRow> {
  @override
  void initState() {
    super.initState();
    // Refresh cache stats when this widget is first displayed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(cacheUsageStatsProvider);
    });
  }

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
            value: settings.cacheQuotaGB.clamp(0.5, 4.0),
            min: 0.5,
            max: 4.0,
            divisions: 7, // 0.5 GB steps: 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0
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
          
          // Compress cache button
          TextButton.icon(
            onPressed: () => _showCompressCacheDialog(),
            icon: Icon(Icons.compress, color: widget.colors.primary, size: 18),
            label: Text(
              'Compress Audio Cache',
              style: TextStyle(color: widget.colors.primary),
            ),
          ),
          
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
        if (stats.compressedCount > 0 || stats.uncompressedCount > 0)
          Text(
            '${stats.compressedCount} compressed, ${stats.uncompressedCount} uncompressed',
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
    final colors = context.appColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title with icon
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Clear Audio Cache?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Content
              Text(
                'This will delete all cached audio files. '
                'Audio will need to be synthesized again when playing books.',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: colors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade400,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Clear',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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

  Future<void> _showCompressCacheDialog() async {
    final colors = context.appColors;
    
    // Get cache stats first
    CacheCompressionStats? stats;
    try {
      final manager = await ref.read(intelligentCacheManagerProvider.future);
      final service = AacCompressionService();
      stats = await CacheCompressionStats.fromDirectory(manager.directory, service);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get cache stats: $e')),
        );
      }
      return;
    }

    if (!stats.canCompress) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No uncompressed audio to compress')),
        );
      }
      return;
    }

    if (!mounted) return;

    // Capture stats for closure (already verified non-null above)
    final cacheStats = stats;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.compress,
                size: 48,
                color: colors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Compress Audio Cache?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${cacheStats.uncompressedFiles} files can be compressed.\n'
                'Estimated savings: ${cacheStats.formattedEstimatedSavings}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Compressed audio plays normally with no quality loss.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Compress',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      await _compressCache();
    }
  }

  Future<void> _compressCache() async {
    final colors = context.appColors;
    
    // Show progress dialog with real-time updates
    bool isCancelled = false;
    bool runningInBackground = false;
    
    // Create a ValueNotifier to trigger dialog updates
    final progressNotifier = ValueNotifier<(int, int)>((0, 0));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ValueListenableBuilder<(int, int)>(
            valueListenable: progressNotifier,
            builder: (context, progress, child) {
              final (done, count) = progress;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Show determinate progress if we know the total
                  if (count > 0)
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        value: done / count,
                        strokeWidth: 4,
                        backgroundColor: colors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                      ),
                    )
                  else
                    const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Compressing Audio Cache',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    count > 0 ? '$done of $count files' : 'Analyzing cache...',
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${(done / count * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: done / count,
                        minHeight: 6,
                        backgroundColor: colors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Action buttons row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Cancel button
                      TextButton(
                        onPressed: () {
                          isCancelled = true;
                          Navigator.pop(dialogContext);
                        },
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: Colors.red.shade400),
                        ),
                      ),
                      // Run in Background button
                      TextButton.icon(
                        onPressed: () {
                          runningInBackground = true;
                          Navigator.pop(dialogContext);
                          // Show snackbar indicating background operation
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(child: Text('Compressing in background...')),
                                ],
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: Icon(Icons.play_circle_outline, size: 18, color: colors.primary),
                        label: Text(
                          'Background',
                          style: TextStyle(color: colors.primary),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    try {
      final manager = await ref.read(intelligentCacheManagerProvider.future);
      final service = AacCompressionService();

      // Pass storage to enable DB-first compression workflow
      final result = await service.compressDirectory(
        manager.storage,  // ✅ Pass storage for metadata updates
        manager.directory,
        onProgress: (done, count) {
          // Update the dialog via ValueNotifier
          progressNotifier.value = (done, count);
        },
        shouldCancel: () => isCancelled,
      );

      // Dispose notifier
      progressNotifier.dispose();

      // Close progress dialog only if not running in background
      if (mounted && !runningInBackground && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      ref.invalidate(cacheUsageStatsProvider);

      if (mounted && !isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Compressed ${result.filesCompressed} files, saved ${result.formattedSavings}',
            ),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      progressNotifier.dispose();
      
      // Close progress dialog only if not running in background
      if (mounted && !runningInBackground && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted && !runningInBackground) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Compression failed: $e')),
        );
      }
    }
  }
}

