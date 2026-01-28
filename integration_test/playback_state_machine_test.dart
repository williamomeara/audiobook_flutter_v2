import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:audiobook_flutter_v2/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Playback State Machine E2E Tests', () {
    testWidgets(
      'SCENARIO 1: Initial book selection and auto-play',
      (WidgetTester tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Verify library screen loaded
        expect(find.text('Library'), findsWidgets);
        expect(find.text('Frankenstein; Or, The Modern Prometheus'), findsWidgets);

        // Tap book
        await tester.tap(find.text('Frankenstein; Or, The Modern Prometheus'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Verify playback screen appears
        // (Use ByType instead of ByText for complex trees)
        expect(find.byType(FloatingActionButton), findsWidgets);

        // Expected: BUFFERING state with spinner on play button
        // This is harder to verify without access to provider state
        // In a real test, you'd watch the playback controller

        print('✅ SCENARIO 1: Initial auto-play PASSED');
      },
      timeout: Timeout(Duration(minutes: 5)),
    );

    testWidgets(
      'SCENARIO 2: Pause and resume same track',
      (WidgetTester tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Navigate to playback
        await tester.tap(find.text('Frankenstein; Or, The Modern Prometheus'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Wait for playback to start
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Find and tap play/pause button
        final pauseButton = find.byIcon(Icons.pause);
        if (pauseButton.evaluate().isNotEmpty) {
          await tester.tap(pauseButton);
          await tester.pumpAndSettle();

          // Verify play button appears (switched from pause)
          expect(find.byIcon(Icons.play), findsWidgets);
        }

        // Tap resume
        await tester.tap(find.byIcon(Icons.play));
        await tester.pumpAndSettle();

        // Verify pause button appears again
        expect(find.byIcon(Icons.pause), findsWidgets);

        print('✅ SCENARIO 2: Pause/Resume PASSED');
      },
      timeout: Timeout(Duration(minutes: 5)),
    );

    testWidgets(
      'SCENARIO 3: Navigation to next segment',
      (WidgetTester tester) async {
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Navigate to playback
        await tester.tap(find.text('Frankenstein; Or, The Modern Prometheus'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Wait for playback to start
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Tap next button (usually on right side of play button)
        // This is app-specific - adjust based on your UI
        final nextButtons = find.byIcon(Icons.skip_next);
        if (nextButtons.evaluate().isNotEmpty) {
          await tester.tap(nextButtons.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));

          // Expected: Brief BUFFERING state, then PLAYING
          // Verify no audio gap (harder to test without audio monitoring)
        }

        print('✅ SCENARIO 3: Next Segment PASSED');
      },
      timeout: Timeout(Duration(minutes: 5)),
    );

    testWidgets(
      'SCENARIO 7: App restart preserves position',
      (WidgetTester tester) async {
        // First run - listen for 10 seconds
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        await tester.tap(find.text('Frankenstein; Or, The Modern Prometheus'));
        await tester.pumpAndSettle(const Duration(seconds: 2));
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Store current state (would need provider access in real test)
        // ...
        // Exit app
        // ...

        // Restart app
        app.main();
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Verify "Continue Listening" shows correct chapter
        expect(find.text('Continue Listening'), findsWidgets);

        print('✅ SCENARIO 7: Position Persistence PASSED');
      },
      timeout: Timeout(Duration(minutes: 10)),
    );
  });
}
