import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Application paths provider.
class AppPaths {
  AppPaths(this._baseDir);

  final Directory _baseDir;

  /// Get base application directory.
  Directory get baseDir => _baseDir;

  /// Get directory for a specific book.
  Directory bookDir(String bookId) => Directory('${_baseDir.path}/books/$bookId');

  /// Get audio cache directory.
  Directory get audioCacheDir => Directory('${_baseDir.path}/audio_cache');

  /// Get cache path string for AudioCache.
  String get cachePath => audioCacheDir.path;

  /// Get voice assets directory.
  Directory get voiceAssetsDir => Directory('${_baseDir.path}/voice_assets');

  /// Get temporary directory for downloads.
  Directory get tempDownloadsDir => Directory('${_baseDir.path}/temp_downloads');
}

/// App paths provider.
final appPathsProvider = FutureProvider<AppPaths>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  return AppPaths(dir);
});
