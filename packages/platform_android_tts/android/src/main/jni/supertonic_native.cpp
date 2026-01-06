/*
 * SupertonicNative.cpp - JNI bindings for Supertonic TTS using ONNX Runtime
 *
 * This implementation uses the ONNX Runtime already bundled with sherpa-onnx,
 * avoiding native library conflicts. It dynamically links to libonnxruntime.so
 * at runtime using dlopen/dlsym.
 *
 * Supertonic Pipeline:
 * 1. text_encoder.onnx: Text tokens → hidden states
 * 2. duration_predictor.onnx: Hidden states → durations
 * 3. vector_estimator.onnx: Hidden + durations → latent vectors
 * 4. vocoder.onnx: Latent vectors → audio samples
 */

#include <jni.h>
#include <android/log.h>
#include <dlfcn.h>
#include <string>
#include <vector>
#include <cstdint>
#include <memory>
#include <fstream>
#include <sstream>
#include <map>
#include <cmath>
#include <cstdlib>

#define LOG_TAG "SupertonicNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

// ONNX Runtime C API type definitions - minimal subset needed for inference
// Based on ONNX Runtime v17 API (ORT_API_VERSION = 17)

// Opaque types (forward declarations)
typedef struct OrtEnv OrtEnv;
typedef struct OrtStatus OrtStatus;
typedef struct OrtMemoryInfo OrtMemoryInfo;
typedef struct OrtSession OrtSession;
typedef struct OrtValue OrtValue;
typedef struct OrtRunOptions OrtRunOptions;
typedef struct OrtTypeInfo OrtTypeInfo;
typedef struct OrtTensorTypeAndShapeInfo OrtTensorTypeAndShapeInfo;
typedef struct OrtSessionOptions OrtSessionOptions;
typedef struct OrtCustomOpDomain OrtCustomOpDomain;
typedef struct OrtAllocator OrtAllocator;
typedef struct OrtModelMetadata OrtModelMetadata;
typedef struct OrtThreadingOptions OrtThreadingOptions;
typedef struct OrtArenaCfg OrtArenaCfg;
typedef struct OrtPrepackedWeightsContainer OrtPrepackedWeightsContainer;
typedef struct OrtTensorRTProviderOptionsV2 OrtTensorRTProviderOptionsV2;
typedef struct OrtCUDAProviderOptionsV2 OrtCUDAProviderOptionsV2;
typedef struct OrtCANNProviderOptions OrtCANNProviderOptions;
typedef struct OrtDnnlProviderOptions OrtDnnlProviderOptions;
typedef struct OrtOp OrtOp;
typedef struct OrtOpAttr OrtOpAttr;
typedef struct OrtLogger OrtLogger;
typedef struct OrtShapeInferContext OrtShapeInferContext;
typedef struct OrtKernelInfo OrtKernelInfo;
typedef struct OrtKernelContext OrtKernelContext;
typedef struct OrtIoBinding OrtIoBinding;
typedef struct OrtMapTypeInfo OrtMapTypeInfo;
typedef struct OrtSequenceTypeInfo OrtSequenceTypeInfo;
typedef struct OrtOptionalTypeInfo OrtOptionalTypeInfo;

// Enums
typedef enum {
    ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED = 0,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT = 1,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8 = 2,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8 = 3,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16 = 4,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT16 = 5,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32 = 6,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64 = 7,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING = 8,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL = 9,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16 = 10,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE = 11,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT32 = 12,
    ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT64 = 13,
} ONNXTensorElementDataType;

typedef enum {
    ONNX_TYPE_UNKNOWN = 0,
    ONNX_TYPE_TENSOR = 1,
    ONNX_TYPE_SEQUENCE = 2,
    ONNX_TYPE_MAP = 3,
    ONNX_TYPE_OPAQUE = 4,
    ONNX_TYPE_SPARSETENSOR = 5,
    ONNX_TYPE_OPTIONAL = 6
} ONNXType;

typedef enum {
    ORT_LOGGING_LEVEL_VERBOSE = 0,
    ORT_LOGGING_LEVEL_INFO = 1,
    ORT_LOGGING_LEVEL_WARNING = 2,
    ORT_LOGGING_LEVEL_ERROR = 3,
    ORT_LOGGING_LEVEL_FATAL = 4,
} OrtLoggingLevel;

typedef enum {
    ORT_OK = 0,
    ORT_FAIL = 1,
    ORT_INVALID_ARGUMENT = 2,
    ORT_NO_SUCHFILE = 3,
    ORT_NO_MODEL = 4,
    ORT_ENGINE_ERROR = 5,
    ORT_RUNTIME_EXCEPTION = 6,
    ORT_INVALID_PROTOBUF = 7,
    ORT_MODEL_LOADED = 8,
    ORT_NOT_IMPLEMENTED = 9,
    ORT_INVALID_GRAPH = 10,
    ORT_EP_FAIL = 11,
} OrtErrorCode;

typedef enum {
    OrtInvalidAllocator = -1,
    OrtDeviceAllocator = 0,
    OrtArenaAllocator = 1
} OrtAllocatorType;

typedef enum {
    OrtMemTypeCPUInput = -2,
    OrtMemTypeCPUOutput = -1,
    OrtMemTypeCPU = OrtMemTypeCPUOutput,
    OrtMemTypeDefault = 0,
} OrtMemType;

typedef enum {
    ORT_DISABLE_ALL = 0,
    ORT_ENABLE_BASIC = 1,
    ORT_ENABLE_EXTENDED = 2,
    ORT_ENABLE_ALL = 99
} GraphOptimizationLevel;

// OrtApi struct - function pointer table
// The order MUST match the official ONNX Runtime header exactly!
struct OrtApi {
    // Index 0-2: OrtStatus functions
    OrtStatus* (*CreateStatus)(OrtErrorCode code, const char* msg);
    OrtErrorCode (*GetErrorCode)(const OrtStatus* status);
    const char* (*GetErrorMessage)(const OrtStatus* status);
    
    // Index 3-4: OrtEnv creation
    OrtStatus* (*CreateEnv)(OrtLoggingLevel log_severity_level, const char* logid, OrtEnv** out);
    OrtStatus* (*CreateEnvWithCustomLogger)(void* logging_function, void* logger_param, 
                                            OrtLoggingLevel log_severity_level, const char* logid, OrtEnv** out);
    
    // Index 5-6: Telemetry
    OrtStatus* (*EnableTelemetryEvents)(const OrtEnv* env);
    OrtStatus* (*DisableTelemetryEvents)(const OrtEnv* env);
    
    // Index 7-8: Session creation
    OrtStatus* (*CreateSession)(const OrtEnv* env, const char* model_path,
                                const OrtSessionOptions* options, OrtSession** out);
    OrtStatus* (*CreateSessionFromArray)(const OrtEnv* env, const void* model_data, size_t model_data_length,
                                         const OrtSessionOptions* options, OrtSession** out);
    
    // Index 9: Run
    OrtStatus* (*Run)(OrtSession* session, const OrtRunOptions* run_options,
                      const char* const* input_names, const OrtValue* const* inputs, size_t input_len,
                      const char* const* output_names, size_t output_names_len, OrtValue** outputs);
    
