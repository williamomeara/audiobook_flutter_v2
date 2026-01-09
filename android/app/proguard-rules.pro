# Keep audio_service classes
-keep class com.ryanheise.audioservice.** { *; }
-keep class androidx.media.** { *; }

# Keep just_audio classes
-keep class com.google.android.exoplayer2.** { *; }
-keep class com.ryanheise.just_audio.** { *; }

# Keep sherpa-onnx classes
-keep class com.k2fsa.sherpa.onnx.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
