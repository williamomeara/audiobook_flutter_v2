import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import 'app/audio_service_handler.dart';
import 'app/settings_controller.dart';
import 'utils/app_logger.dart';
import 'ui/theme/app_theme.dart';
import 'ui/screens/library_screen.dart';
import 'ui/screens/book_details_screen.dart';
import 'ui/screens/playback_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/free_books_screen.dart';
import 'ui/screens/download_manager_screen.dart';
import 'ui/screens/developer_screen.dart';

/// Global audio handler instance for system media controls.
/// Initialized once in main() and shared across the app.
late AudioServiceHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Setup logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    AppLogger.log('${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}');
    if (record.error != null) {
      AppLogger.info('Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      AppLogger.info('StackTrace: ${record.stackTrace}');
    }
  });

  // Initialize audio service for system media controls.
  // This enables lock screen controls, notification shade, and
  // Bluetooth/headphone button handling.
  audioHandler = await AudioService.init(
    builder: () => AudioServiceHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.williamomeara.audiobook.channel.audio',
      androidNotificationChannelName: 'Audiobook Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_notification',
    ),
  );

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
    GoRoute(
      path: '/settings/downloads',
      builder: (context, state) => const DownloadManagerScreen(),
    ),
    GoRoute(
      path: '/settings/developer',
      builder: (context, state) => const DeveloperScreen(),
    ),
  ],
);