    // Index 10-26: SessionOptions functions
    OrtStatus* (*CreateSessionOptions)(OrtSessionOptions** options);
    OrtStatus* (*SetOptimizedModelFilePath)(OrtSessionOptions* options, const char* optimized_model_filepath);
    OrtStatus* (*CloneSessionOptions)(const OrtSessionOptions* in_options, OrtSessionOptions** out_options);
    OrtStatus* (*SetSessionExecutionMode)(OrtSessionOptions* options, int execution_mode);
    OrtStatus* (*EnableProfiling)(OrtSessionOptions* options, const char* profile_file_prefix);
    OrtStatus* (*DisableProfiling)(OrtSessionOptions* options);
    OrtStatus* (*EnableMemPattern)(OrtSessionOptions* options);
    OrtStatus* (*DisableMemPattern)(OrtSessionOptions* options);
    OrtStatus* (*EnableCpuMemArena)(OrtSessionOptions* options);
    OrtStatus* (*DisableCpuMemArena)(OrtSessionOptions* options);
    OrtStatus* (*SetSessionLogId)(OrtSessionOptions* options, const char* logid);
    OrtStatus* (*SetSessionLogVerbosityLevel)(OrtSessionOptions* options, int session_log_verbosity_level);
    OrtStatus* (*SetSessionLogSeverityLevel)(OrtSessionOptions* options, int session_log_severity_level);
    OrtStatus* (*SetSessionGraphOptimizationLevel)(OrtSessionOptions* options, GraphOptimizationLevel graph_optimization_level);
    OrtStatus* (*SetIntraOpNumThreads)(OrtSessionOptions* options, int intra_op_num_threads);
    OrtStatus* (*SetInterOpNumThreads)(OrtSessionOptions* options, int inter_op_num_threads);
    
    // Index 27-28: CustomOpDomain
    OrtStatus* (*CreateCustomOpDomain)(const char* domain, OrtCustomOpDomain** out);
    OrtStatus* (*CustomOpDomain_Add)(OrtCustomOpDomain* custom_op_domain, const void* op);
    
    // Index 29-30: SessionOptions continued
    OrtStatus* (*AddCustomOpDomain)(OrtSessionOptions* options, OrtCustomOpDomain* custom_op_domain);
    OrtStatus* (*RegisterCustomOpsLibrary)(OrtSessionOptions* options, const char* library_path, void** library_handle);
    
    // Index 31-36: Session info
    OrtStatus* (*SessionGetInputCount)(const OrtSession* session, size_t* out);
    OrtStatus* (*SessionGetOutputCount)(const OrtSession* session, size_t* out);
    OrtStatus* (*SessionGetOverridableInitializerCount)(const OrtSession* session, size_t* out);
    OrtStatus* (*SessionGetInputTypeInfo)(const OrtSession* session, size_t index, OrtTypeInfo** type_info);
    OrtStatus* (*SessionGetOutputTypeInfo)(const OrtSession* session, size_t index, OrtTypeInfo** type_info);
    OrtStatus* (*SessionGetOverridableInitializerTypeInfo)(const OrtSession* session, size_t index, OrtTypeInfo** type_info);
    
    // Index 37-39: Session names
    OrtStatus* (*SessionGetInputName)(const OrtSession* session, size_t index, OrtAllocator* allocator, char** value);
    OrtStatus* (*SessionGetOutputName)(const OrtSession* session, size_t index, OrtAllocator* allocator, char** value);
    OrtStatus* (*SessionGetOverridableInitializerName)(const OrtSession* session, size_t index, OrtAllocator* allocator, char** value);
    
    // Index 40-49: RunOptions
    OrtStatus* (*CreateRunOptions)(OrtRunOptions** out);
    OrtStatus* (*RunOptionsSetRunLogVerbosityLevel)(OrtRunOptions* options, int log_verbosity_level);
    OrtStatus* (*RunOptionsSetRunLogSeverityLevel)(OrtRunOptions* options, int log_severity_level);
    OrtStatus* (*RunOptionsSetRunTag)(OrtRunOptions* options, const char* run_tag);
    OrtStatus* (*RunOptionsGetRunLogVerbosityLevel)(const OrtRunOptions* options, int* log_verbosity_level);
    OrtStatus* (*RunOptionsGetRunLogSeverityLevel)(const OrtRunOptions* options, int* log_severity_level);
    OrtStatus* (*RunOptionsGetRunTag)(const OrtRunOptions* options, const char** run_tag);
    OrtStatus* (*RunOptionsSetTerminate)(OrtRunOptions* options);
    OrtStatus* (*RunOptionsUnsetTerminate)(OrtRunOptions* options);
    
    // Index 50-55: OrtValue/Tensor creation
    OrtStatus* (*CreateTensorAsOrtValue)(OrtAllocator* allocator, const int64_t* shape, size_t shape_len,
                                         ONNXTensorElementDataType type, OrtValue** out);
    OrtStatus* (*CreateTensorWithDataAsOrtValue)(const OrtMemoryInfo* info, void* p_data, size_t p_data_len,
                                                  const int64_t* shape, size_t shape_len,
                                                  ONNXTensorElementDataType type, OrtValue** out);
    OrtStatus* (*IsTensor)(const OrtValue* value, int* out);
    OrtStatus* (*GetTensorMutableData)(OrtValue* value, void** out);
    OrtStatus* (*FillStringTensor)(OrtValue* value, const char* const* s, size_t s_len);
    OrtStatus* (*GetStringTensorDataLength)(const OrtValue* value, size_t* len);
    
    // Index 56: GetStringTensorContent
    OrtStatus* (*GetStringTensorContent)(const OrtValue* value, void* s, size_t s_len, size_t* offsets, size_t offsets_len);
    
    // Index 57-58: TypeInfo
    OrtStatus* (*CastTypeInfoToTensorInfo)(const OrtTypeInfo* type_info, const OrtTensorTypeAndShapeInfo** out);
    OrtStatus* (*GetOnnxTypeFromTypeInfo)(const OrtTypeInfo* type_info, ONNXType* out);
    
    // Index 59-66: TensorTypeAndShapeInfo
    OrtStatus* (*CreateTensorTypeAndShapeInfo)(OrtTensorTypeAndShapeInfo** out);
    OrtStatus* (*SetTensorElementType)(OrtTensorTypeAndShapeInfo* info, ONNXTensorElementDataType type);
    OrtStatus* (*SetDimensions)(OrtTensorTypeAndShapeInfo* info, const int64_t* dim_values, size_t dim_count);
    OrtStatus* (*GetTensorElementType)(const OrtTensorTypeAndShapeInfo* info, ONNXTensorElementDataType* out);
    OrtStatus* (*GetDimensionsCount)(const OrtTensorTypeAndShapeInfo* info, size_t* out);
    OrtStatus* (*GetDimensions)(const OrtTensorTypeAndShapeInfo* info, int64_t* dim_values, size_t dim_values_length);
    OrtStatus* (*GetSymbolicDimensions)(const OrtTensorTypeAndShapeInfo* info, const char** dim_params, size_t dim_params_length);
    OrtStatus* (*GetTensorShapeElementCount)(const OrtTensorTypeAndShapeInfo* info, size_t* out);
    
