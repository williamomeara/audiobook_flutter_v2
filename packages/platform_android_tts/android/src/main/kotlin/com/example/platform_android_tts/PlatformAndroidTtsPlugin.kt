package com.example.platform_android_tts

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import com.example.platform_android_tts.generated.TtsNativeApi
import com.example.platform_android_tts.services.KokoroTtsService
import com.example.platform_android_tts.services.PiperTtsService
import com.example.platform_android_tts.services.SupertonicTtsService

/** PlatformAndroidTtsPlugin */
class PlatformAndroidTtsPlugin :
    FlutterPlugin,
    MethodCallHandler {
    
    private lateinit var channel: MethodChannel
    private var ttsApiImpl: TtsNativeApiImpl? = null
    
    // TTS services (in-process for now, will be moved to separate processes)
    private val kokoroService = KokoroTtsService()
    private val piperService = PiperTtsService()
    private val supertonicService = SupertonicTtsService()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "platform_android_tts")
        channel.setMethodCallHandler(this)
        
        // Register Pigeon API
        ttsApiImpl = TtsNativeApiImpl(
            kokoroService = kokoroService,
            piperService = piperService,
            supertonicService = supertonicService
        )
        TtsNativeApi.setUp(flutterPluginBinding.binaryMessenger, ttsApiImpl)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        if (call.method == "getPlatformVersion") {
            result.success("Android ${android.os.Build.VERSION.RELEASE}")
        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        TtsNativeApi.setUp(binding.binaryMessenger, null)
        ttsApiImpl?.cleanup()
        ttsApiImpl = null
    }
}
