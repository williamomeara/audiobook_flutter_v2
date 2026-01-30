import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import 'app/audio_service_handler.dart';
import 'app/quick_settings_service.dart';
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
import 'ui/widgets/mini_player_scaffold.dart';

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
  AppLogger.debug('initAudioService() called', name: 'AudioService');

  if (_audioHandler != null) {
    AppLogger.debug(
      'Already initialized, returning existing handler',
      name: 'AudioService',
    );
    return _audioHandler!;
  }
  if (_audioServiceInitializing) {
    AppLogger.debug(
      'Initialization in progress, waiting...',
      name: 'AudioService',
    );
    // Wait for initialization to complete
    while (_audioHandler == null && _audioServiceInitializing) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    AppLogger.debug(
      'Initialization complete, returning handler',
      name: 'AudioService',
    );
    return _audioHandler ?? AudioServiceHandler();
  }

  _audioServiceInitializing = true;
  AppLogger.debug('Starting AudioService.init()...', name: 'AudioService');

  try {
    _audioHandler = await AudioService.init(
      builder: () {
        AppLogger.debug(
          'Builder called, creating AudioServiceHandler',
          name: 'AudioService',
        );
        return AudioServiceHandler();
      },
      config: const AudioServiceConfig(
        androidNotificationChannelId:
            'com.williamomeara.audiobook.channel.audio',
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
    AppLogger.debug(
      'AudioService.init() completed successfully',
      name: 'AudioService',
    );
    AppLogger.debug(
      'Handler type: ${_audioHandler.runtimeType}',
      name: 'AudioService',
    );
  } catch (e, st) {
    AppLogger.error(
      'Failed to initialize audio service: $e',
      name: 'AudioService',
    );
    AppLogger.debug('Stack trace: $st', name: 'AudioService');
    // Create a minimal handler even if init fails
    _audioHandler = AudioServiceHandler();
    AppLogger.debug('Created fallback handler', name: 'AudioService');
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

  // Initialize QuickSettingsService for instant dark mode access.
  // This reads dark_mode from SharedPreferences before rendering.
  final initialDarkMode = await QuickSettingsService.initialize();

  // Setup logging - use WARNING level by default to reduce clutter
  // Change to Level.ALL for verbose debugging when needed
  Logger.root.level = Level.WARNING;
  Logger.root.onRecord.listen((record) {
    AppLogger.log(
      '${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}',
    );
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

  runApp(ProviderScope(child: AudiobookApp(initialDarkMode: initialDarkMode)));
}

class AudiobookApp extends ConsumerWidget {
  const AudiobookApp({super.key, required this.initialDarkMode});

  /// Initial dark mode value from QuickSettingsService.
  /// Used to avoid theme flash while settings load from SQLite.
  final bool initialDarkMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // Use settings.darkMode from provider (which may still be loading).
    // SettingsController initializes with QuickSettingsService.darkMode,
    // so the value should be correct from the first build.

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
      builder: (context, state) => const MiniPlayerScaffold(
        child: LibraryScreen(),
      ),
    ),
    GoRoute(
      path: '/book/:id',
      builder: (context, state) {
        final bookId = state.pathParameters['id']!;
        return MiniPlayerScaffold(
          child: BookDetailsScreen(bookId: bookId),
        );
      },
    ),
    GoRoute(
      path: '/playback/:bookId',
      builder: (context, state) {
        final bookId = state.pathParameters['bookId']!;
        // Support optional query params for navigating to specific position
        final chapterStr = state.uri.queryParameters['chapter'];
        final segmentStr = state.uri.queryParameters['segment'];
        final startPlaybackStr = state.uri.queryParameters['startPlayback'];
        final initialChapter =
            chapterStr != null ? int.tryParse(chapterStr) : null;
        final initialSegment =
            segmentStr != null ? int.tryParse(segmentStr) : null;
        final startPlayback = startPlaybackStr == 'true';
        return PlaybackScreen(
          bookId: bookId,
          initialChapter: initialChapter,
          initialSegment: initialSegment,
          startPlayback: startPlayback,
        );
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