    // Index 67-69: OrtValue info
    OrtStatus* (*GetTensorTypeAndShape)(const OrtValue* value, OrtTensorTypeAndShapeInfo** out);
    OrtStatus* (*GetTypeInfo)(const OrtValue* value, OrtTypeInfo** out);
    OrtStatus* (*GetValueType)(const OrtValue* value, ONNXType* out);
    
    // Index 70-78: MemoryInfo
    OrtStatus* (*CreateMemoryInfo)(const char* name, OrtAllocatorType type, int id,
                                   OrtMemType mem_type, OrtMemoryInfo** out);
    OrtStatus* (*CreateCpuMemoryInfo)(OrtAllocatorType type, OrtMemType mem_type, OrtMemoryInfo** out);
    OrtStatus* (*CompareMemoryInfo)(const OrtMemoryInfo* info1, const OrtMemoryInfo* info2, int* out);
    OrtStatus* (*MemoryInfoGetName)(const OrtMemoryInfo* ptr, const char** out);
    OrtStatus* (*MemoryInfoGetId)(const OrtMemoryInfo* ptr, int* out);
    OrtStatus* (*MemoryInfoGetMemType)(const OrtMemoryInfo* ptr, OrtMemType* out);
    OrtStatus* (*MemoryInfoGetType)(const OrtMemoryInfo* ptr, OrtAllocatorType* out);
    OrtStatus* (*AllocatorAlloc)(OrtAllocator* ort_allocator, size_t size, void** out);
    OrtStatus* (*AllocatorFree)(OrtAllocator* ort_allocator, void* p);
    
    // Index 79-80: Allocator
    OrtStatus* (*AllocatorGetInfo)(const OrtAllocator* ort_allocator, const OrtMemoryInfo** out);
    OrtStatus* (*GetAllocatorWithDefaultOptions)(OrtAllocator** out);
    
    // Index 81: AddFreeDimensionOverride
    OrtStatus* (*AddFreeDimensionOverride)(OrtSessionOptions* options, const char* dim_denotation, int64_t dim_value);
    
    // Index 82-84: Non-tensor values
    OrtStatus* (*GetValue)(const OrtValue* value, int index, OrtAllocator* allocator, OrtValue** out);
    OrtStatus* (*GetValueCount)(const OrtValue* value, size_t* out);
    OrtStatus* (*CreateValue)(const OrtValue* const* in, size_t num_values, ONNXType value_type, OrtValue** out);
    
    // Index 85-86: Opaque values
    OrtStatus* (*CreateOpaqueValue)(const char* domain_name, const char* type_name,
                                    const void* data_container, size_t data_container_size, OrtValue** out);
    OrtStatus* (*GetOpaqueValue)(const char* domain_name, const char* type_name, const OrtValue* in,
                                 void* data_container, size_t data_container_size);
    
    // Index 87-89: KernelInfo
    OrtStatus* (*KernelInfoGetAttribute_float)(const OrtKernelInfo* info, const char* name, float* out);
    OrtStatus* (*KernelInfoGetAttribute_int64)(const OrtKernelInfo* info, const char* name, int64_t* out);
    OrtStatus* (*KernelInfoGetAttribute_string)(const OrtKernelInfo* info, const char* name, char* out, size_t* size);
    
    // Index 90-93: KernelContext
    OrtStatus* (*KernelContext_GetInputCount)(const OrtKernelContext* context, size_t* out);
    OrtStatus* (*KernelContext_GetOutputCount)(const OrtKernelContext* context, size_t* out);
    OrtStatus* (*KernelContext_GetInput)(const OrtKernelContext* context, size_t index, const OrtValue** out);
    OrtStatus* (*KernelContext_GetOutput)(OrtKernelContext* context, size_t index, const int64_t* dim_values, size_t dim_count, OrtValue** out);
    
    // Index 94-104: Release functions
    void (*ReleaseEnv)(OrtEnv* input);
    void (*ReleaseStatus)(OrtStatus* input);
    void (*ReleaseMemoryInfo)(OrtMemoryInfo* input);
    void (*ReleaseSession)(OrtSession* input);
    void (*ReleaseValue)(OrtValue* input);
    void (*ReleaseRunOptions)(OrtRunOptions* input);
    void (*ReleaseTypeInfo)(OrtTypeInfo* input);
    void (*ReleaseTensorTypeAndShapeInfo)(OrtTensorTypeAndShapeInfo* input);
    void (*ReleaseSessionOptions)(OrtSessionOptions* input);
    void (*ReleaseCustomOpDomain)(OrtCustomOpDomain* input);
    
    // More functions follow but we don't need them for basic inference
    // Using void* padding to allow safe struct extension
    void* _padding[200];  // Reserve space for additional API functions
};

// OrtApiBase struct - entry point
struct OrtApiBase {
    const OrtApi* (*GetApi)(uint32_t version);
    const char* (*GetVersionString)(void);
};

// Global state
static bool g_initialized = false;
static void* g_ortLibHandle = nullptr;
static const OrtApi* g_ortApi = nullptr;
static OrtEnv* g_ortEnv = nullptr;
static OrtMemoryInfo* g_memoryInfo = nullptr;
static OrtAllocator* g_allocator = nullptr;

// Session pointers for Supertonic models
static OrtSession* g_textEncoder = nullptr;
static OrtSession* g_durationPredictor = nullptr;
static OrtSession* g_vectorEstimator = nullptr;
static OrtSession* g_vocoder = nullptr;
static OrtSessionOptions* g_sessionOptions = nullptr;

// Unicode indexer for text tokenization
static std::map<int32_t, int64_t> g_unicodeIndexer;
static std::string g_modelBasePath;

// Voice style cache: speaker_id -> {style_ttl, style_dp}
struct VoiceStyle {
    std::vector<float> style_ttl;  // [50 * 256] flattened
    std::vector<float> style_dp;   // [8 * 16] flattened
    bool loaded = false;
};
static std::map<int, VoiceStyle> g_voiceStyles;

// Constants from tts.json
static constexpr int SAMPLE_RATE = 44100;           // ae.sample_rate
static constexpr int BASE_CHUNK_SIZE = 512;         // ae.base_chunk_size  
static constexpr int CHUNK_COMPRESS_FACTOR = 6;     // ttl.chunk_compress_factor
static constexpr int LATENT_DIM = 24;               // ttl.latent_dim
static constexpr int LATENT_CHANNELS = LATENT_DIM * CHUNK_COMPRESS_FACTOR;  // 24 * 6 = 144
static constexpr int CHUNK_SIZE = BASE_CHUNK_SIZE * CHUNK_COMPRESS_FACTOR;  // 512 * 6 = 3072

/**
 * Initialize ONNX Runtime by dynamically loading the library
 */
