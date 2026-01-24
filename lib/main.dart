import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// Initialized lazily to avoid blocking app startup.
AudioServiceHandler? _audioHandler;

/// Get the audio handler, creating it if needed.
/// This returns the initialized handler or null if not yet initialized.
AudioServiceHandler? get audioHandler => _audioHandler;

/// Flag to track if initialization is in progress.
bool _audioServiceInitializing = false;

/// Initialize the audio service. Safe to call multiple times.
Future<AudioServiceHandler> initAudioService() async {
  // ignore: avoid_print
  print('[AudioService] initAudioService() called');
  
  if (_audioHandler != null) {
    // ignore: avoid_print
    print('[AudioService] Already initialized, returning existing handler');
    return _audioHandler!;
  }
  if (_audioServiceInitializing) {
    // ignore: avoid_print
    print('[AudioService] Initialization in progress, waiting...');
    // Wait for initialization to complete
    while (_audioHandler == null && _audioServiceInitializing) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    // ignore: avoid_print
    print('[AudioService] Initialization complete, returning handler');
    return _audioHandler ?? AudioServiceHandler();
  }
  
  _audioServiceInitializing = true;
  // ignore: avoid_print
  print('[AudioService] Starting AudioService.init()...');
  
  try {
    _audioHandler = await AudioService.init(
      builder: () {
        // ignore: avoid_print
        print('[AudioService] Builder called, creating AudioServiceHandler');
        return AudioServiceHandler();
      },
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.williamomeara.audiobook.channel.audio',
        androidNotificationChannelName: 'Audiobook Playback',
        // When false, notification can be dismissed by user swipe
        // When true, notification is "ongoing" and cannot be dismissed
        // Note: androidNotificationOngoing only applies when foreground service is running
        androidNotificationOngoing: false,
        // Keep notification visible while paused so user can resume easily
        androidStopForegroundOnPause: false,
        androidNotificationIcon: 'drawable/ic_notification',
      ),
    );
    // ignore: avoid_print
    print('[AudioService] AudioService.init() completed successfully');
    // ignore: avoid_print
    print('[AudioService] Handler type: ${_audioHandler.runtimeType}');
  } catch (e, st) {
    // ignore: avoid_print
    print('[AudioService] Failed to initialize audio service: $e');
    // ignore: avoid_print
    print('[AudioService] Stack trace: $st');
    // Create a minimal handler even if init fails
    _audioHandler = AudioServiceHandler();
    // ignore: avoid_print
    print('[AudioService] Created fallback handler');
  }
  _audioServiceInitializing = false;
  return _audioHandler!;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait orientation by default (except playback screen)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

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

  // Don't block app startup - initialize audio service lazily.
  // The service will be initialized when first needed (e.g., playback starts).
  // This avoids the VRI redraw loop issue on some devices.

  runApp(const ProviderScope(child: AudiobookApp()));
}

class AudiobookApp extends ConsumerWidget {
  const AudiobookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    
    return MaterialApp.router(
      title: 'Éist',
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
