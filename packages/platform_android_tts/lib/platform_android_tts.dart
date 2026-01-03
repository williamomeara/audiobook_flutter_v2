
import 'platform_android_tts_platform_interface.dart';

// Export generated Pigeon API
export 'generated/tts_api.g.dart';

class PlatformAndroidTts {
  Future<String?> getPlatformVersion() {
    return PlatformAndroidTtsPlatform.instance.getPlatformVersion();
  }
}