static bool initOrtApi() {
    if (g_ortApi != nullptr) {
        return true;
    }

    // Try to get handle to already-loaded libonnxruntime.so
    g_ortLibHandle = dlopen("libonnxruntime.so", RTLD_NOLOAD);
    if (g_ortLibHandle == nullptr) {
        // Try loading it explicitly
        g_ortLibHandle = dlopen("libonnxruntime.so", RTLD_NOW);
    }
    
    if (g_ortLibHandle == nullptr) {
        LOGE("Failed to load libonnxruntime.so: %s", dlerror());
        return false;
    }
    
    LOGI("Successfully loaded libonnxruntime.so");
    
    // Get OrtGetApiBase function
    typedef const OrtApiBase* (*OrtGetApiBaseFunc)();
    auto getApiBase = (OrtGetApiBaseFunc)dlsym(g_ortLibHandle, "OrtGetApiBase");
    if (getApiBase == nullptr) {
        LOGE("Failed to find OrtGetApiBase: %s", dlerror());
        return false;
    }
    
    // Get API base and then the API
    const OrtApiBase* apiBase = getApiBase();
    if (apiBase == nullptr) {
        LOGE("OrtGetApiBase returned null");
        return false;
    }
    
    // Log version for debugging
    const char* version = apiBase->GetVersionString();
    LOGI("ONNX Runtime version: %s", version);
    
    // Get API version 17 (matches sherpa-onnx bundled version)
    g_ortApi = apiBase->GetApi(17);
    
    if (g_ortApi == nullptr) {
        LOGE("Failed to get ORT API v17");
        return false;
    }
    
    LOGI("ONNX Runtime API v17 initialized successfully");
    return true;
}

/**
 * Check if a status indicates an error, log it, and free the status.
 * Returns true if there was an error.
 */
static bool checkStatus(OrtStatus* status, const char* operation) {
    if (status != nullptr) {
        const char* msg = g_ortApi->GetErrorMessage(status);
        LOGE("ONNX Runtime error during %s: %s", operation, msg);
        g_ortApi->ReleaseStatus(status);
        return true;
    }
    return false;
}

/**
 * Load unicode_indexer.json for text tokenization
 * 
 * The file is a JSON array where:
 * - Array index = Unicode codepoint
 * - Array value = token index (-1 means invalid/unknown)
 * 
 * Example: [−1, −1, ..., 0, 1, 2, ...] where index 32 (space) might map to token 0
 */
static bool loadUnicodeIndexer(const std::string& path) {
    std::ifstream file(path);
    if (!file.is_open()) {
        LOGE("Failed to open unicode_indexer.json: %s", path.c_str());
        return false;
    }
    
    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string content = buffer.str();
    
    g_unicodeIndexer.clear();
    
    // Parse JSON array: [val0, val1, val2, ...]
    // Find the opening bracket
    size_t start = content.find('[');
    if (start == std::string::npos) {
        LOGE("Invalid unicode_indexer.json: no opening bracket");
        return false;
    }
    
    size_t pos = start + 1;
    int32_t codepoint = 0;
    int validCount = 0;
    
    while (pos < content.size()) {
        // Skip whitespace and commas
        while (pos < content.size() && (content[pos] == ' ' || content[pos] == '\t' || 
               content[pos] == '\n' || content[pos] == '\r' || content[pos] == ',')) {
            pos++;
        }
        
        if (pos >= content.size() || content[pos] == ']') {
            break;  // End of array
        }
        
        // Parse the integer value (may be negative)
        size_t valueStart = pos;
        if (content[pos] == '-') {
            pos++;
        }
        while (pos < content.size() && isdigit(content[pos])) {
            pos++;
        }
        
        if (pos > valueStart) {
            try {
                int64_t tokenIndex = std::stoll(content.substr(valueStart, pos - valueStart));
                // Only store valid mappings (token index >= 0)
                if (tokenIndex >= 0) {
                    g_unicodeIndexer[codepoint] = tokenIndex;
                    validCount++;
                }
            } catch (...) {
                // Skip invalid entries
            }
        }
        
        codepoint++;
    }
    
    LOGI("Loaded unicode_indexer.json: %d codepoints scanned, %d valid mappings", 
         codepoint, validCount);
    return validCount > 0;
}

/**
 * Parse a nested float array from JSON: [[[ ... ]]] 
 * Extracts all float values into a flattened vector
 */
static std::vector<float> parseNestedFloatArray(const std::string& json, const std::string& key) {
    std::vector<float> result;
    
    // Find the key
    std::string searchKey = "\"" + key + "\"";
    size_t keyPos = json.find(searchKey);
    if (keyPos == std::string::npos) {
        return result;
    }
    
    // Find "data" under this key
    size_t dataPos = json.find("\"data\"", keyPos);
    if (dataPos == std::string::npos) {
        return result;
    }
    
    // Find the opening bracket of the array
    size_t start = json.find('[', dataPos);
    if (start == std::string::npos) {
        return result;
    }
    
    // Count nested brackets to find all floats
    size_t pos = start;
    while (pos < json.size()) {
        char c = json[pos];
        
        if (c == ']') {
            // Check if we're done with this array
            size_t nextBracket = json.find_first_of("[]", pos + 1);
            if (nextBracket == std::string::npos || json[nextBracket] == '[') {
                // We might be at a new key, check if there's a colon before the bracket
                size_t colonPos = json.find(':', pos + 1);
                if (colonPos != std::string::npos && colonPos < nextBracket) {
                    break;  // New key found, stop parsing
                }
            }
            pos++;
        } else if (c == '-' || isdigit(c)) {
            // Parse a number
            size_t numStart = pos;
            while (pos < json.size() && (isdigit(json[pos]) || json[pos] == '.' || 
                   json[pos] == '-' || json[pos] == 'e' || json[pos] == 'E' || json[pos] == '+')) {
                pos++;
            }
            try {
                float val = std::stof(json.substr(numStart, pos - numStart));
                result.push_back(val);
            } catch (...) {
                // Skip invalid numbers
            }
        } else {
            pos++;
        }
    }
    
    return result;
}

/**
 * Load voice style from JSON file
 * Format: {"style_ttl": {"data": [[[...]]]}, "style_dp": {"data": [[[...]]]}}
 */
