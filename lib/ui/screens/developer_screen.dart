import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/database/app_database.dart';
import '../../app/granular_download_manager.dart';
import '../../app/library_controller.dart';
import '../../app/playback_providers.dart';
import '../../app/settings_controller.dart';
import '../../app/tts_providers.dart';
import '../../utils/app_logger.dart';
import '../theme/app_colors.dart';
import 'package:core_domain/core_domain.dart';

/// Developer settings screen for testing TTS and audio playback.
class DeveloperScreen extends ConsumerStatefulWidget {
  const DeveloperScreen({super.key});

  @override
  ConsumerState<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends ConsumerState<DeveloperScreen> {
  final _textController = TextEditingController(
    text: 'Hello, this is a test of the text to speech engine.',
  );
  
  final AudioPlayer _testPlayer = AudioPlayer();
  
  bool _isSynthesizing = false;
  bool _isPlaying = false;
  bool _isReimporting = false;
  bool _isResettingDatabase = false;
  bool _isBenchmarking = false;
  bool _isGeneratingPreviews = false;
  String? _lastError;
  String? _lastAudioPath;
  int? _lastDurationMs;
  int? _lastFileSizeBytes;
  Duration _synthesisTime = Duration.zero;
  String? _reimportMessage;
  String? _resetDatabaseMessage;
  String? _benchmarkResults;
  String? _previewGenerationMessage;

  @override
  void dispose() {
    _textController.dispose();
    _testPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final settings = ref.watch(settingsProvider);
    final downloadState = ref.watch(granularDownloadManagerProvider);

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
                    'Developer',
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
                    // Current Voice Info
                    _buildInfoCard(colors, settings, downloadState),
                    const SizedBox(height: 20),

                    // Voice Preview Generator (for app bundled previews)
                    _buildPreviewGeneratorCard(colors, downloadState),
                    const SizedBox(height: 20),

                    // Dev Tools Section
                    _buildDevToolsCard(colors),
                    const SizedBox(height: 20),

                    // Benchmark Test
                    _buildBenchmarkCard(colors, settings),
                    const SizedBox(height: 20),
                    
                    // Reset Database (danger zone)
                    _buildResetDatabaseCard(colors),
                    const SizedBox(height: 20),

                    // Sample Audio Test
                    _buildSampleAudioCard(colors),
                    const SizedBox(height: 20),

                    // TTS Synthesis Test
                    _buildSynthesisCard(colors, settings),
                    const SizedBox(height: 20),

                    // Last Result
                    if (_lastError != null || _lastAudioPath != null)
                      _buildResultCard(colors),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(AppThemeColors colors, SettingsState settings, AsyncValue downloadState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Configuration',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Selected Voice:', settings.selectedVoice, colors),
          _buildInfoRow('Engine:', _getEngineForVoice(settings.selectedVoice), colors),
          downloadState.when(
            loading: () => _buildInfoRow('Downloads:', 'Loading...', colors),
            error: (e, _) => _buildInfoRow('Downloads:', 'Error: $e', colors),
            data: (state) {
              final readyVoices = state.readyVoiceCount;
              final totalVoices = state.totalVoiceCount;
              return _buildInfoRow('Downloads:', '$readyVoices/$totalVoices voices ready', colors);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, AppThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getEngineForVoice(String voiceId) {
    if (voiceId == VoiceIds.device) return 'Device TTS';
    if (VoiceIds.isKokoro(voiceId)) return 'Kokoro';
    if (VoiceIds.isPiper(voiceId)) return 'Piper';
    if (VoiceIds.isSupertonic(voiceId)) return 'Supertonic';
    return 'Unknown';
  }

  Widget _buildPreviewGeneratorCard(AppThemeColors colors, AsyncValue downloadState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.record_voice_over, color: colors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Voice Preview Generator',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Generate preview audio samples for all downloaded voices.\n'
            'Files are saved to the app\'s external storage.',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isGeneratingPreviews ? null : _generateVoicePreviews,
              icon: _isGeneratingPreviews
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isGeneratingPreviews ? 'Generating...' : 'Generate Voice Previews'),
            ),
          ),
          if (_previewGenerationMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.backgroundSecondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _previewGenerationMessage!,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: _previewGenerationMessage!.contains('Error') 
                      ? colors.danger 
                      : colors.text,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _generateVoicePreviews() async {
    setState(() {
      _isGeneratingPreviews = true;
      _previewGenerationMessage = 'Starting preview generation...';
    });

    const previewText = 'Hello, this is a preview of my voice. '
        'I hope you enjoy listening to me read your audiobooks.';

    try {
      final downloadState = ref.read(granularDownloadManagerProvider);
      final routingEngine = await ref.read(ttsRoutingEngineProvider.future);
      
      // Get list of ready voices
      final readyVoices = downloadState.maybeWhen(
        data: (state) => state.readyVoices,
        orElse: () => <dynamic>[],
      );

      if (readyVoices.isEmpty) {
        setState(() {
          _previewGenerationMessage = 'No downloaded voices found. Please download some voices first.';
          _isGeneratingPreviews = false;
        });
        return;
      }

      // Use app's cache directory (no permissions needed)
      // Files will be accessible via: adb shell run-as io.eist.app cat <path>
      final appCacheDir = await getApplicationCacheDirectory();
      final directory = Directory('${appCacheDir.path}/voice_previews');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      DevLogger.info('[PreviewGen] Saving previews to: ${directory.path}');
      DevLogger.info('[PreviewGen] Found ${readyVoices.length} ready voices');

      int generated = 0;
      int failed = 0;
      final List<String> successPaths = [];

      for (final voice in readyVoices) {
        final voiceId = voice.voiceId as String;
        
        setState(() {
          _previewGenerationMessage = 'Generating preview for $voiceId... (${generated + failed + 1}/${readyVoices.length})';
        });

        try {
          DevLogger.info('[PreviewGen] Synthesizing preview for: $voiceId');
          
          final result = await routingEngine.synthesizeToWavFile(
            voiceId: voiceId,
            text: previewText,
            playbackRate: 1.0,
          );

          // Copy to external storage with proper naming
          final safeId = voiceId.replaceAll(':', '_');
          final destPath = '${directory.path}/$safeId.wav';
          await result.file.copy(destPath);

          DevLogger.info('[PreviewGen] ✓ Generated: $destPath');
          successPaths.add(safeId);
          generated++;
        } catch (e) {
          DevLogger.error('[PreviewGen] ✗ Failed for $voiceId: $e');
          failed++;
        }
      }

      setState(() {
        _previewGenerationMessage = '''
✓ Preview Generation Complete!

Generated: $generated
Failed: $failed

Output Directory:
${directory.path}

Generated Files:
${successPaths.map((p) => '• $p.wav').join('\n')}

To copy files to your project, run:
adb shell "run-as io.eist.app cat ${directory.path}/<voice_id>.wav" > assets/voice_previews/<voice_id>.wav
''';
      });

      DevLogger.info('[PreviewGen] Complete! Generated: $generated, Failed: $failed');
    } catch (e) {
      DevLogger.error('[PreviewGen] Error: $e');
      setState(() {
        _previewGenerationMessage = 'Error: $e';
      });
    } finally {
      setState(() => _isGeneratingPreviews = false);
    }
  }

  Widget _buildDevToolsCard(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Developer Tools',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Reimport downloaded books from library',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isReimporting ? null : _reimportDownloadedBooks,
              icon: _isReimporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_isReimporting ? 'Reimporting...' : 'Reimport Downloaded Books'),
            ),
          ),
          if (_reimportMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _reimportMessage!,
              style: TextStyle(
                fontSize: 13,
                color: _reimportMessage!.contains('Error') ? colors.danger : colors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildResetDatabaseCard(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: colors.danger, size: 20),
              const SizedBox(width: 8),
              Text(
                'Reset Database',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Delete the database and restart the app. All books, settings, and progress will be lost!',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isResettingDatabase ? null : _showResetDatabaseDialog,
              style: FilledButton.styleFrom(
                backgroundColor: colors.danger,
              ),
              icon: _isResettingDatabase
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_forever),
              label: Text(_isResettingDatabase ? 'Resetting...' : 'Reset Database'),
            ),
          ),
          if (_resetDatabaseMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _resetDatabaseMessage!,
              style: TextStyle(
                fontSize: 13,
                color: _resetDatabaseMessage!.contains('Error') ? colors.danger : colors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBenchmarkCard(AppThemeColors colors, SettingsState settings) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed, color: colors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Synthesis Benchmark',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '5-minute test chapter using real playback logic.\nCache is cleared before each run for accurate results.',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isBenchmarking ? null : () => _runBenchmark(settings.selectedVoice),
              icon: _isBenchmarking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isBenchmarking ? 'Running Benchmark...' : 'Run Benchmark Test'),
            ),
          ),
          if (_benchmarkResults != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.backgroundSecondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _benchmarkResults!,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: colors.text,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSampleAudioCard(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Direct Audio Test',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Test audio playback independently of TTS',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isPlaying ? null : _playTestTone,
                  icon: Icon(_isPlaying ? Icons.stop : Icons.volume_up),
                  label: Text(_isPlaying ? 'Playing...' : 'Play Test Tone'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isPlaying ? null : _playCachedAudio,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Play Last Cache'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSynthesisCard(AppThemeColors colors, SettingsState settings) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TTS Synthesis Test',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Using voice: ${settings.selectedVoice}',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _textController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter text to synthesize...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: colors.backgroundSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isSynthesizing ? null : () => _synthesize(settings.selectedVoice),
                  icon: _isSynthesizing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.record_voice_over),
                  label: Text(_isSynthesizing ? 'Synthesizing...' : 'Synthesize'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _lastAudioPath != null && !_isPlaying ? _playLastSynthesized : null,
                  icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                  label: Text(_isPlaying ? 'Playing...' : 'Play Result'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _lastError != null ? colors.danger.withValues(alpha: 0.1) : colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _lastError != null ? colors.danger : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _lastError != null ? 'Error' : 'Last Result',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _lastError != null ? colors.danger : colors.text,
            ),
          ),
          const SizedBox(height: 12),
          if (_lastError != null)
            Text(
              _lastError!,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: colors.danger,
              ),
            ),
          if (_lastAudioPath != null) ...[
            _buildInfoRow('Duration:', '${_lastDurationMs}ms', colors),
            _buildInfoRow('File size:', '${(_lastFileSizeBytes ?? 0) ~/ 1024} KB', colors),
            _buildInfoRow('Synth time:', '${_synthesisTime.inMilliseconds}ms', colors),
            _buildInfoRow('RTF:', 
              _lastDurationMs != null && _lastDurationMs! > 0
                ? '${(_synthesisTime.inMilliseconds / _lastDurationMs!).toStringAsFixed(2)}x'
                : 'N/A',
              colors),
            const SizedBox(height: 8),
            Text(
              _lastAudioPath!,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: colors.textTertiary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _playTestTone() async {
    setState(() => _isPlaying = true);
    
    try {
      // Generate a simple sine wave test tone
      DevLogger.info('[Developer] Playing test tone...');
      
      // Use a system sound or just test the player
      await _testPlayer.setAsset('assets/test_tone.wav');
      await _testPlayer.play();
      
      // Wait for completion
      await _testPlayer.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
    } catch (e) {
      DevLogger.error('[Developer] Test tone error: $e');
      // If no test tone asset, try URL
      try {
        await _testPlayer.setUrl(
          'https://www.soundjay.com/buttons/beep-01a.mp3',
        );
        await _testPlayer.play();
        await _testPlayer.playerStateStream.firstWhere(
          (state) => state.processingState == ProcessingState.completed,
        );
      } catch (e2) {
        setState(() {
          _lastError = 'Failed to play test sound: $e2';
        });
      }
    } finally {
      setState(() => _isPlaying = false);
    }
  }

  Future<void> _playCachedAudio() async {
    if (_lastAudioPath == null) {
      setState(() => _lastError = 'No cached audio available');
      return;
    }
    
    await _playLastSynthesized();
  }

  Future<void> _synthesize(String voiceId) async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _lastError = 'Please enter text to synthesize');
      return;
    }

    setState(() {
      _isSynthesizing = true;
      _lastError = null;
      _lastAudioPath = null;
    });

    try {
      DevLogger.info('[Developer] Synthesizing text with voice: $voiceId');
      DevLogger.info('[Developer] Text: $text');
      
      final startTime = DateTime.now();
      
      final routingEngine = await ref.read(ttsRoutingEngineProvider.future);
      
      final result = await routingEngine.synthesizeToWavFile(
        voiceId: voiceId,
        text: text,
        playbackRate: 1.0,
      );

      final elapsed = DateTime.now().difference(startTime);
      final fileSize = await result.file.length();

      DevLogger.info('[Developer] Synthesis complete: ${result.durationMs}ms, $fileSize bytes');
      DevLogger.info('[Developer] File: ${result.file.path}');

      setState(() {
        _lastAudioPath = result.file.path;
        _lastDurationMs = result.durationMs;
        _lastFileSizeBytes = fileSize;
        _synthesisTime = elapsed;
        _lastError = null;
      });
    } catch (e, st) {
      DevLogger.error('[Developer] Synthesis error: $e');
      DevLogger.error('[Developer] Stack: $st');
      setState(() {
        _lastError = e.toString();
        _lastAudioPath = null;
      });
    } finally {
      setState(() => _isSynthesizing = false);
    }
  }

