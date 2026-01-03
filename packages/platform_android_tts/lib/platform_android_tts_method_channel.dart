import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_android_tts_platform_interface.dart';

/// An implementation of [PlatformAndroidTtsPlatform] that uses method channels.
class MethodChannelPlatformAndroidTts extends PlatformAndroidTtsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('platform_android_tts');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
