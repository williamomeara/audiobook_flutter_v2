import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import 'app/settings_controller.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/library_screen.dart';
import 'ui/screens/book_details_screen.dart';
import 'ui/screens/playback_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/free_books_screen.dart';

void main() {
  // Setup logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}');
    if (record.error != null) {
      print('Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      print('StackTrace: ${record.stackTrace}');
    }
  });

  runApp(const ProviderScope(child: AudiobookApp()));
}

class AudiobookApp extends ConsumerWidget {
  const AudiobookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    
    return MaterialApp.router(
      title: 'Audiobook',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const LibraryScreen(),
    ),
    GoRoute(
      path: '/book/:id',
      builder: (context, state) {
        final bookId = state.pathParameters['id']!;
        return BookDetailsScreen(bookId: bookId);
      },
    ),
    GoRoute(
      path: '/playback/:bookId',
      builder: (context, state) {
        final bookId = state.pathParameters['bookId']!;
        return PlaybackScreen(bookId: bookId);
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/free-books',
      builder: (context, state) => const FreeBooksScreen(),
    ),
  ],
);
