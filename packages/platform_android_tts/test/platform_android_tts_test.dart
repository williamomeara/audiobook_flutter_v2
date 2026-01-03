import 'package:flutter_test/flutter_test.dart';
import 'package:platform_android_tts/platform_android_tts.dart';
import 'package:platform_android_tts/platform_android_tts_platform_interface.dart';
import 'package:platform_android_tts/platform_android_tts_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPlatformAndroidTtsPlatform
    with MockPlatformInterfaceMixin
    implements PlatformAndroidTtsPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final PlatformAndroidTtsPlatform initialPlatform = PlatformAndroidTtsPlatform.instance;

  test('$MethodChannelPlatformAndroidTts is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelPlatformAndroidTts>());
  });

  test('getPlatformVersion', () async {
    PlatformAndroidTts platformAndroidTtsPlugin = PlatformAndroidTts();
    MockPlatformAndroidTtsPlatform fakePlatform = MockPlatformAndroidTtsPlatform();
    PlatformAndroidTtsPlatform.instance = fakePlatform;

    expect(await platformAndroidTtsPlugin.getPlatformVersion(), '42');
  });
}