  Future<void> _playLastSynthesized() async {
    if (_lastAudioPath == null) return;
    
    final file = File(_lastAudioPath!);
    if (!await file.exists()) {
      setState(() => _lastError = 'Audio file not found');
      return;
    }

    setState(() => _isPlaying = true);
    
    try {
      DevLogger.info('[Developer] Playing: $_lastAudioPath');
      await _testPlayer.setFilePath(_lastAudioPath!);
      DevLogger.info('[Developer] Duration: ${_testPlayer.duration}');
      await _testPlayer.play();
      DevLogger.info('[Developer] Play started, waiting for completion...');
      
      // Wait for completion
      await _testPlayer.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
      DevLogger.info('[Developer] Playback completed');
    } catch (e) {
      DevLogger.error('[Developer] Playback error: $e');
      setState(() => _lastError = 'Playback error: $e');
    } finally {
      setState(() => _isPlaying = false);
    }
  }

  Future<void> _reimportDownloadedBooks() async {
    setState(() {
      _isReimporting = true;
      _reimportMessage = null;
    });

    try {
      final libraryController = ref.read(libraryProvider.notifier);
      final currentState = ref.read(libraryProvider).value;
      
      if (currentState == null || currentState.books.isEmpty) {
        setState(() {
          _reimportMessage = 'No books in library to reimport';
          _isReimporting = false;
        });
        return;
      }

      final books = currentState.books;
      DevLogger.info('[Developer] Found ${books.length} books in library to reimport');
      
      int reimported = 0;
      int failed = 0;

      for (final book in books) {
        try {
          if (book.filePath.isEmpty) {
            DevLogger.info('[Developer] Skipping ${book.title}: no file path');
            failed++;
            continue;
          }

          final file = File(book.filePath);
          if (!await file.exists()) {
            DevLogger.info('[Developer] Skipping ${book.title}: file not found at ${book.filePath}');
            failed++;
            continue;
          }

          DevLogger.info('[Developer] Reimporting: ${book.title}');
          
          // Remove the old book entry
          await libraryController.removeBook(book.id);
          
          // Re-import from the existing file path
          final fileName = book.filePath.split('/').last;
          await libraryController.importBookFromPath(
            sourcePath: book.filePath,
            fileName: fileName,
            gutenbergId: book.gutenbergId,
          );
          
          reimported++;
          setState(() {
            _reimportMessage = 'Reimported $reimported/${books.length} books...';
          });
        } catch (e) {
          DevLogger.error('[Developer] Failed to reimport ${book.title}: $e');
          failed++;
        }
      }

      setState(() {
        _reimportMessage = 
            'Reimport complete: $reimported successful, $failed failed';
      });
      
      DevLogger.info('[Developer] Reimport complete: $reimported successful, $failed failed');
    } catch (e) {
      DevLogger.error('[Developer] Reimport error: $e');
      setState(() {
        _reimportMessage = 'Error: $e';
      });
    } finally {
      setState(() => _isReimporting = false);
    }
  }
  
