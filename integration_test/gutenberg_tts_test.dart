// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:audiobook_flutter_v2/main.dart' as app;
import 'package:flutter/material.dart';

/// Integration test that imports a book from Gutenberg and tests playback.
/// 
/// This test focuses on:
/// 1. Importing a book from Project Gutenberg
/// 2. Opening the book for playback  
/// 3. Verifying playback screen loads
/// 4. Checking TTS synthesis attempt (may fail if no voice model)
///
/// Note: Voice model needs to be pushed via ADB after app install:
///   ./scripts/push_piper_model.sh
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Gutenberg import and playback test', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    print('=== GUTENBERG IMPORT & PLAYBACK TEST ===\n');

    // Step 1: Go to Free Books
    print('=== STEP 1: Navigate to Free Books ===');
    
    // Look for the "Free Books" text button in the library screen header
    final freeBooksButton = find.text('Free Books');
    if (freeBooksButton.evaluate().isEmpty) {
      print('✗ No "Free Books" button found');
      // Log what we can find
      final allText = find.byType(Text);
      print('Found ${allText.evaluate().length} Text widgets');
      for (final widget in allText.evaluate().take(10)) {
        final text = widget.widget as Text;
        print('  - Text: "${text.data}"');
      }
      return;
    }
    
    await tester.tap(freeBooksButton.first);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    print('✓ Opened Free Books screen');

    // Step 2: Find and import a book
    print('\n=== STEP 2: Import a book from Gutenberg ===');
    
    // Wait for books to load
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    
    // Debug: Log what's visible
    final allTexts = find.byType(Text);
    print('Found ${allTexts.evaluate().length} text widgets');
    for (final el in allTexts.evaluate().take(20)) {
      final text = el.widget as Text;
      if (text.data != null && text.data!.isNotEmpty) {
        print('  Text: "${text.data}"');
      }
    }
    
    // Look for "Import" text button
    final importTextButton = find.text('Import');
    
    if (importTextButton.evaluate().isNotEmpty) {
      print('Found ${importTextButton.evaluate().length} "Import" buttons');
      await tester.tap(importTextButton.first);
      print('Tapped Import button, waiting for download...');
      
      // Wait for import (can take 10-30 seconds)
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
        
        // Check for success indicators - "Open" means it was imported
        final openButton = find.text('Open');
        final importingText = find.text('Importing…');
        final downloadingText = find.text('Downloading…');
        
        // Check for snackbar messages
        final successSnackbar = find.textContaining(RegExp(r'added|imported|success', caseSensitive: false));
        
        if (openButton.evaluate().isNotEmpty) {
          print('✓ Book import completed - found "Open" button (${i+1}s)');
          break;
        }
        
        if (importingText.evaluate().isNotEmpty || downloadingText.evaluate().isNotEmpty) {
          if (i % 5 == 0) {
            print('  Import in progress... (${i+1}s)');
          }
        }
        
        if (successSnackbar.evaluate().isNotEmpty) {
          print('✓ Success message found (${i+1}s)');
          break;
        }
        
        if (i % 10 == 9) {
          print('  Still waiting... (${i+1}s)');
        }
      }
    } else {
      print('✗ No "Import" button found');
      // Check if books are already imported
      final openButton = find.text('Open');
      if (openButton.evaluate().isNotEmpty) {
        print('Found "Open" buttons - books may already be imported');
      }
    }
    
    // Step 3: Go back to library
    print('\n=== STEP 3: Return to Library ===');
    
    final backButton = find.byIcon(Icons.arrow_back);
    if (backButton.evaluate().isNotEmpty) {
      await tester.tap(backButton.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      print('✓ Returned to library');
    }
    
    // Step 4: Find the imported book
    print('\n=== STEP 4: Find imported book ===');
    
    await tester.pumpAndSettle(const Duration(seconds: 2));
    
    // Log what's in the library
    final allTexts2 = find.byType(Text);
    print('Library screen has ${allTexts2.evaluate().length} text widgets:');
    for (final el in allTexts2.evaluate().take(20)) {
      final text = el.widget as Text;
      if (text.data != null && text.data!.isNotEmpty) {
        print('  Text: "${text.data}"');
      }
    }
    
    // Look for Frankenstein (the first book in Gutenberg list)
    final frankensteinText = find.textContaining('Frankenstein');
    final mobyDickText = find.textContaining('Moby');
    final christmasCarolText = find.textContaining('Christmas Carol');
    
    Finder? bookToTap;
    String? bookName;
    
    if (frankensteinText.evaluate().isNotEmpty) {
      bookToTap = frankensteinText.first;
      bookName = 'Frankenstein';
    } else if (mobyDickText.evaluate().isNotEmpty) {
      bookToTap = mobyDickText.first;
      bookName = 'Moby Dick';
    } else if (christmasCarolText.evaluate().isNotEmpty) {
      bookToTap = christmasCarolText.first;
      bookName = 'A Christmas Carol';
    }
    
    if (bookToTap != null) {
      print('✓ Found book: $bookName');
      await tester.tap(bookToTap);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      print('✓ Opened book details');
      
      // Step 5: Start playback
      print('\n=== STEP 5: Start playback ===');
      
      final playButton = find.byIcon(Icons.play_arrow);
      final playFab = find.byType(FloatingActionButton);
      final readButton = find.textContaining(RegExp(r'Read|Play|Listen|Start', caseSensitive: false));
      
      Finder? startButton;
      if (playButton.evaluate().isNotEmpty) {
        startButton = playButton.first;
        print('Found play_arrow icon');
      } else if (playFab.evaluate().isNotEmpty) {
        startButton = playFab.first;
        print('Found FloatingActionButton');
      } else if (readButton.evaluate().isNotEmpty) {
        startButton = readButton.first;
        print('Found Read/Play button text');
      }
      
      if (startButton != null) {
        await tester.tap(startButton);
        await tester.pumpAndSettle(const Duration(seconds: 5));
        print('✓ Tapped play button');
        
        // Step 6: Monitor playback
        print('\n=== STEP 6: Monitor playback ===');
        
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(seconds: 2));
          
          // Look for playback indicators
          final pauseButton = find.byIcon(Icons.pause);
          final stopButton = find.byIcon(Icons.stop);
          final progressSlider = find.byType(Slider);
          
          // Look for errors
          final errorText = find.textContaining(RegExp(r'Error|Failed|exception|No engine', caseSensitive: false));
          
          if (pauseButton.evaluate().isNotEmpty) {
            print('✓ PLAYBACK ACTIVE - Pause button visible!');
          }
          
          if (errorText.evaluate().isNotEmpty) {
            // Extract the error text
            final errorWidget = errorText.evaluate().first.widget;
            if (errorWidget is Text) {
              print('⚠ Error: ${errorWidget.data}');
            }
          }
          
          // Look for chapter/position info
          final chapterText = find.textContaining('Chapter');
          final timeText = find.textContaining(RegExp(r'\d+:\d+'));
          
          if (chapterText.evaluate().isNotEmpty || timeText.evaluate().isNotEmpty) {
            print('✓ Found chapter/time info');
          }
          
          if (i % 5 == 4) {
            print('  Monitoring... (${(i+1)*2}s)');
          }
        }
        
        // Final state dump
        print('\n=== FINAL STATE ===');
        final pauseVisible = find.byIcon(Icons.pause).evaluate().isNotEmpty;
        final playVisible = find.byIcon(Icons.play_arrow).evaluate().isNotEmpty;
        
        print('Pause button visible: $pauseVisible');
        print('Play button visible: $playVisible');
        
        if (pauseVisible) {
          print('\n🎉 SUCCESS: TTS playback is working!');
        } else if (playVisible) {
          print('\n⏸ Playback paused or not started');
        } else {
          print('\n❓ Unknown playback state');
        }
      } else {
        print('✗ No play button found');
      }
    } else {
      print('✗ No book found in library');
    }

    print('\n=== TEST COMPLETE ===');
  });
}