static bool loadVoiceStyle(int speakerId) {
    if (g_voiceStyles.count(speakerId) > 0 && g_voiceStyles[speakerId].loaded) {
        return true;  // Already loaded
    }
    
    // Map speaker ID to voice file name
    // M1-M5 = 0-4, F1-F5 = 5-9
    const char* voiceNames[] = {"M1", "M2", "M3", "M4", "M5", "F1", "F2", "F3", "F4", "F5"};
    if (speakerId < 0 || speakerId >= 10) {
        LOGE("Invalid speaker ID: %d", speakerId);
        return false;
    }
    
    std::string path = g_modelBasePath + "/voice_styles/" + voiceNames[speakerId] + ".json";
    
    std::ifstream file(path);
    if (!file.is_open()) {
        LOGE("Failed to open voice style file: %s", path.c_str());
        return false;
    }
    
    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string content = buffer.str();
    file.close();
    
    VoiceStyle style;
    
    // Parse style_ttl [1, 50, 256] = 12800 floats
    style.style_ttl = parseNestedFloatArray(content, "style_ttl");
    if (style.style_ttl.size() != 50 * 256) {
        LOGE("Invalid style_ttl size: %zu (expected %d)", style.style_ttl.size(), 50 * 256);
        return false;
    }
    
    // Parse style_dp [1, 8, 16] = 128 floats
    style.style_dp = parseNestedFloatArray(content, "style_dp");
    if (style.style_dp.size() != 8 * 16) {
        LOGE("Invalid style_dp size: %zu (expected %d)", style.style_dp.size(), 8 * 16);
        return false;
    }
    
    style.loaded = true;
    g_voiceStyles[speakerId] = std::move(style);
    
    LOGD("Loaded voice style for speaker %d (%s)", speakerId, voiceNames[speakerId]);
    return true;
}

/**
 * Tokenize text using unicode indexer
 */
static std::vector<int64_t> tokenizeText(const std::string& text) {
    std::vector<int64_t> tokens;
    
    // Decode UTF-8 and look up each codepoint
    const unsigned char* s = (const unsigned char*)text.c_str();
    size_t len = text.length();
    size_t i = 0;
    
    while (i < len) {
        int32_t codepoint = 0;
        
        if ((s[i] & 0x80) == 0) {
            codepoint = s[i];
            i += 1;
        } else if ((s[i] & 0xE0) == 0xC0 && i + 1 < len) {
            codepoint = ((s[i] & 0x1F) << 6) | (s[i+1] & 0x3F);
            i += 2;
        } else if ((s[i] & 0xF0) == 0xE0 && i + 2 < len) {
            codepoint = ((s[i] & 0x0F) << 12) | ((s[i+1] & 0x3F) << 6) | (s[i+2] & 0x3F);
            i += 3;
        } else if ((s[i] & 0xF8) == 0xF0 && i + 3 < len) {
            codepoint = ((s[i] & 0x07) << 18) | ((s[i+1] & 0x3F) << 12) | ((s[i+2] & 0x3F) << 6) | (s[i+3] & 0x3F);
            i += 4;
        } else {
            i += 1;  // Skip invalid byte
            continue;
        }
        
        auto it = g_unicodeIndexer.find(codepoint);
        if (it != g_unicodeIndexer.end()) {
            tokens.push_back(it->second);
        } else {
            // Unknown character - use 0 (usually <unk>)
            tokens.push_back(0);
        }
    }
    
    return tokens;
}

/**
 * Load an ONNX model and log its input/output info
 */
static OrtSession* loadModel(const std::string& path) {
    OrtSession* session = nullptr;
    OrtStatus* status = g_ortApi->CreateSession(g_ortEnv, path.c_str(), g_sessionOptions, &session);
    
    if (checkStatus(status, "CreateSession")) {
        LOGE("Failed to load model: %s", path.c_str());
        return nullptr;
    }
    
    // Log input info
    size_t numInputs = 0;
    status = g_ortApi->SessionGetInputCount(session, &numInputs);
    if (status == nullptr) {
        LOGI("Model %s has %zu inputs:", path.c_str(), numInputs);
        for (size_t i = 0; i < numInputs; i++) {
            char* name = nullptr;
            status = g_ortApi->SessionGetInputName(session, i, g_allocator, &name);
            if (status == nullptr && name != nullptr) {
                LOGI("  Input %zu: %s", i, name);
                g_ortApi->AllocatorFree(g_allocator, name);
            }
        }
    }
    
    // Log output info
    size_t numOutputs = 0;
    status = g_ortApi->SessionGetOutputCount(session, &numOutputs);
    if (status == nullptr) {
        LOGI("Model %s has %zu outputs:", path.c_str(), numOutputs);
        for (size_t i = 0; i < numOutputs; i++) {
            char* name = nullptr;
            status = g_ortApi->SessionGetOutputName(session, i, g_allocator, &name);
            if (status == nullptr && name != nullptr) {
                LOGI("  Output %zu: %s", i, name);
                g_ortApi->AllocatorFree(g_allocator, name);
            }
        }
    }
    
    LOGI("Loaded model: %s", path.c_str());
    return session;
}

extern "C" {

/**
 * Initialize the Supertonic engine with models from the given path.
 */
JNIEXPORT jboolean JNICALL
Java_com_example_platform_1android_1tts_onnx_SupertonicNative_initialize(
    JNIEnv* env, jobject thiz, jstring corePath) {
    
    if (g_initialized) {
        LOGI("Supertonic already initialized");
        return JNI_TRUE;
    }
    
    // Initialize ONNX Runtime API
    if (!initOrtApi()) {
        return JNI_FALSE;
    }
    
    const char* path = env->GetStringUTFChars(corePath, nullptr);
    if (path == nullptr) {
        LOGE("Failed to get core path string");
        return JNI_FALSE;
    }
    
    std::string basePath(path);
    g_modelBasePath = basePath;
    env->ReleaseStringUTFChars(corePath, path);
    
    // Verify model files exist
    std::vector<std::string> requiredFiles = {
        basePath + "/onnx/text_encoder.onnx",
        basePath + "/onnx/duration_predictor.onnx",
        basePath + "/onnx/vector_estimator.onnx",
        basePath + "/onnx/vocoder.onnx",
        basePath + "/onnx/unicode_indexer.json",
    };
    
    for (const auto& file : requiredFiles) {
        FILE* f = fopen(file.c_str(), "r");
        if (f == nullptr) {
            LOGE("Required file not found: %s", file.c_str());
            return JNI_FALSE;
        }
        fclose(f);
        LOGD("Found: %s", file.c_str());
    }
    
    // Load unicode indexer
    if (!loadUnicodeIndexer(basePath + "/onnx/unicode_indexer.json")) {
        LOGE("Failed to load unicode indexer");
        return JNI_FALSE;
    }
    
    // Create ONNX Runtime environment
    OrtStatus* status = g_ortApi->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "supertonic", &g_ortEnv);
    if (checkStatus(status, "CreateEnv")) {
        return JNI_FALSE;
    }
    
    // Create session options
    status = g_ortApi->CreateSessionOptions(&g_sessionOptions);
    if (checkStatus(status, "CreateSessionOptions")) {
        return JNI_FALSE;
    }
    
    // Set optimization level
    status = g_ortApi->SetSessionGraphOptimizationLevel(g_sessionOptions, ORT_ENABLE_ALL);
    if (checkStatus(status, "SetSessionGraphOptimizationLevel")) {
        return JNI_FALSE;
    }
    
    // Use 2 threads for inference
    status = g_ortApi->SetIntraOpNumThreads(g_sessionOptions, 2);
    if (checkStatus(status, "SetIntraOpNumThreads")) {
        return JNI_FALSE;
    }
    
    // Get default allocator
    status = g_ortApi->GetAllocatorWithDefaultOptions(&g_allocator);
    if (checkStatus(status, "GetAllocatorWithDefaultOptions")) {
        return JNI_FALSE;
    }
    
    // Create CPU memory info
    status = g_ortApi->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &g_memoryInfo);
    if (checkStatus(status, "CreateCpuMemoryInfo")) {
        return JNI_FALSE;
    }
    
    // Load all 4 models
    LOGI("Loading Supertonic models...");
    
    g_textEncoder = loadModel(basePath + "/onnx/text_encoder.onnx");
    if (g_textEncoder == nullptr) return JNI_FALSE;
    
    g_durationPredictor = loadModel(basePath + "/onnx/duration_predictor.onnx");
    if (g_durationPredictor == nullptr) return JNI_FALSE;
    
    g_vectorEstimator = loadModel(basePath + "/onnx/vector_estimator.onnx");
    if (g_vectorEstimator == nullptr) return JNI_FALSE;
    
    g_vocoder = loadModel(basePath + "/onnx/vocoder.onnx");
    if (g_vocoder == nullptr) return JNI_FALSE;
    
    LOGI("Supertonic initialized successfully at %s", basePath.c_str());
    g_initialized = true;
    
    return JNI_TRUE;
}

