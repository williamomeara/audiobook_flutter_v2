import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:audiobook_flutter_v2/main.dart' as app;
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Full app navigation flow', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    print('=== STEP 1: Library Screen ===');
    
    // Check we're on library screen
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Free Books'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    print('✓ Library screen elements found');

    // Find and tap settings
    print('=== STEP 2: Navigate to Settings ===');
    final settingsButton = find.byIcon(Icons.settings_outlined);
    expect(settingsButton, findsOneWidget);
    await tester.tap(settingsButton);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify settings screen
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Dark mode'), findsOneWidget);
    print('✓ Settings screen elements found');

    // Navigate back
    print('=== STEP 3: Navigate back to Library ===');
    final backButton = find.byIcon(Icons.chevron_left);
    expect(backButton, findsOneWidget);
    await tester.tap(backButton);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify back on library
    expect(find.text('Library'), findsOneWidget);
    print('✓ Back on Library screen');

    // Navigate to Free Books
    print('=== STEP 4: Navigate to Free Books ===');
    final freeBooksButton = find.text('Free Books');
    await tester.tap(freeBooksButton);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Look for Free Books screen content
    // Check for search field or book list
    final gridView = find.byType(GridView);
    final listView = find.byType(ListView);
    print('GridView found: ${gridView.evaluate().isNotEmpty}');
    print('ListView found: ${listView.evaluate().isNotEmpty}');
    print('✓ Free Books screen loaded');

    // Navigate back
    print('=== STEP 5: Navigate back from Free Books ===');
    final freeBackButton = find.byIcon(Icons.chevron_left);
    if (freeBackButton.evaluate().isNotEmpty) {
      await tester.tap(freeBackButton.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    } else {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    expect(find.text('Library'), findsOneWidget);
    print('✓ Back on Library screen');

    // Test Library tabs
    print('=== STEP 6: Test Library Tabs ===');
    final favoritesTab = find.text('Favorites');
    await tester.tap(favoritesTab);
    await tester.pumpAndSettle();
    print('✓ Tapped Favorites tab');

    final allTab = find.text('All');
    await tester.tap(allTab);
    await tester.pumpAndSettle();
    print('✓ Tapped All tab');

    // Test search
    print('=== STEP 7: Test Search Field ===');
    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'test');
    await tester.pumpAndSettle();
    print('✓ Search text entered');

    await tester.enterText(searchField, '');
    await tester.pumpAndSettle();
    print('✓ Search cleared');

    print('=== ALL NAVIGATION TESTS PASSED ===');
  });
}