  Future<void> _showResetDatabaseDialog() async {
    final colors = context.appColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Database?'),
        content: const Text(
          'This will delete ALL data including:\n\n'
          '• All imported books\n'
          '• Reading progress\n'
          '• Settings\n'
          '• Audio cache metadata\n\n'
          'The app will close. You will need to restart it manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: colors.danger,
            ),
            child: const Text('Reset & Exit'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _resetDatabase();
    }
  }
  
  Future<void> _resetDatabase() async {
    setState(() {
      _isResettingDatabase = true;
      _resetDatabaseMessage = 'Deleting database...';
    });
    
    try {
      await AppDatabase.deleteDatabase();
      
      setState(() {
        _resetDatabaseMessage = 'Database deleted. Exiting app...';
      });
      
      // Wait a moment for user to see the message
      await Future.delayed(const Duration(seconds: 1));
      
      // Exit the app (user must restart manually)
      exit(0);
    } catch (e) {
      DevLogger.error('[Developer] Failed to reset database: $e');
      setState(() {
        _resetDatabaseMessage = 'Error: $e';
        _isResettingDatabase = false;
      });
    }
  }

  /// Generate a realistic 5-minute test chapter (approximately 750 words for ~5 min at normal reading speed).
  String _generateBenchmarkChapter() {
    return '''
The detective stood at the window of her office, watching the rain streak down the glass in irregular patterns. It had been raining for three days straight, and the city looked gray and weary beneath the persistent downpour. Sarah Chen had been a homicide detective for fifteen years, long enough to develop a sixth sense about cases, and this one felt different.

The victim, Marcus Thompson, had been found in his apartment three mornings ago. No signs of forced entry. No struggle. Just a man lying peacefully in his bed, except he wasn't sleeping. The toxicology report had come back that morning, and it confirmed her suspicions: a rare poison, one that required specialized knowledge to acquire and administer.

Her partner, Detective James Rodriguez, knocked on the door frame before entering. He carried two cups of coffee, one of which he set on her desk without a word. It was their ritual, this silent exchange of caffeine. They'd been partners for eight years, and some things didn't require discussion.

"The wife's alibi checks out," James said, settling into the chair across from her desk. "She was at a conference in Seattle when it happened. Multiple witnesses, hotel security footage, the works." He took a sip of his coffee and grimaced. The precinct coffee was notoriously terrible, but it was hot and contained caffeine, which was all that really mattered.

Sarah turned from the window, her mind already racing through the implications. If not the wife, then who? Thompson had no enemies that they could find. He was a mild-mannered accountant, devoted to his wife, attended church regularly, volunteered at a local food bank. On paper, he was practically a saint.

"What about the business partner?" she asked, moving to her desk and pulling out the case file. It was already thick with reports, witness statements, and photographs. "David Chen. No relation," she added, noting James's raised eyebrow at the shared surname. It was a common enough name, but in their line of work, coincidences always warranted explanation.

"Chen's clean too. Been out of the country for two weeks. His passport confirms travel to Japan for a business conference. He only flew back yesterday when he heard about Thompson's death." James leaned back in his chair, the springs creaking in protest. "We're missing something, Sarah. Everyone's alibis are solid, but someone killed this man."

She nodded, flipping through the crime scene photos once more. Something had been nagging at her since the beginning, a detail that didn't quite fit. The apartment had been spotless, almost obsessively clean. No dust, no clutter, everything in its designated place. But there, in the corner of one photograph, she saw it.

"Look at this," she said, sliding the photo across to James. "The bookshelf. See that gap?" Her finger pointed to an empty space between two leather-bound volumes. "Something's missing."

James squinted at the image, then pulled out his phone to check his notes. "The wife said everything was there. Nothing was taken." He scrolled through his digital notes. "We have a complete inventory of the apartment. If something's missing, she didn't report it."

"Maybe she didn't know it was missing," Sarah suggested. "Or maybe she didn't know it existed in the first place." She stood up, pacing the small office. Her mind was connecting dots, forming patterns. "What if Thompson was involved in something his wife didn't know about? Something that got him killed?"

The rain outside intensified, drumming against the window with renewed vigor. Sarah watched the water cascade down, her reflection ghostly in the glass. In fifteen years of detective work, she'd learned that people always had secrets. The trick was figuring out which secrets mattered.

"I want to talk to Thompson's colleagues again," she said, turning back to James. "Not the partner. The people he worked with every day. Someone knows something they're not telling us." She grabbed her jacket from the back of her chair and her car keys from the desk. "And I want another look at that apartment. There's something we missed."

James drained the last of his terrible coffee and stood up. "You thinking what I'm thinking?" he asked, a knowing smile crossing his face. After eight years as partners, they often arrived at the same conclusions via different routes.

"That our mild-mannered accountant wasn't so mild-mannered after all?" Sarah returned the smile grimly. "Yeah. That's exactly what I'm thinking. Let's go find out what Marcus Thompson was really up to."

They left the office together, heading out into the rain. The afternoon was growing late, the sky already darkening with the approach of evening. Somewhere in this city was a killer who thought they'd committed the perfect crime. Sarah Chen was determined to prove them wrong.
''';
  }

