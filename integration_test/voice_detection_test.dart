// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:audiobook_flutter_v2/main.dart' as app;
import 'package:flutter/material.dart';

/// Quick test to check if voice models are detected.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Voice detection test', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    print('=== VOICE DETECTION TEST ===\n');

    // Step 1: Go to Settings
    print('=== STEP 1: Navigate to Settings ===');
    
    final settingsIcon = find.byIcon(Icons.settings_outlined);
    if (settingsIcon.evaluate().isEmpty) {
      print('✗ No settings icon found');
      return;
    }
    
    await tester.tap(settingsIcon.first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    print('✓ Opened Settings screen');

    // Step 2: Find voice section
    print('\n=== STEP 2: Check Voice Section ===');
    
    // Log all text widgets
    final allTexts = find.byType(Text);
    print('Settings screen has ${allTexts.evaluate().length} text widgets:');
    for (final el in allTexts.evaluate()) {
      final text = el.widget as Text;
      if (text.data != null && text.data!.isNotEmpty) {
        if (text.data!.toLowerCase().contains('voice') ||
            text.data!.toLowerCase().contains('download') ||
            text.data!.toLowerCase().contains('piper') ||
            text.data!.toLowerCase().contains('none')) {
          print('  > "${text.data}"');
        }
      }
    }
    
    // Look for "Selected voice" row
    final selectedVoiceText = find.text('Selected voice');
    if (selectedVoiceText.evaluate().isNotEmpty) {
      print('\n✓ Found "Selected voice" setting');
      
      // The sub-label shows the current voice
      // Look for text following "Selected voice"
      final voiceLabels = [
        find.text('None - Download a voice'),
        find.textContaining('Piper'),
        find.textContaining('Kokoro'),
        find.textContaining('Supertonic'),
      ];
      
      for (final finder in voiceLabels) {
        if (finder.evaluate().isNotEmpty) {
          final text = finder.evaluate().first.widget as Text;
          print('Current voice: "${text.data}"');
          break;
        }
      }
    }
    
    // Step 3: Tap on voice selector to see available voices
    print('\n=== STEP 3: Open Voice Picker ===');
    
    if (selectedVoiceText.evaluate().isNotEmpty) {
      await tester.tap(selectedVoiceText.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      // Check for voice options
      final piperVoices = find.textContaining('Piper');
      final kokoroVoices = find.textContaining('Kokoro');
      final supertonicVoices = find.textContaining('Supertonic');
      
      print('Available voices:');
      print('  - Piper voices: ${piperVoices.evaluate().length}');
      print('  - Kokoro voices: ${kokoroVoices.evaluate().length}');
      print('  - Supertonic voices: ${supertonicVoices.evaluate().length}');
      
      // List all text in the picker
      final pickerTexts = find.byType(Text);
      for (final el in pickerTexts.evaluate()) {
        final text = el.widget as Text;
        if (text.data != null && text.data!.contains(':')) {
          // Voice IDs contain colons like "piper:en_US-lessac-medium"
          print('  Voice option: "${text.data}"');
        }
      }
      
      // Check if any voice is available
      final hasVoices = piperVoices.evaluate().isNotEmpty ||
                        kokoroVoices.evaluate().isNotEmpty ||
                        supertonicVoices.evaluate().isNotEmpty;
      
      if (hasVoices) {
        print('\n✓ Voice models detected!');
        
        // Try to select a Piper voice
        if (piperVoices.evaluate().isNotEmpty) {
          print('Selecting Piper voice...');
          await tester.tap(piperVoices.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
          print('✓ Piper voice selected');
        }
      } else {
        print('\n✗ No voice models available');
        print('Make sure to push voice model after install:');
        print('  ./scripts/push_piper_model.sh');
      }
    }

    print('\n=== VOICE DETECTION TEST COMPLETE ===');
  });
}
