// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:audiobook_flutter_v2/main.dart' as app;
import 'package:flutter/material.dart';

/// Test that imports Frankenstein from Gutenberg and stops.
/// After this test runs, pull the database with:
///   adb -s localhost:5555 shell "run-as io.eist.app cat app_flutter/eist.db" > local_dev/db_debug/eist.db
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Import Frankenstein from Gutenberg', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    print('=== IMPORT FRANKENSTEIN TEST ===\n');

    // Step 1: Go to Free Books
    print('=== STEP 1: Navigate to Free Books ===');
    
    final freeBooksButton = find.text('Free Books');
    if (freeBooksButton.evaluate().isEmpty) {
      print('✗ No "Free Books" button found');
      return;
    }
    
    await tester.tap(freeBooksButton.first);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    print('✓ Opened Free Books screen');

    // Step 2: Wait for books to load and import Frankenstein
    print('\n=== STEP 2: Import Frankenstein ===');
    
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    
    // The import button for the first book (Frankenstein)
    final importButton = find.text('Import');
    
    if (importButton.evaluate().isNotEmpty) {
      print('Found ${importButton.evaluate().length} "Import" buttons');
      await tester.tap(importButton.first);  // First book is Frankenstein
      print('Tapped Import on Frankenstein...');
      
      // Wait for import to complete
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
        
        // "Open" means it was imported
        final openButton = find.text('Open');
        if (openButton.evaluate().isNotEmpty) {
          print('✓ Frankenstein imported successfully! (${i+1}s)');
          break;
        }
        
        if (i % 5 == 0) {
          print('  Waiting for import... (${i+1}s)');
        }
      }
    } else {
      final openButton = find.text('Open');
      if (openButton.evaluate().isNotEmpty) {
        print('✓ Frankenstein already imported');
      } else {
        print('✗ No Import or Open button found');
        return;
      }
    }

    // Step 3: Open Frankenstein to view its details
    print('\n=== STEP 3: Open Book Details ===');
    
    final openButton = find.text('Open');
    if (openButton.evaluate().isNotEmpty) {
      await tester.tap(openButton.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      print('✓ Opened book details');
    }

    // Step 4: List chapters
    print('\n=== STEP 4: List chapters ===');
    
    // Log all text widgets to find chapter names
    final allTexts = find.byType(Text);
    print('Found ${allTexts.evaluate().length} text widgets:');
    
    final texts = <String>[];
    for (final el in allTexts.evaluate()) {
      final text = el.widget as Text;
      if (text.data != null && text.data!.trim().isNotEmpty) {
        texts.add(text.data!);
      }
    }
    
    // Filter for chapter-like entries
    final chapterTexts = texts.where((t) => 
      t.toLowerCase().contains('chapter') || 
      t.toLowerCase().contains('letter') ||
      t.toLowerCase().contains('walton')
    ).toList();
    
    print('\nChapter-related texts:');
    for (final t in chapterTexts) {
      print('  - $t');
    }

    print('\n=== Import complete! ===');
    print('You can now pull the database with:');
    print('  adb -s localhost:5555 exec-out run-as io.eist.app cat app_flutter/eist.db > local_dev/db_debug/eist.db');
    
    // Leave the app open for a moment
    await tester.pump(const Duration(seconds: 5));
  });
}
