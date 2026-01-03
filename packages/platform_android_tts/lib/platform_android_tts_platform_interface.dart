import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'platform_android_tts_method_channel.dart';

abstract class PlatformAndroidTtsPlatform extends PlatformInterface {
  /// Constructs a PlatformAndroidTtsPlatform.
  PlatformAndroidTtsPlatform() : super(token: _token);

  static final Object _token = Object();

  static PlatformAndroidTtsPlatform _instance = MethodChannelPlatformAndroidTts();

  /// The default instance of [PlatformAndroidTtsPlatform] to use.
  ///
  /// Defaults to [MethodChannelPlatformAndroidTts].
  static PlatformAndroidTtsPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PlatformAndroidTtsPlatform] when
  /// they register themselves.
  static set instance(PlatformAndroidTtsPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
