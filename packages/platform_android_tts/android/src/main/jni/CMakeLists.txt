# CMakeLists.txt for Supertonic TTS native library
#
# This builds supertonic_native.cpp which uses the ONNX Runtime
# already bundled with sherpa-onnx (libonnxruntime.so).

cmake_minimum_required(VERSION 3.18)
project(supertonic_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add the native library
add_library(supertonic_native SHARED
    supertonic_native.cpp
)

# Link against Android log library and dl (for dlopen/dlsym)
target_link_libraries(supertonic_native
    android
    log
    dl
)

# Note: We do NOT link against libonnxruntime.so directly.
# Instead, we use dlopen at runtime to get a handle to the already-loaded
# library (which sherpa-onnx loads). This avoids duplicate symbol issues.
