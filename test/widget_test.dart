// Basic Flutter widget test placeholder.
//
// Actual tests can be added as features are implemented.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:audiobook_flutter_v2/main.dart';

void main() {
  testWidgets('App loads without error', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(
      child: AudiobookApp(initialDarkMode: false),
    ));

    // Verify the app loaded (library screen should show)
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
