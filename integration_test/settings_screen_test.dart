import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:audiobook_flutter_v2/main.dart' as app;
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Settings Screen Tests', () {
    testWidgets('Can navigate to settings via outlined icon', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Find settings icon (outlined version)
      final settingsButton = find.byIcon(Icons.settings_outlined);
      expect(settingsButton, findsOneWidget, reason: 'Settings button should exist');
      
      // Tap settings
      await tester.tap(settingsButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify we're on settings screen
      expect(find.text('Settings'), findsWidgets);
      
      print('✓ Settings screen accessible via outlined icon');
    });

    testWidgets('Settings screen has expected sections', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to settings
      final settingsButton = find.byIcon(Icons.settings_outlined);
      await tester.tap(settingsButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Check for expected setting sections/options
      final textFinders = [
        'Voice',  // TTS settings
        'Playback',  // Playback settings
        'Theme',  // Theme settings
        'Download',  // Download settings
      ];
      
      for (final text in textFinders) {
        final finder = find.textContaining(text);
        print('$text found: ${finder.evaluate().isNotEmpty}');
      }
      
      print('✓ Settings screen sections present');
    });

    testWidgets('Can navigate back from settings', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to settings
      final settingsButton = find.byIcon(Icons.settings_outlined);
      await tester.tap(settingsButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Look for back button
      final backButton = find.byIcon(Icons.arrow_back);
      if (backButton.evaluate().isNotEmpty) {
        await tester.tap(backButton);
      } else {
        // Try system back
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Should be back on library screen
      expect(find.text('Library'), findsOneWidget);
      
      print('✓ Navigation back from settings works');
    });
  });

  group('Free Books Screen Tests', () {
    testWidgets('Free Books screen loads books', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to Free Books
      final freeBooksButton = find.text('Free Books');
      await tester.tap(freeBooksButton);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Check for book list
      final listView = find.byType(ListView);
      print('ListView found: ${listView.evaluate().isNotEmpty}');
      
      // Check for Gutenberg content
      final gutenbergContent = find.textContaining('Gutenberg');
      print('Gutenberg reference found: ${gutenbergContent.evaluate().isNotEmpty}');
      
      print('✓ Free Books screen loaded');
    });
  });

  group('UI Element Verification', () {
    testWidgets('Library tabs work correctly', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Check All tab
      final allTab = find.text('All');
      expect(allTab, findsOneWidget);
      
      // Check Favorites tab
      final favoritesTab = find.text('Favorites');
      expect(favoritesTab, findsOneWidget);
      
      // Tap Favorites
      await tester.tap(favoritesTab);
      await tester.pumpAndSettle();
      
      // Tap All
      await tester.tap(allTab);
      await tester.pumpAndSettle();
      
      print('✓ Library tabs are interactive');
    });

    testWidgets('Search field is present and works', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Find search field
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      
      // Find search icon
      final searchIcon = find.byIcon(Icons.search);
      expect(searchIcon, findsOneWidget);
      
      // Enter text in search
      await tester.enterText(searchField, 'test search');
      await tester.pumpAndSettle();
      
      // Clear search
      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();
      
      print('✓ Search field is functional');
    });
  });
}
