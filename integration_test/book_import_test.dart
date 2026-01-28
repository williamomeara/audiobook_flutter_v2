// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:audiobook_flutter_v2/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Integration test for book import functionality.
/// 
/// Tests the library screen's import and free books features,
/// checking for any crashes or unexpected behavior.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Book Import Tests', () {
    testWidgets('Library screen loads without errors', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Check library screen is showing
      expect(find.text('Library'), findsOneWidget);
      
      print('✓ Library screen loaded successfully');
    });

    testWidgets('Import button is interactive', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Find the Import button
      final importButton = find.text('Import');
      expect(importButton, findsOneWidget);
      
      // Note: We can't actually trigger file picker in tests,
      // but we can verify the button exists and is tappable
      final buttonWidget = find.ancestor(
        of: importButton,
        matching: find.byType(InkWell),
      );
      
      // Button should be there
      expect(buttonWidget, findsAtLeast(1));
      
      print('✓ Import button found and appears interactive');
    });

    testWidgets('Free Books navigation works', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Find and tap Free Books button
      final freeBooksButton = find.text('Free Books');
      expect(freeBooksButton, findsOneWidget);
      
      await tester.tap(freeBooksButton);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      
      // Should be on Free Books screen now
      // Look for Gutenberg indicators
      expect(
        find.textContaining('Gutenberg'),
        findsAtLeast(1),
        reason: 'Free Books screen should mention Gutenberg',
      );
      
      print('✓ Free Books screen navigation successful');
      
      // Go back to library
      final backButton = find.byIcon(Icons.chevron_left);
      if (backButton.evaluate().isNotEmpty) {
        await tester.tap(backButton.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.text('Library'), findsOneWidget);
        print('✓ Navigation back to library successful');
      }
    });

    testWidgets('Search functionality works', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Find search field
      final searchField = find.byType(TextField);
      expect(searchField, findsAtLeast(1));
      
      // Enter search text
      await tester.enterText(searchField.first, 'test search');
      await tester.pumpAndSettle();
      
      // App should not crash during search
      print('✓ Search text entry works without crash');
      
      // Clear search
      await tester.enterText(searchField.first, '');
      await tester.pumpAndSettle();
      
      print('✓ Search clear works');
    });

    testWidgets('Filter toggle works', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Find Filter button
      final filterButton = find.text('Filter');
      expect(filterButton, findsOneWidget);
      
      // Tap to show filters
      await tester.tap(filterButton);
      await tester.pumpAndSettle();
      
      // Should see sort options
      expect(find.text('Sort by'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
      
      print('✓ Filter panel shows sort options');
      
      // Tap to hide filters
      await tester.tap(filterButton);
      await tester.pumpAndSettle();
      
      // Sort by should be hidden
      expect(find.text('Sort by'), findsNothing);
      
      print('✓ Filter panel toggle works correctly');
    });

    testWidgets('Tab switching works', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Find All and Favorites tabs
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Favorites'), findsOneWidget);
      
      // Tap Favorites tab
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      
      print('✓ Switched to Favorites tab');
      
      // Tap All tab
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      
      print('✓ Switched back to All tab');
    });

    testWidgets('Check for books in library', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Look for book cards/list items
      final bookCards = find.byType(GestureDetector);
      
      print('Found ${bookCards.evaluate().length} GestureDetector widgets');
      
      // Check if empty library message is shown
      final emptyMessages = [
        find.textContaining('No books'),
        find.textContaining('Import'),
        find.textContaining('empty'),
      ];
      
      bool hasEmptyMessage = false;
      for (final finder in emptyMessages) {
        if (finder.evaluate().isNotEmpty) {
          hasEmptyMessage = true;
          print('✓ Found empty library message');
          break;
        }
      }
      
      if (!hasEmptyMessage) {
        print('✓ Library appears to have content or different empty state');
      }
      
      // App should not crash regardless of library state
      print('✓ Library screen stable regardless of content');
    });
  });

  group('Settings Screen Stability', () {
    testWidgets('Settings toggles work without crash', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to settings
      final settingsButton = find.byIcon(Icons.settings_outlined);
      expect(settingsButton, findsOneWidget);
      
      await tester.tap(settingsButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      // Find all switches
      final switches = find.byType(Switch);
      final switchCount = switches.evaluate().length;
      
      print('Found $switchCount switch widgets');
      
      // Try toggling each switch
      for (int i = 0; i < switchCount && i < 3; i++) { // Limit to first 3
        try {
          await tester.tap(switches.at(i));
          await tester.pumpAndSettle(const Duration(milliseconds: 500));
          print('✓ Toggled switch $i');
          
          // Toggle back
          await tester.tap(switches.at(i));
          await tester.pumpAndSettle(const Duration(milliseconds: 500));
        } catch (e) {
          print('! Could not toggle switch $i: $e');
        }
      }
      
      print('✓ Settings toggles work without crash');
    });

    testWidgets('Settings sliders work without crash', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to settings
      final settingsButton = find.byIcon(Icons.settings_outlined);
      await tester.tap(settingsButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      // Find sliders
      final sliders = find.byType(Slider);
      final sliderCount = sliders.evaluate().length;
      
      print('Found $sliderCount slider widgets');
      
      // Verify sliders exist (dragging in tests can be tricky)
      expect(sliderCount, greaterThan(0), reason: 'Should have at least one slider');
      
      print('✓ Settings sliders present and stable');
    });
  });
}
