import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/granular_download_manager.dart';
import '../../app/settings_controller.dart';
import '../../app/tts_providers.dart';
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
  String? _lastError;
  String? _lastAudioPath;
  int? _lastDurationMs;
  int? _lastFileSizeBytes;
  Duration _synthesisTime = Duration.zero;

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
      print('[Developer] Playing test tone...');
      
      // Use a system sound or just test the player
      await _testPlayer.setAsset('assets/test_tone.wav');
      await _testPlayer.play();
      
      // Wait for completion
      await _testPlayer.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
    } catch (e) {
      print('[Developer] Test tone error: $e');
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
      print('[Developer] Synthesizing text with voice: $voiceId');
      print('[Developer] Text: $text');
      
      final startTime = DateTime.now();
      
      final routingEngine = await ref.read(ttsRoutingEngineProvider.future);
      
      final result = await routingEngine.synthesizeToWavFile(
        voiceId: voiceId,
        text: text,
        playbackRate: 1.0,
      );

      final elapsed = DateTime.now().difference(startTime);
      final fileSize = await result.file.length();

      print('[Developer] Synthesis complete: ${result.durationMs}ms, ${fileSize} bytes');
      print('[Developer] File: ${result.file.path}');

      setState(() {
        _lastAudioPath = result.file.path;
        _lastDurationMs = result.durationMs;
        _lastFileSizeBytes = fileSize;
        _synthesisTime = elapsed;
        _lastError = null;
      });
    } catch (e, st) {
      print('[Developer] Synthesis error: $e');
      print('[Developer] Stack: $st');
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
      print('[Developer] Playing: $_lastAudioPath');
      await _testPlayer.setFilePath(_lastAudioPath!);
      print('[Developer] Duration: ${_testPlayer.duration}');
      await _testPlayer.play();
      print('[Developer] Play started, waiting for completion...');
      
      // Wait for completion
      await _testPlayer.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
      print('[Developer] Playback completed');
    } catch (e) {
      print('[Developer] Playback error: $e');
      setState(() => _lastError = 'Playback error: $e');
    } finally {
      setState(() => _isPlaying = false);
    }
  }
}
