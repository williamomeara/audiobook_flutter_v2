#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint platform_ios_tts.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'platform_ios_tts'
  s.version          = '0.0.1'
  s.summary          = 'iOS native TTS implementation for audiobook reader.'
  s.description      = <<-DESC
iOS native TTS implementation using ONNX Runtime and sherpa-onnx for neural TTS synthesis.
Supports Kokoro, Piper, and Supertonic TTS engines.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'

  # Vendored xcframeworks for TTS inference
  s.vendored_frameworks = 'Frameworks/onnxruntime.xcframework', 'Frameworks/sherpa-onnx.xcframework'
  
  # Download ONNX Runtime binaries from GitHub releases (too large for git)
  s.prepare_command = <<-CMD
    cd "$(dirname "$0")/../../.." && \
    if [ -x scripts/download_onnx_ios_binaries.sh ]; then
      ./scripts/download_onnx_ios_binaries.sh
    fi
  CMD
  
  # Note: Supertonic ONNX models are downloaded at runtime by the app
  # Uses same models as Android (unified ONNX-based approach).
  
  # Preserve module map folders
  s.preserve_paths = 'SherpaOnnxCApi', 'OnnxRuntimeCApi'
  
  # Module map for C API access (bridging headers not supported in frameworks)
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'SWIFT_INCLUDE_PATHS' => '$(PODS_TARGET_SRCROOT)/SherpaOnnxCApi $(PODS_TARGET_SRCROOT)/OnnxRuntimeCApi',
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/Frameworks/sherpa-onnx.xcframework/ios-arm64/Headers $(PODS_TARGET_SRCROOT)/SherpaOnnxCApi $(PODS_TARGET_SRCROOT)/Frameworks/onnxruntime.xcframework/Headers $(PODS_TARGET_SRCROOT)/OnnxRuntimeCApi'
  }
  s.swift_version = '5.0'
  
  # Frameworks required by ONNX Runtime
  s.frameworks = 'Accelerate'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'platform_ios_tts_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