  Future<void> _runBenchmark(String voiceId) async {
    setState(() {
      _isBenchmarking = true;
      _benchmarkResults = null;
      _lastError = null;
    });

    DevLogger.info('[Benchmark] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    DevLogger.info('[Benchmark] STARTING SYNTHESIS BENCHMARK');
    DevLogger.info('[Benchmark] Voice: $voiceId');

    try {
      // Get TTS engine
      final routingEngine = await ref.read(ttsRoutingEngineProvider.future);
      final cache = await ref.read(audioCacheProvider.future);
      
      // Check voice readiness
      final voiceReadiness = await routingEngine.checkVoiceReady(voiceId);
      if (!voiceReadiness.isReady) {
        setState(() {
          _lastError = 'Voice not ready: ${voiceReadiness.nextActionUserShouldTake}';
          _isBenchmarking = false;
        });
        return;
      }

      // Generate test chapter
      final chapterText = _generateBenchmarkChapter();
      DevLogger.info('[Benchmark] Generated chapter: ${chapterText.length} characters');
      
      // ════════════════════════════════════════════════════════════════════════
      // CLEAR CACHE for accurate benchmark (we want to measure synthesis, not cache hits)
      // ════════════════════════════════════════════════════════════════════════
      DevLogger.info('[Benchmark] Clearing cache for accurate measurement...');
      await cache.clear();
      DevLogger.info('[Benchmark] Cache cleared');
      
      // Segment text using SAME logic as playback
      final benchmarkStart = DateTime.now();
      final segments = segmentText(chapterText);
      final segmentDuration = DateTime.now().difference(benchmarkStart);
      
      DevLogger.info('[Benchmark] Segmented into ${segments.length} segments in ${segmentDuration.inMilliseconds}ms');
      
      // Calculate expected audio duration
      final expectedDurationMs = segments.fold<int>(
        0,
        (sum, segment) => sum + segment.estimatedDuration.inMilliseconds,
      );
      final expectedMinutes = (expectedDurationMs / 60000).toStringAsFixed(1);
      DevLogger.info('[Benchmark] Expected audio duration: $expectedMinutes minutes');

      // Synthesize all segments (simulating playback logic)
      int synthesized = 0;
      int cached = 0;
      int failed = 0;
      int totalSynthesisMs = 0;
      final List<int> synthesisTimesMs = []; // Track per-segment synthesis time
      
      final synthStart = DateTime.now();
      
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        
        // Generate cache key using SAME logic as playback
        final cacheKey = CacheKeyGenerator.generate(
          voiceId: voiceId,
          text: segment.text,
          playbackRate: CacheKeyGenerator.getSynthesisRate(1.0),
        );

        // Check cache
        final isCached = await cache.isReady(cacheKey);
        if (isCached) {
          DevLogger.debug('[Benchmark] [$i/${segments.length}] Cached');
          cached++;
          synthesisTimesMs.add(0); // Cached = instant
          continue;
        }

        // Synthesize using SAME engine as playback
        DevLogger.debug('[Benchmark] [$i/${segments.length}] Synthesizing...');
        final segmentStart = DateTime.now();
        
        try {
          await routingEngine.synthesizeToWavFile(
            voiceId: voiceId,
            text: segment.text,
            playbackRate: 1.0,
          );
          
          final segmentDuration = DateTime.now().difference(segmentStart);
          totalSynthesisMs += segmentDuration.inMilliseconds;
          synthesisTimesMs.add(segmentDuration.inMilliseconds);
          synthesized++;
          
          DevLogger.debug('[Benchmark] [$i/${segments.length}] Done in ${segmentDuration.inMilliseconds}ms');
        } catch (e) {
          DevLogger.error('[Benchmark] [$i/${segments.length}] FAILED: $e');
          synthesisTimesMs.add(0); // Failed = no time counted
          failed++;
        }

        // Update UI periodically
        if (i % 5 == 0) {
          setState(() {
            _benchmarkResults = 'Progress: $i/${segments.length} segments\n'
                'Synthesized: $synthesized, Cached: $cached, Failed: $failed';
          });
        }
      }

      final totalDuration = DateTime.now().difference(synthStart);
      final avgSynthesisTime = synthesized > 0 ? totalSynthesisMs / synthesized : 0;
      
      // Calculate RTF (Real-Time Factor)
      final rtf = expectedDurationMs > 0 ? totalSynthesisMs / expectedDurationMs : 0;

      // ═══════════════════════════════════════════════════════════════════════════
      // CALCULATE USER BUFFERING TIME (MOST IMPORTANT METRIC!)
      // ═══════════════════════════════════════════════════════════════════════════
      // Simulate actual playback: when would user need to wait for synthesis?
      int totalBufferingMs = 0;
      int bufferingEvents = 0;
      
      if (synthesisTimesMs.isNotEmpty && segments.isNotEmpty) {
        // First segment ALWAYS blocks (user presses play, waits for synthesis)
        if (synthesisTimesMs[0] > 0) {
          totalBufferingMs = synthesisTimesMs[0];
          bufferingEvents = 1;
        }
        
        // Simulate playback with background prefetch
        int cumulativeAudioMs = 0;
        int cumulativeSynthesisMs = synthesisTimesMs[0]; // Prefetch starts after first segment
        
        for (var i = 1; i < segments.length; i++) {
          // When does playback NEED this segment?
          cumulativeAudioMs += segments[i - 1].estimatedDuration.inMilliseconds;
          
          // When is synthesis COMPLETE for this segment?
          cumulativeSynthesisMs += synthesisTimesMs[i];
          
          // Does user need to wait?
          if (cumulativeAudioMs < cumulativeSynthesisMs) {
            final waitMs = cumulativeSynthesisMs - cumulativeAudioMs;
            totalBufferingMs += waitMs;
            bufferingEvents++;
          }
        }
      }
      
      final bufferingPercent = expectedDurationMs > 0 
          ? (totalBufferingMs / expectedDurationMs * 100) 
          : 0.0;

      DevLogger.info('[Benchmark] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      DevLogger.info('[Benchmark] BENCHMARK COMPLETE');
      DevLogger.info('[Benchmark] Total segments: ${segments.length}');
      DevLogger.info('[Benchmark] Synthesized: $synthesized');
      DevLogger.info('[Benchmark] Cached: $cached');
      DevLogger.info('[Benchmark] Failed: $failed');
      DevLogger.info('[Benchmark] Total time: ${totalDuration.inSeconds}s');
      DevLogger.info('[Benchmark] Average synthesis time: ${avgSynthesisTime.toStringAsFixed(0)}ms/segment');
      DevLogger.info('[Benchmark] RTF: ${rtf.toStringAsFixed(2)}x');
      DevLogger.info('[Benchmark] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      DevLogger.info('[Benchmark] 🔴 USER EXPERIENCE METRICS (MOST IMPORTANT!)');
      DevLogger.info('[Benchmark] Total buffering time: ${(totalBufferingMs / 1000).toStringAsFixed(1)}s');
      DevLogger.info('[Benchmark] Buffering events: $bufferingEvents');
      DevLogger.info('[Benchmark] Buffering percentage: ${bufferingPercent.toStringAsFixed(1)}% of playback');
      if (bufferingEvents > 0) {
        DevLogger.info('[Benchmark] First segment wait: ${(synthesisTimesMs[0] / 1000).toStringAsFixed(1)}s');
        if (bufferingEvents > 1) {
          DevLogger.info('[Benchmark] Additional pauses: ${bufferingEvents - 1} during playback');
        }
      }
      DevLogger.info('[Benchmark] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      setState(() {
        _benchmarkResults = '''
✓ Benchmark Complete!

Total Segments: ${segments.length}
Expected Audio: $expectedMinutes min

🔴 USER EXPERIENCE (Most Important!):
• Buffering Time: ${(totalBufferingMs / 1000).toStringAsFixed(1)}s (${bufferingPercent.toStringAsFixed(1)}% of playback)
• Buffering Events: $bufferingEvents
${bufferingEvents > 0 ? '• First Wait: ${(synthesisTimesMs[0] / 1000).toStringAsFixed(1)}s (press play → audio starts)' : ''}
${bufferingEvents > 1 ? '• Additional Pauses: ${bufferingEvents - 1} during playback' : ''}

Synthesis Results:
• Synthesized: $synthesized
• Cached: $cached  
• Failed: $failed

Technical Performance:
• Total Time: ${totalDuration.inSeconds}s
• Avg/Segment: ${avgSynthesisTime.toStringAsFixed(0)}ms
• RTF: ${rtf.toStringAsFixed(2)}x

${synthesized > 0 ? '\n✓ Successfully synthesized $synthesized segments' : ''}
${cached > 0 ? '\n⚡ Used $cached cached segments (instant playback!)' : ''}
${failed > 0 ? '\n⚠️ $failed segments failed' : ''}

💡 RTF < 1.0 = faster than real-time (good!)
💡 Buffering Time = actual user frustration
💡 Goal: 0s buffering with smart pre-synthesis
''';
      });
    } catch (e, st) {
      DevLogger.error('[Benchmark] ERROR: $e');
      DevLogger.error('[Benchmark] Stack: $st');
      setState(() {
        _lastError = 'Benchmark failed: $e';
        _benchmarkResults = null;
      });
    } finally {
      setState(() => _isBenchmarking = false);
    }
  }

}
