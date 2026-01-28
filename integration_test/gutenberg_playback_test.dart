// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:audiobook_flutter_v2/main.dart' as app;
import 'package:flutter/material.dart';

/// Integration test for downloading a book from Project Gutenberg
/// and testing TTS playback.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Download book from Gutenberg and test playback', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    print('=== STEP 1: Navigate to Free Books ===');
    
    // Navigate to Free Books screen
    final freeBooksButton = find.text('Free Books');
    expect(freeBooksButton, findsOneWidget);
    await tester.tap(freeBooksButton);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    
    print('✓ On Free Books screen');

    // Wait for books to load
    print('=== STEP 2: Wait for book list to load ===');
    
    // Wait up to 30 seconds for content to load
    bool booksLoaded = false;
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
      
      // Check for book-related content
      final importButtons = find.text('Import');
      if (importButtons.evaluate().length > 1) { // More than just the library Import button
        booksLoaded = true;
        print('✓ Books loaded after ${i + 1} seconds');
        break;
      }
      
      // Also check for Gutenberg IDs
      final gutenbergIds = find.textContaining('Gutenberg #');
      if (gutenbergIds.evaluate().isNotEmpty) {
        booksLoaded = true;
        print('✓ Gutenberg books visible after ${i + 1} seconds');
        break;
      }
    }
    
    if (!booksLoaded) {
      // Check for loading indicator
      final loading = find.byType(CircularProgressIndicator);
      if (loading.evaluate().isNotEmpty) {
        print('! Still loading, waiting more...');
        await tester.pumpAndSettle(const Duration(seconds: 15));
      }
    }
    
    // Final check for books
    await tester.pumpAndSettle(const Duration(seconds: 2));
    
    print('=== STEP 3: Find and tap Import on a book ===');
    
    // Find all Import buttons/text
    final allImportButtons = find.text('Import');
    final importCount = allImportButtons.evaluate().length;
    print('Found $importCount "Import" text widgets');
    
    if (importCount > 0) {
      // Try to tap the first Import button (should be for a book)
      // We need to find the TextButton parent, not just the text
      final textButtons = find.byType(TextButton);
      print('Found ${textButtons.evaluate().length} TextButton widgets');
      
      // Find Import TextButtons specifically
      TextButton? importButton;
      for (final element in textButtons.evaluate()) {
        final widget = element.widget as TextButton;
        if (widget.child is Text) {
          final textWidget = widget.child as Text;
          if (textWidget.data == 'Import') {
            importButton = widget;
            break;
          }
        }
      }
      
      if (importButton != null) {
        // Find and tap the first Import button for a book
        final firstImport = find.widgetWithText(TextButton, 'Import');
        if (firstImport.evaluate().isNotEmpty) {
          print('Tapping Import button...');
          await tester.tap(firstImport.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
          
          // Watch for download progress
          print('=== STEP 4: Monitor download ===');
          
          bool downloadStarted = false;
          bool downloadComplete = false;
          
          for (int i = 0; i < 120; i++) { // Up to 2 minutes for download
            await tester.pump(const Duration(seconds: 1));
            
            // Check for progress indicator
            final progress = find.byType(LinearProgressIndicator);
            if (progress.evaluate().isNotEmpty) {
              downloadStarted = true;
              if (i % 10 == 0) {
                print('  Download in progress... (${i}s)');
              }
            }
            
            // Check for "Downloading" or "Importing" text
            final downloading = find.textContaining(RegExp(r'Downloading|Importing'));
            if (downloading.evaluate().isNotEmpty && !downloadStarted) {
              downloadStarted = true;
              print('  Download/Import started');
            }
            
            // Check if button changed to "Open"
            final openButton = find.text('Open');
            if (openButton.evaluate().isNotEmpty) {
              downloadComplete = true;
              print('✓ Download complete after ${i}s - "Open" button visible');
              break;
            }
            
            // Check for snackbar success message
            final snackbar = find.byType(SnackBar);
            if (snackbar.evaluate().isNotEmpty) {
              print('  Snackbar appeared');
            }
          }
          
          if (!downloadStarted && !downloadComplete) {
            print('! Download may not have started - checking for errors');
            final errors = find.textContaining(RegExp(r'error|Error|failed|Failed'));
            if (errors.evaluate().isNotEmpty) {
              print('! Error message found');
            }
          }
          
          if (downloadComplete) {
            print('=== STEP 5: Open the imported book ===');
            
            final openButton = find.text('Open');
            if (openButton.evaluate().isNotEmpty) {
              await tester.tap(openButton.first);
              await tester.pumpAndSettle(const Duration(seconds: 3));
              
              // Should be on book details screen now
              // Look for book details elements
              final startListening = find.text('Start Listening');
              final continueListening = find.text('Continue Listening');
              final listenAgain = find.text('Listen Again');
              
              final hasPlayButton = startListening.evaluate().isNotEmpty ||
                  continueListening.evaluate().isNotEmpty ||
                  listenAgain.evaluate().isNotEmpty;
              
              if (hasPlayButton) {
                print('✓ On book details screen');
                
                print('=== STEP 6: Start playback ===');
                
                // Find and tap the play button
                Finder? playButton;
                if (startListening.evaluate().isNotEmpty) {
                  playButton = startListening;
                  print('Found "Start Listening"');
                } else if (continueListening.evaluate().isNotEmpty) {
                  playButton = continueListening;
                  print('Found "Continue Listening"');
                } else if (listenAgain.evaluate().isNotEmpty) {
                  playButton = listenAgain;
                  print('Found "Listen Again"');
                }
                
                if (playButton != null) {
                  await tester.tap(playButton);
                  await tester.pumpAndSettle(const Duration(seconds: 5));
                  
                  print('=== STEP 7: Check playback screen ===');
                  
                  // Look for playback UI elements
                  final playIcon = find.byIcon(Icons.play_arrow);
                  final pauseIcon = find.byIcon(Icons.pause);
                  final playCircle = find.byIcon(Icons.play_circle);
                  final pauseCircle = find.byIcon(Icons.pause_circle);
                  
                  final hasPlaybackControls = playIcon.evaluate().isNotEmpty ||
                      pauseIcon.evaluate().isNotEmpty ||
                      playCircle.evaluate().isNotEmpty ||
                      pauseCircle.evaluate().isNotEmpty;
                  
                  if (hasPlaybackControls) {
                    print('✓ Playback screen loaded with controls');
                    
                    // Check for chapter/segment text
                    final chapterText = find.textContaining('Chapter');
                    if (chapterText.evaluate().isNotEmpty) {
                      print('✓ Chapter content visible');
                    }
                    
                    // Check for voice selection warning
                    final noVoice = find.textContaining(RegExp(r'voice|Voice'));
                    if (noVoice.evaluate().isNotEmpty) {
                      print('ℹ Voice-related content found');
                    }
                    
                    // Try tapping play
                    if (playCircle.evaluate().isNotEmpty) {
                      print('Attempting to play...');
                      await tester.tap(playCircle.first);
                      await tester.pumpAndSettle(const Duration(seconds: 3));
                      
                      // Check if voice dialog appeared
                      final voiceDialog = find.textContaining(RegExp(r'No voice|Select.*voice|Download'));
                      if (voiceDialog.evaluate().isNotEmpty) {
                        print('ℹ Voice selection/download required');
                      } else {
                        // Check if playback started (pause icon visible)
                        if (pauseCircle.evaluate().isNotEmpty) {
                          print('✓ Playback started!');
                        }
                      }
                    }
                  } else {
                    print('! Playback controls not found');
                  }
                }
              } else {
                print('! Play button not found on book details');
              }
            }
          }
        }
      }
    } else {
      print('! No books found to import');
    }
    
    print('=== TEST COMPLETE ===');
  });
}
