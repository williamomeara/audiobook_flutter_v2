import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:audiobook_flutter_v2/main.dart' as app;
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Comprehensive Settings Exploration', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    print('=== COMPREHENSIVE SETTINGS EXPLORATION ===\n');
    
    // Navigate to settings
    final settingsButton = find.byIcon(Icons.settings_outlined);
    await tester.tap(settingsButton);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // ==========================================
    // SECTION 1: TTS Settings
    // ==========================================
    print('--- TTS SETTINGS ---');
    
    final ttsTerms = ['Voice', 'TTS', 'Synthesis', 'Speed', 'Pitch', 'Engine', 'Piper', 'Kokoro', 'Supertonic'];
    for (final term in ttsTerms) {
      final finder = find.textContaining(term);
      if (finder.evaluate().isNotEmpty) {
        print('✓ $term: ${finder.evaluate().length} occurrences');
      }
    }

    // Check sliders and switches
    print('\nUI Controls:');
    print('  Sliders: ${find.byType(Slider).evaluate().length}');
    print('  Switches: ${find.byType(Switch).evaluate().length}');

    // ==========================================
    // SECTION 2: Scroll and check more content
    // ==========================================
    print('\n--- SCROLLING DOWN ---');
    final scrollable = find.byType(SingleChildScrollView);
    
    if (scrollable.evaluate().isNotEmpty) {
      // Scroll in steps and record what we find
      for (int i = 1; i <= 6; i++) {
        await tester.drag(scrollable.first, const Offset(0, -300));
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        
        // Check for interesting elements at this scroll position
        final downloadStatus = find.textContaining(RegExp(r'\d+\s*MB|\d+\s*GB|\d+%'));
        final buttons = find.byType(ElevatedButton);
        
        if (downloadStatus.evaluate().isNotEmpty || buttons.evaluate().isNotEmpty) {
          print('Scroll $i: Found ${downloadStatus.evaluate().length} size/progress indicators, ${buttons.evaluate().length} buttons');
        }
      }
    }

    // ==========================================
    // SECTION 3: Check for all visible content
    // ==========================================
    print('\n--- CONTENT ANALYSIS ---');
    
    // Check for important settings sections
    final settingsSections = [
      'Appearance', 'Dark mode', 'Theme',
      'Voice', 'Download', 'Speed', 'Pitch',
      'Playback', 'Auto', 'Sleep', 'Timer',
      'Developer', 'Debug', 'Version', 'About',
      'Clear', 'Reset', 'Cache', 'Database'
    ];
    
    List<String> foundSections = [];
    for (final section in settingsSections) {
      final finder = find.textContaining(section);
      if (finder.evaluate().isNotEmpty) {
        foundSections.add(section);
      }
    }
    print('Found settings: ${foundSections.join(", ")}');

    // ==========================================
    // SECTION 4: Check for actionable items
    // ==========================================
    print('\n--- ACTIONABLE ITEMS ---');
    
    // Count interactive elements
    final allSwitches = find.byType(Switch);
    final allSliders = find.byType(Slider);
    final allButtons = find.byType(ElevatedButton);
    final allTextButtons = find.byType(TextButton);
    final allIconButtons = find.byType(IconButton);
    
    print('Switches: ${allSwitches.evaluate().length}');
    print('Sliders: ${allSliders.evaluate().length}');
    print('Elevated Buttons: ${allButtons.evaluate().length}');
    print('Text Buttons: ${allTextButtons.evaluate().length}');
    print('Icon Buttons: ${allIconButtons.evaluate().length}');

    // ==========================================
    // SECTION 5: Navigate back and verify
    // ==========================================
    print('\n--- NAVIGATION CHECK ---');
    
    // Scroll back to top first
    for (int i = 0; i < 6; i++) {
      await tester.drag(scrollable.first, const Offset(0, 300));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
    }
    
    // Find and tap back button
    final backButton = find.byIcon(Icons.chevron_left);
    if (backButton.evaluate().isNotEmpty) {
      await tester.tap(backButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('Library'), findsOneWidget);
      print('✓ Successfully navigated back to Library');
    }

    print('\n=== EXPLORATION COMPLETE ===');
  });

  testWidgets('Free Books Screen Deep Dive', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    print('=== FREE BOOKS EXPLORATION ===\n');
    
    // Navigate to Free Books
    final freeBooksButton = find.text('Free Books');
    await tester.tap(freeBooksButton);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    print('--- SCREEN CONTENT ---');
    
    // Check for UI elements
    final textFields = find.byType(TextField);
    final listViews = find.byType(ListView);
    final gridViews = find.byType(GridView);
    final cards = find.byType(Card);
    
    print('TextFields (search): ${textFields.evaluate().length}');
    print('ListViews: ${listViews.evaluate().length}');
    print('GridViews: ${gridViews.evaluate().length}');
    print('Cards: ${cards.evaluate().length}');

    // Check for book-related content
    final bookTerms = ['Gutenberg', 'Download', 'Author', 'Title', 'Classic'];
    for (final term in bookTerms) {
      final finder = find.textContaining(term);
      if (finder.evaluate().isNotEmpty) {
        print('✓ Found "$term": ${finder.evaluate().length} matches');
      }
    }

    // Check for loading indicators
    final loadingIndicators = find.byType(CircularProgressIndicator);
    if (loadingIndicators.evaluate().isNotEmpty) {
      print('Loading indicators visible: ${loadingIndicators.evaluate().length}');
      await tester.pumpAndSettle(const Duration(seconds: 10));
    }

    // After potential loading, re-check content
    print('\n--- AFTER LOADING ---');
    print('Cards visible: ${find.byType(Card).evaluate().length}');
    
    // Navigate back
    final backButton = find.byIcon(Icons.chevron_left);
    if (backButton.evaluate().isNotEmpty) {
      await tester.tap(backButton.first);
      await tester.pumpAndSettle();
      print('\n✓ Navigated back to Library');
    }

    print('\n=== FREE BOOKS EXPLORATION COMPLETE ===');
  });
}
