# Keep audio_service classes
-keep class com.ryanheise.audioservice.** { *; }
-keep class androidx.media.** { *; }

# Keep just_audio classes
-keep class com.google.android.exoplayer2.** { *; }
-keep class com.ryanheise.just_audio.** { *; }

# Keep sherpa-onnx classes
-keep class com.k2fsa.sherpa.onnx.** { *; }

# Keep Google Play Billing classes
-keep class com.android.vending.billing.** { *; }
-keep class com.google.android.gms.** { *; }

# Keep RevenueCat classes (if using RevenueCat)
-keep class com.revenuecat.purchases.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