/**
 * Create an OrtValue tensor from data using the default allocator
 * This lets ONNX Runtime manage the memory automatically
 */
static OrtValue* createTensor(const void* data, size_t dataSize, 
                              const int64_t* shape, size_t shapeLen,
                              ONNXTensorElementDataType type) {
    OrtValue* tensor = nullptr;
    
    // Create tensor using allocator (ORT manages memory)
    OrtStatus* status = g_ortApi->CreateTensorAsOrtValue(
        g_allocator, shape, shapeLen, type, &tensor);
    
    if (checkStatus(status, "CreateTensorAsOrtValue")) {
        return nullptr;
    }
    
    // Copy data into the tensor
    void* tensorData = nullptr;
    status = g_ortApi->GetTensorMutableData(tensor, &tensorData);
    if (checkStatus(status, "GetTensorMutableData")) {
        g_ortApi->ReleaseValue(tensor);
        return nullptr;
    }
    
    memcpy(tensorData, data, dataSize);
    
    return tensor;
}

/**
 * Run a single model and get the output tensor
 */
static OrtValue* runModel(OrtSession* session, 
                          const char* const* inputNames, OrtValue** inputs, size_t numInputs,
                          const char* const* outputNames, size_t numOutputs) {
    std::vector<OrtValue*> outputs(numOutputs, nullptr);
    
    OrtStatus* status = g_ortApi->Run(session, nullptr, 
                                       inputNames, (const OrtValue* const*)inputs, numInputs,
                                       outputNames, numOutputs, outputs.data());
    
    if (checkStatus(status, "Run")) {
        return nullptr;
    }
    
    return outputs[0];  // Return first output
}

/**
 * Synthesize text to audio samples.
 */
