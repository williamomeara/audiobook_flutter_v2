// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:audiobook_flutter_v2/main.dart' as app;
import 'package:flutter/material.dart';

/// Integration test for Piper TTS playback.
/// 
/// Pre-requisites:
/// 1. Piper lessac model pushed via ADB to app_flutter/piper/piper_lessac_us_v1/
/// 2. A book should already be in the library (or we'll import from Gutenberg)
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Piper TTS playback test', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    print('=== PIPER TTS PLAYBACK TEST ===\n');

    // Step 1: Navigate to Settings to verify voice is detected
    print('=== STEP 1: Verify Piper voice in Settings ===');
    
    final settingsButton = find.byIcon(Icons.settings_outlined);
    expect(settingsButton, findsOneWidget);
    await tester.tap(settingsButton);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    
    // Look for voice selector
    final voiceLabel = find.textContaining('Voice');
    print('Found "Voice" labels: ${voiceLabel.evaluate().length}');
    
    // Look for Piper in the UI
    final piperText = find.textContaining('Piper');
    final lessacText = find.textContaining('Lessac');
    
    if (piperText.evaluate().isNotEmpty) {
      print('✓ Piper engine visible in settings');
    }
    if (lessacText.evaluate().isNotEmpty) {
      print('✓ Lessac voice visible in settings');
    }
    
    // Try to find voice selection dropdown/button
    final voiceDropdown = find.byKey(const Key('voice_selector'));
    final voicePicker = find.textContaining(RegExp(r'Select|Choose|Voice'));
    
    print('Voice dropdown: ${voiceDropdown.evaluate().length}');
    print('Voice picker text: ${voicePicker.evaluate().length}');
    
    // Take screenshot of settings
    print('\n--- Settings Screen State ---');
    
    // Try scrolling to find voice settings
    final scrollable = find.byType(SingleChildScrollView);
    if (scrollable.evaluate().isNotEmpty) {
      for (int i = 0; i < 5; i++) {
        await tester.drag(scrollable.first, const Offset(0, -200));
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
        
        final piperAfterScroll = find.textContaining('Piper');
        final lessacAfterScroll = find.textContaining('Lessac');
        
        if (piperAfterScroll.evaluate().isNotEmpty || lessacAfterScroll.evaluate().isNotEmpty) {
          print('✓ Found Piper/Lessac after scroll');
          
          // Try to tap on it to select
          if (lessacAfterScroll.evaluate().isNotEmpty) {
            await tester.tap(lessacAfterScroll.first);
            await tester.pumpAndSettle(const Duration(seconds: 1));
            print('  Tapped on Lessac voice');
          } else if (piperAfterScroll.evaluate().isNotEmpty) {
            await tester.tap(piperAfterScroll.first);
            await tester.pumpAndSettle(const Duration(seconds: 1));
            print('  Tapped on Piper option');
          }
          break;
        }
      }
    }

    // Step 2: Navigate back to library and find a book
    print('\n=== STEP 2: Navigate to Library ===');
    
    final backButton = find.byIcon(Icons.arrow_back);
    if (backButton.evaluate().isNotEmpty) {
      await tester.tap(backButton.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
    
    // Check if we have any books
    final bookTiles = find.byType(Card);
    final listTiles = find.byType(ListTile);
    
    print('Cards found: ${bookTiles.evaluate().length}');
    print('ListTiles found: ${listTiles.evaluate().length}');
    
    // If no books, import from Gutenberg
    if (bookTiles.evaluate().isEmpty && listTiles.evaluate().isEmpty) {
      print('\n=== STEP 2a: Import book from Gutenberg ===');
      
      final gutenbergButton = find.byIcon(Icons.public);
      if (gutenbergButton.evaluate().isNotEmpty) {
        await tester.tap(gutenbergButton.first);
        await tester.pumpAndSettle(const Duration(seconds: 5));
        
        // Find first book with Import button
        final importButtons = find.widgetWithText(IconButton, 'Import').evaluate().isEmpty
            ? find.byIcon(Icons.download)
            : find.widgetWithText(IconButton, 'Import');
        
        if (importButtons.evaluate().isNotEmpty) {
          await tester.tap(importButtons.first);
          await tester.pumpAndSettle(const Duration(seconds: 30));
          print('✓ Imported book from Gutenberg');
        }
        
        // Go back to library
        final closeButton = find.byIcon(Icons.arrow_back);
        if (closeButton.evaluate().isNotEmpty) {
          await tester.tap(closeButton.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }
    }
    
    // Step 3: Open a book for playback
    print('\n=== STEP 3: Open book for playback ===');
    
    // Find any book card/tile and tap it
    final bookCards = find.byType(Card);
    final bookListTiles = find.byType(ListTile);
    
    Finder? bookToTap;
    if (bookCards.evaluate().isNotEmpty) {
      bookToTap = bookCards.first;
      print('Tapping on Card...');
    } else if (bookListTiles.evaluate().isNotEmpty) {
      bookToTap = bookListTiles.first;
      print('Tapping on ListTile...');
    }
    
    if (bookToTap != null) {
      await tester.tap(bookToTap);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      print('✓ Opened book details');
      
      // Step 4: Start playback
      print('\n=== STEP 4: Start playback ===');
      
      // Look for Play button
      final playButton = find.byIcon(Icons.play_arrow);
      final playFab = find.byType(FloatingActionButton);
      final readButton = find.textContaining(RegExp(r'Read|Play|Listen|Start'));
      
      Finder? startPlayback;
      if (playButton.evaluate().isNotEmpty) {
        startPlayback = playButton.first;
        print('Found play icon button');
      } else if (playFab.evaluate().isNotEmpty) {
        startPlayback = playFab.first;
        print('Found FloatingActionButton');
      } else if (readButton.evaluate().isNotEmpty) {
        startPlayback = readButton.first;
        print('Found Read/Play/Listen button');
      }
      
      if (startPlayback != null) {
        await tester.tap(startPlayback);
        await tester.pumpAndSettle(const Duration(seconds: 5));
        print('✓ Tapped play button');
        
        // Wait for playback screen to load
        print('\n--- PLAYBACK SCREEN ---');
        await tester.pump(const Duration(seconds: 3));
        
        // Check for playback UI elements
        final playPauseBtn = find.byIcon(Icons.pause);
        final stopBtn = find.byIcon(Icons.stop);
        final progressBar = find.byType(Slider);
        final textDisplay = find.textContaining(RegExp(r'.{20,}')); // Long text
        
        print('Pause button: ${playPauseBtn.evaluate().length}');
        print('Stop button: ${stopBtn.evaluate().length}');
        print('Progress slider: ${progressBar.evaluate().length}');
        
        // Wait for TTS synthesis
        print('\n=== STEP 5: Wait for TTS synthesis ===');
        
        for (int i = 0; i < 10; i++) {
          await tester.pump(const Duration(seconds: 2));
          
          // Check for any error messages
          final errorText = find.textContaining(RegExp(r'Error|Failed|exception', caseSensitive: false));
          final noVoiceError = find.textContaining('No engine available');
          
          if (errorText.evaluate().isNotEmpty) {
            print('⚠ Found error text: ${(errorText.evaluate().first.widget as Text).data}');
          }
          if (noVoiceError.evaluate().isNotEmpty) {
            print('✗ No voice available error - voice model not detected');
            break;
          }
          
          // Check if playing
          final pauseBtn = find.byIcon(Icons.pause);
          if (pauseBtn.evaluate().isNotEmpty) {
            print('✓ Playback appears to be active (pause button visible)');
            break;
          }
          
          print('  Waiting for synthesis... (${i+1}/10)');
        }
        
        // Final state check
        print('\n=== FINAL STATE ===');
        
        // Dump any text widgets for debugging
        final allText = find.byType(Text);
        print('Total Text widgets: ${allText.evaluate().length}');
        
        // Look for specific playback indicators
        final chapterText = find.textContaining('Chapter');
        final timeText = find.textContaining(RegExp(r'\d+:\d+'));
        
        if (chapterText.evaluate().isNotEmpty) {
          print('✓ Chapter text visible');
        }
        if (timeText.evaluate().isNotEmpty) {
          print('✓ Time display visible');
        }
      } else {
        print('✗ Could not find play button');
      }
    } else {
      print('✗ No books found in library');
    }

    print('\n=== TEST COMPLETE ===');
  });
}
