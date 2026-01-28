import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:audiobook_flutter_v2/main.dart' as app;
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TTS Settings exploration', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    print('=== Exploring TTS Settings ===');
    
    // Navigate to settings
    final settingsButton = find.byIcon(Icons.settings_outlined);
    await tester.tap(settingsButton);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Look for Voice/TTS section
    print('Looking for Voice/TTS settings...');
    
    // Scroll to find voice settings
    final scrollable = find.byType(SingleChildScrollView);
    if (scrollable.evaluate().isNotEmpty) {
      print('Scrollable found, searching for TTS settings...');
    }
    
    // Check what text we can find related to TTS
    final ttsRelated = [
      'Voice', 'TTS', 'Speech', 'Synthesis', 'Engine',
      'Speed', 'Pitch', 'Download', 'Piper', 'Kokoro', 'Supertonic'
    ];
    
    for (final term in ttsRelated) {
      final finder = find.textContaining(term);
      if (finder.evaluate().isNotEmpty) {
        print('✓ Found: $term (${finder.evaluate().length} matches)');
      }
    }

    // Look for sliders (speed/pitch controls)
    final sliders = find.byType(Slider);
    print('Sliders found: ${sliders.evaluate().length}');

    // Look for dropdowns
    final dropdowns = find.byType(DropdownButton);
    print('Dropdowns found: ${dropdowns.evaluate().length}');

    // Look for switches
    final switches = find.byType(Switch);
    print('Switches found: ${switches.evaluate().length}');

    // Try scrolling down to see more settings
    await tester.drag(scrollable.first, const Offset(0, -500));
    await tester.pumpAndSettle();
    
    print('After scroll:');
    for (final term in ttsRelated) {
      final finder = find.textContaining(term);
      if (finder.evaluate().isNotEmpty) {
        print('✓ Found: $term (${finder.evaluate().length} matches)');
      }
    }

    print('✓ TTS Settings exploration complete');
  });

  testWidgets('Voice download status check', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Navigate to settings
    final settingsButton = find.byIcon(Icons.settings_outlined);
    await tester.tap(settingsButton);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Look for download-related elements
    print('=== Checking Voice Download UI ===');
    
    final downloadRelated = [
      'Download', 'Progress', 'Available', 'Installed', 
      'Voice', 'MB', 'GB', '%'
    ];
    
    for (final term in downloadRelated) {
      final finder = find.textContaining(term);
      if (finder.evaluate().isNotEmpty) {
        print('Found: $term (${finder.evaluate().length} matches)');
      }
    }

    // Check for progress indicators
    final progressIndicators = find.byType(CircularProgressIndicator);
    final linearProgress = find.byType(LinearProgressIndicator);
    print('Circular progress indicators: ${progressIndicators.evaluate().length}');
    print('Linear progress indicators: ${linearProgress.evaluate().length}');

    print('✓ Voice download UI check complete');
  });

  testWidgets('Playback settings exploration', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Navigate to settings
    final settingsButton = find.byIcon(Icons.settings_outlined);
    await tester.tap(settingsButton);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    print('=== Exploring Playback Settings ===');

    // Look for playback-related settings
    final playbackTerms = [
      'Playback', 'Speed', 'Auto', 'Skip', 'Sleep', 'Timer',
      'Continue', 'Background', 'Audio', 'Media'
    ];
    
    for (final term in playbackTerms) {
      final finder = find.textContaining(term);
      if (finder.evaluate().isNotEmpty) {
        print('Found: $term');
      }
    }

    // Check for speed slider specifically
    final speedSlider = find.byType(Slider);
    print('Sliders (may include speed): ${speedSlider.evaluate().length}');

    print('✓ Playback settings exploration complete');
  });

  testWidgets('Developer options check', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Navigate to settings
    final settingsButton = find.byIcon(Icons.settings_outlined);
    await tester.tap(settingsButton);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    print('=== Checking Developer Options ===');

    // Scroll to bottom where developer options usually are
    final scrollable = find.byType(SingleChildScrollView);
    
    // Scroll down multiple times to reach bottom
    for (int i = 0; i < 5; i++) {
      await tester.drag(scrollable.first, const Offset(0, -400));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
    }

    // Check for developer-related UI
    final devTerms = [
      'Developer', 'Debug', 'Version', 'About', 'Database', 
      'Clear', 'Reset', 'Cache', 'Logs'
    ];
    
    for (final term in devTerms) {
      final finder = find.textContaining(term);
      if (finder.evaluate().isNotEmpty) {
        print('Found: $term');
      }
    }

    // Look for version info
    final versionFinder = find.textContaining(RegExp(r'\d+\.\d+\.\d+'));
    print('Version-like text found: ${versionFinder.evaluate().length}');

    print('✓ Developer options check complete');
  });
}