JNIEXPORT jfloatArray JNICALL
Java_com_example_platform_1android_1tts_onnx_SupertonicNative_synthesize(
    JNIEnv* env, jobject thiz, jstring text, jint speakerId, jfloat speed) {
    
    if (!g_initialized) {
        LOGE("Supertonic not initialized");
        return nullptr;
    }
    
    const char* textStr = env->GetStringUTFChars(text, nullptr);
    if (textStr == nullptr) {
        return nullptr;
    }
    
    std::string inputText(textStr);
    env->ReleaseStringUTFChars(text, textStr);
    
    LOGD("Synthesizing: '%s' (speaker=%d, speed=%.2f)", inputText.c_str(), speakerId, speed);
    
    // Step 1: Tokenize text
    std::vector<int64_t> tokens = tokenizeText(inputText);
    if (tokens.empty()) {
        LOGE("Failed to tokenize text");
        return nullptr;
    }
    LOGD("Tokenized %zu characters into %zu tokens", inputText.length(), tokens.size());
    
    // Create input tensors for text encoder
    // Inputs: text_ids [batch, seq_len], style_ttl [batch, n_style, style_dim], text_mask [batch, seq_len]
    int64_t seqLen = (int64_t)tokens.size();
    int64_t textShape[] = {1, seqLen};
    OrtValue* textInput = createTensor(tokens.data(), tokens.size() * sizeof(int64_t),
                                        textShape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64);
    if (textInput == nullptr) {
        return nullptr;
    }
    
    // Create style_ttl embedding [1, 50, 256] - from voice_styles/*.json
    // Load voice style if not already loaded
    if (!loadVoiceStyle(speakerId)) {
        LOGE("Failed to load voice style for speaker %d, using fallback", speakerId);
    }
    
    const int N_STYLE_TTL = 50;
    const int STYLE_TTL_DIM = 256;
    std::vector<float> styleTtl(N_STYLE_TTL * STYLE_TTL_DIM, 0.0f);
    
    // Use loaded style if available, otherwise use zeros
    if (g_voiceStyles.count(speakerId) > 0 && g_voiceStyles[speakerId].loaded) {
        styleTtl = g_voiceStyles[speakerId].style_ttl;
    }
    
    int64_t styleTtlShape[] = {1, N_STYLE_TTL, STYLE_TTL_DIM};
    OrtValue* styleTensor = createTensor(styleTtl.data(), styleTtl.size() * sizeof(float),
                                          styleTtlShape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
    
    // Create text mask (all ones = all tokens valid) - shape [1, 1, seq_len]
    std::vector<float> textMaskData(seqLen, 1.0f);
    int64_t textMaskShape[] = {1, 1, seqLen};
    OrtValue* textMask = createTensor(textMaskData.data(), textMaskData.size() * sizeof(float),
                                       textMaskShape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
    
    // Step 2: Run text encoder
    // Inputs: text_ids, style_ttl, text_mask -> Output: text_emb
    OrtValue* textEncoderInputTensors[] = {textInput, styleTensor, textMask};
    const char* textEncoderInputs[] = {"text_ids", "style_ttl", "text_mask"};
    const char* textEncoderOutputs[] = {"text_emb"};
    
    std::vector<OrtValue*> textEncoderOutputTensors(1, nullptr);
    OrtStatus* runStatus = g_ortApi->Run(g_textEncoder, nullptr,
                                          textEncoderInputs, (const OrtValue* const*)textEncoderInputTensors, 3,
                                          textEncoderOutputs, 1, textEncoderOutputTensors.data());
    
    g_ortApi->ReleaseValue(textInput);
    
    if (checkStatus(runStatus, "TextEncoder Run")) {
        g_ortApi->ReleaseValue(styleTensor);
        g_ortApi->ReleaseValue(textMask);
        LOGE("Text encoder failed");
        return nullptr;
    }
    OrtValue* textEmb = textEncoderOutputTensors[0];
    LOGD("Text encoder completed");
    
    // Step 3: Run duration predictor
    // Inputs: text_ids, style_dp [1, 8, 16], text_mask -> Output: duration
    // Reuse text_ids token tensor, need fresh one since we released it
    OrtValue* textInput2 = createTensor(tokens.data(), tokens.size() * sizeof(int64_t),
                                         textShape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64);
    
    // style_dp has shape [1, 8, 16] - different from style_ttl
    const int N_STYLE_DP = 8;
    const int STYLE_DP_DIM = 16;
    std::vector<float> styleDp(N_STYLE_DP * STYLE_DP_DIM, 0.0f);
    
    // Use loaded style if available
    if (g_voiceStyles.count(speakerId) > 0 && g_voiceStyles[speakerId].loaded) {
        styleDp = g_voiceStyles[speakerId].style_dp;
    }
    
    int64_t styleDpShape[] = {1, N_STYLE_DP, STYLE_DP_DIM};
    OrtValue* styleDpTensor = createTensor(styleDp.data(), styleDp.size() * sizeof(float),
                                            styleDpShape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
    
    // Recreate text mask with 3D shape [1, 1, seq_len]
    OrtValue* textMask2 = createTensor(textMaskData.data(), textMaskData.size() * sizeof(float),
                                        textMaskShape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
    
    OrtValue* durPredInputTensors[] = {textInput2, styleDpTensor, textMask2};
    const char* durPredInputs[] = {"text_ids", "style_dp", "text_mask"};
    const char* durPredOutputs[] = {"duration"};
    
    std::vector<OrtValue*> durPredOutputTensors(1, nullptr);
    runStatus = g_ortApi->Run(g_durationPredictor, nullptr,
                               durPredInputs, (const OrtValue* const*)durPredInputTensors, 3,
                               durPredOutputs, 1, durPredOutputTensors.data());
    
    g_ortApi->ReleaseValue(textInput2);
    g_ortApi->ReleaseValue(styleDpTensor);
    g_ortApi->ReleaseValue(textMask2);
    
    if (checkStatus(runStatus, "DurationPredictor Run")) {
        g_ortApi->ReleaseValue(textEmb);
        g_ortApi->ReleaseValue(styleTensor);
        g_ortApi->ReleaseValue(textMask);
        LOGE("Duration predictor failed");
        return nullptr;
    }
    OrtValue* durations = durPredOutputTensors[0];
    LOGD("Duration predictor completed");
    
    // Get duration tensor info to compute latent length
    OrtTensorTypeAndShapeInfo* durShapeInfo = nullptr;
    g_ortApi->GetTensorTypeAndShape(durations, &durShapeInfo);
    size_t durDimCount = 0;
    g_ortApi->GetDimensionsCount(durShapeInfo, &durDimCount);
    std::vector<int64_t> durDims(durDimCount);
    g_ortApi->GetDimensions(durShapeInfo, durDims.data(), durDimCount);
    
    // Log duration tensor shape for debugging
    std::string dimStr = "";
    for (size_t i = 0; i < durDimCount; i++) {
        if (i > 0) dimStr += "x";
        dimStr += std::to_string(durDims[i]);
    }
    LOGD("Duration tensor shape: [%s]", dimStr.c_str());
    g_ortApi->ReleaseTensorTypeAndShapeInfo(durShapeInfo);
    
    // Get durations data and sum to get latent length
    float* durData = nullptr;
    g_ortApi->GetTensorMutableData(durations, (void**)&durData);
    
    // The duration output may have multiple dimensions, use the total element count
    size_t durTotalElements = 1;
    for (size_t i = 0; i < durDimCount; i++) {
        durTotalElements *= durDims[i];
    }
    
    float durSum = 0.0f;
    for (size_t i = 0; i < durTotalElements; i++) {
        durSum += durData[i];
    }
    LOGD("Duration sum: %.2f (from %zu elements)", durSum, durTotalElements);
    
    // Scale duration by speed (reference implementation uses speed = 1.05)
    const float DEFAULT_SPEED = 1.05f;
    float scaledDurSum = durSum / DEFAULT_SPEED;
    
    // Duration is in seconds (from the Supertonic model)
    // Latent length = ceil(scaledDurSum * SAMPLE_RATE / CHUNK_SIZE)
    // where CHUNK_SIZE = BASE_CHUNK_SIZE * CHUNK_COMPRESS_FACTOR = 512 * 6 = 3072
    float wavLen = scaledDurSum * SAMPLE_RATE;  // audio samples
    int64_t latentLen = (int64_t)((wavLen + CHUNK_SIZE - 1) / CHUNK_SIZE);  // ceil division
    
    // Ensure minimum latent length of 1
    if (latentLen < 1) {
        LOGD("Adjusting latent length from %lld to minimum 1", (long long)latentLen);
        latentLen = 1;
    }
    LOGD("Computed latent length: %lld (scaledDur=%.2f, wavLen=%.0f samples, chunkSize=%d)", (long long)latentLen, scaledDurSum, wavLen, CHUNK_SIZE);
    
    // Step 4: Run vector estimator (flow-matching denoiser)
    // This is a diffusion model that iteratively denoises
    // Inputs: noisy_latent, text_emb, style_ttl, latent_mask, text_mask, current_step, total_step
    // Output: denoised_latent
    
    const int NUM_STEPS = 5;  // Number of diffusion steps (5 is default in reference implementation)
    
    // noisy_latent shape: [batch, LATENT_CHANNELS (144), latent_length]
    // Generate Gaussian noise using Box-Muller transform (matching reference implementation)
    std::vector<float> latentData(LATENT_CHANNELS * latentLen, 0.0f);
    
    // Use deterministic seed for reproducibility (based on text hash)
    unsigned int seed = 0;
    for (size_t i = 0; i < inputText.length(); i++) {
        seed = seed * 31 + inputText[i];
    }
    srand(seed);
    
    // Generate Gaussian noise using Box-Muller transform
    for (size_t i = 0; i < latentData.size(); i += 2) {
        double u1 = std::max(1e-10, (double)rand() / RAND_MAX);
        double u2 = (double)rand() / RAND_MAX;
        double z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
        double z1 = sqrt(-2.0 * log(u1)) * sin(2.0 * M_PI * u2);
        latentData[i] = (float)z0;
        if (i + 1 < latentData.size()) {
            latentData[i + 1] = (float)z1;
        }
    }
    int64_t latentShape[] = {1, LATENT_CHANNELS, latentLen};
    
    // Create latent mask (all ones) - shape [1, 1, latent_len]
    std::vector<float> latentMaskData(latentLen, 1.0f);
    int64_t latentMaskShape[] = {1, 1, latentLen};
    
    // Recreate text mask for vector estimator with 3D shape [1, 1, seq_len]
    OrtValue* textMask3 = createTensor(textMaskData.data(), textMaskData.size() * sizeof(float),
                                        textMaskShape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
    
    // Run diffusion steps
    for (int step = 0; step < NUM_STEPS; step++) {
        OrtValue* noisyLatent = createTensor(latentData.data(), latentData.size() * sizeof(float),
                                              latentShape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
        OrtValue* latentMask = createTensor(latentMaskData.data(), latentMaskData.size() * sizeof(float),
                                             latentMaskShape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
        
        // Step tensors - model expects float32, not int64
        int64_t stepShape[] = {1};
        float currentStepVal = static_cast<float>(step);
        float totalStepVal = static_cast<float>(NUM_STEPS);
        OrtValue* currentStepTensor = createTensor(&currentStepVal, sizeof(float),
                                                    stepShape, 1, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
        OrtValue* totalStepTensor = createTensor(&totalStepVal, sizeof(float),
                                                  stepShape, 1, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
        
        OrtValue* vecEstInputTensors[] = {noisyLatent, textEmb, styleTensor, latentMask, textMask3, currentStepTensor, totalStepTensor};
        const char* vecEstInputNames[] = {"noisy_latent", "text_emb", "style_ttl", "latent_mask", "text_mask", "current_step", "total_step"};
        const char* vecEstOutputs[] = {"denoised_latent"};
        
        std::vector<OrtValue*> vecEstOutputTensors(1, nullptr);
        runStatus = g_ortApi->Run(g_vectorEstimator, nullptr,
                                   vecEstInputNames, (const OrtValue* const*)vecEstInputTensors, 7,
                                   vecEstOutputs, 1, vecEstOutputTensors.data());
        
        g_ortApi->ReleaseValue(noisyLatent);
        g_ortApi->ReleaseValue(latentMask);
        g_ortApi->ReleaseValue(currentStepTensor);
        g_ortApi->ReleaseValue(totalStepTensor);
        
        if (checkStatus(runStatus, "VectorEstimator Run")) {
            g_ortApi->ReleaseValue(textEmb);
            g_ortApi->ReleaseValue(styleTensor);
            g_ortApi->ReleaseValue(textMask);
            g_ortApi->ReleaseValue(textMask3);
            g_ortApi->ReleaseValue(durations);
            LOGE("Vector estimator failed at step %d", step);
            return nullptr;
        }
        
        // Copy denoised output back to latentData for next step
        float* denoisedData = nullptr;
        g_ortApi->GetTensorMutableData(vecEstOutputTensors[0], (void**)&denoisedData);
        memcpy(latentData.data(), denoisedData, latentData.size() * sizeof(float));
        g_ortApi->ReleaseValue(vecEstOutputTensors[0]);
    }
    
    g_ortApi->ReleaseValue(textEmb);
    g_ortApi->ReleaseValue(styleTensor);
    g_ortApi->ReleaseValue(textMask);
    g_ortApi->ReleaseValue(textMask3);
    g_ortApi->ReleaseValue(durations);
    LOGD("Vector estimator completed (%d steps)", NUM_STEPS);
    
    // Step 5: Run vocoder
    // Input: latent [batch, 144, latent_length] -> Output: wav_tts
    OrtValue* finalLatent = createTensor(latentData.data(), latentData.size() * sizeof(float),
                                          latentShape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT);
    
    const char* vocoderInputs[] = {"latent"};
    const char* vocoderOutputs[] = {"wav_tts"};
    
    std::vector<OrtValue*> vocoderOutputTensors(1, nullptr);
    runStatus = g_ortApi->Run(g_vocoder, nullptr,
                               vocoderInputs, (const OrtValue* const*)&finalLatent, 1,
                               vocoderOutputs, 1, vocoderOutputTensors.data());
    
    g_ortApi->ReleaseValue(finalLatent);
    
    if (checkStatus(runStatus, "Vocoder Run") || vocoderOutputTensors[0] == nullptr) {
        LOGE("Vocoder failed");
        return nullptr;
    }
    OrtValue* audioTensor = vocoderOutputTensors[0];
    LOGD("Vocoder completed");
    
    // Get audio data from tensor
    float* audioData = nullptr;
    OrtStatus* status = g_ortApi->GetTensorMutableData(audioTensor, (void**)&audioData);
    if (checkStatus(status, "GetTensorMutableData") || audioData == nullptr) {
        g_ortApi->ReleaseValue(audioTensor);
        return nullptr;
    }
    
    // Get tensor shape to determine audio length
    OrtTensorTypeAndShapeInfo* shapeInfo = nullptr;
    status = g_ortApi->GetTensorTypeAndShape(audioTensor, &shapeInfo);
    if (checkStatus(status, "GetTensorTypeAndShape")) {
        g_ortApi->ReleaseValue(audioTensor);
        return nullptr;
    }
    
    size_t numSamples = 0;
    status = g_ortApi->GetTensorShapeElementCount(shapeInfo, &numSamples);
    g_ortApi->ReleaseTensorTypeAndShapeInfo(shapeInfo);
    
    if (checkStatus(status, "GetTensorShapeElementCount") || numSamples == 0) {
        g_ortApi->ReleaseValue(audioTensor);
        return nullptr;
    }
    
    LOGD("Generated %zu audio samples", numSamples);
    
    // Create Java float array
    jfloatArray result = env->NewFloatArray(numSamples);
    if (result == nullptr) {
        g_ortApi->ReleaseValue(audioTensor);
        return nullptr;
    }
    
    env->SetFloatArrayRegion(result, 0, numSamples, audioData);
    g_ortApi->ReleaseValue(audioTensor);
    
    return result;
}

/**
 * Get the sample rate.
 */
JNIEXPORT jint JNICALL
Java_com_example_platform_1android_1tts_onnx_SupertonicNative_getSampleRate(
    JNIEnv* env, jobject thiz) {
    return SAMPLE_RATE;
}

/**
 * Check if the engine is ready.
 */
JNIEXPORT jboolean JNICALL
Java_com_example_platform_1android_1tts_onnx_SupertonicNative_isReady(
    JNIEnv* env, jobject thiz) {
    return g_initialized ? JNI_TRUE : JNI_FALSE;
}

/**
 * Release all resources.
 */
JNIEXPORT void JNICALL
Java_com_example_platform_1android_1tts_onnx_SupertonicNative_dispose(
    JNIEnv* env, jobject thiz) {
    
    LOGI("Disposing Supertonic engine");
    
    if (g_textEncoder != nullptr) {
        g_ortApi->ReleaseSession(g_textEncoder);
        g_textEncoder = nullptr;
    }
    if (g_durationPredictor != nullptr) {
        g_ortApi->ReleaseSession(g_durationPredictor);
        g_durationPredictor = nullptr;
    }
    if (g_vectorEstimator != nullptr) {
        g_ortApi->ReleaseSession(g_vectorEstimator);
        g_vectorEstimator = nullptr;
    }
    if (g_vocoder != nullptr) {
        g_ortApi->ReleaseSession(g_vocoder);
        g_vocoder = nullptr;
    }
    
    if (g_sessionOptions != nullptr) {
        g_ortApi->ReleaseSessionOptions(g_sessionOptions);
        g_sessionOptions = nullptr;
    }
    
    if (g_memoryInfo != nullptr) {
        g_ortApi->ReleaseMemoryInfo(g_memoryInfo);
        g_memoryInfo = nullptr;
    }
    
    if (g_ortEnv != nullptr) {
        g_ortApi->ReleaseEnv(g_ortEnv);
        g_ortEnv = nullptr;
    }
    
    g_unicodeIndexer.clear();
    g_modelBasePath.clear();
    g_initialized = false;
}

} // extern "C"
