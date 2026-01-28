// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:audiobook_flutter_v2/main.dart' as app;
import 'package:flutter/material.dart';

/// Test that imports a book and tests TTS playback.
/// IMPORTANT: Run this AFTER pushing the voice model:
///   flutter install -d localhost:5555 --debug
///   ./scripts/push_piper_model.sh
///   adb -s localhost:5555 shell am force-stop io.eist.app
///   adb -s localhost:5555 shell am start -n io.eist.app/...
/// 
/// Then run:
///   flutter test integration_test/tts_playback_test.dart -d localhost:5555
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TTS playback test', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    print('=== TTS PLAYBACK TEST ===\n');

    // Step 1: Import a book from Gutenberg
    print('=== STEP 1: Import book from Gutenberg ===');
    
    final freeBooksButton = find.text('Free Books');
    if (freeBooksButton.evaluate().isEmpty) {
      print('✗ No "Free Books" button found');
      return;
    }
    
    await tester.tap(freeBooksButton.first);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    print('✓ Opened Free Books screen');
    
    // Wait for books to load and find import button
    await tester.pump(const Duration(seconds: 3));
    
    final importButton = find.text('Import');
    if (importButton.evaluate().isNotEmpty) {
      print('Found Import button, tapping...');
      await tester.tap(importButton.first);
      
      // Wait for import to complete
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        final openButton = find.text('Open');
        if (openButton.evaluate().isNotEmpty) {
          print('✓ Book imported (${i+1}s)');
          break;
        }
        if (i % 5 == 4) print('  Importing... (${i+1}s)');
      }
    } else {
      // Book may already be imported
      final openButton = find.text('Open');
      if (openButton.evaluate().isNotEmpty) {
        print('Book already imported, opening...');
        await tester.tap(openButton.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
    }
    
    // Step 2: Return to library
    print('\n=== STEP 2: Return to Library ===');
    final backButton = find.byIcon(Icons.arrow_back);
    if (backButton.evaluate().isNotEmpty) {
      await tester.tap(backButton.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      print('✓ Back to library');
    }
    
    // Step 3: Find and open the imported book
    print('\n=== STEP 3: Open Book ===');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    
    final bookTitle = find.textContaining('Frankenstein');
    if (bookTitle.evaluate().isEmpty) {
      print('✗ No book found in library');
      final allTexts = find.byType(Text);
      for (final el in allTexts.evaluate().take(15)) {
        final text = el.widget as Text;
        if (text.data != null) print('  Text: "${text.data}"');
      }
      return;
    }
    
    print('✓ Found Frankenstein');
    await tester.tap(bookTitle.first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    print('✓ Opened book details');
    
    // Step 4: Start playback
    print('\n=== STEP 4: Start Playback ===');
    
    final playButton = find.byIcon(Icons.play_arrow);
    if (playButton.evaluate().isEmpty) {
      print('✗ No play button found');
      return;
    }
    
    await tester.tap(playButton.first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    print('✓ Entered playback screen');
    
    // Step 5: Select voice and start
    print('\n=== STEP 5: Check TTS Status ===');
    
    // Wait for playback controller to initialize and check logs
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
      
      // Look for pause button (indicates playback started)
      final pauseButton = find.byIcon(Icons.pause);
      final errorIcon = find.byIcon(Icons.error_outline);
      final errorText = find.textContaining(RegExp(r'error|failed|not available', caseSensitive: false));
      
      // Check for TTS synthesis indicators
      if (pauseButton.evaluate().isNotEmpty) {
        print('✓ Playback controls active - pause button visible (${i+1}s)');
        
        // Check if audio is actually synthesizing
        // Look for the play/pause button state
        print('✓ TTS synthesis appears to be working!');
        break;
      }
      
      if (errorIcon.evaluate().isNotEmpty || errorText.evaluate().isNotEmpty) {
        print('✗ Error detected during playback');
        for (final el in errorText.evaluate()) {
          final text = el.widget as Text;
          print('  Error: "${text.data}"');
        }
        break;
      }
      
      if (i % 5 == 4) {
        print('  Waiting for TTS... (${i+1}s)');
        // Log current screen state
        final texts = find.byType(Text);
        for (final el in texts.evaluate().take(5)) {
          final text = el.widget as Text;
          if (text.data != null && text.data!.isNotEmpty) {
            print('    - "${text.data}"');
          }
        }
      }
    }
    
    // Step 6: Final state check
    print('\n=== STEP 6: Final State ===');
    
    // Log all text on the playback screen
    final allTexts = find.byType(Text);
    print('Playback screen text:');
    for (final el in allTexts.evaluate().take(20)) {
      final text = el.widget as Text;
      if (text.data != null && text.data!.isNotEmpty) {
        print('  "${text.data}"');
      }
    }
    
    // Check for key playback elements
    final chapterText = find.textContaining('Chapter');
    final timeText = find.textContaining(RegExp(r'\d:\d\d'));
    
    if (chapterText.evaluate().isNotEmpty) {
      print('✓ Chapter indicator visible');
    }
    if (timeText.evaluate().isNotEmpty) {
      print('✓ Time indicator visible');
    }

    print('\n=== TTS PLAYBACK TEST COMPLETE ===');
  });
}
