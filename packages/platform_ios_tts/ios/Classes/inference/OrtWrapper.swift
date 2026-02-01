import Foundation
import OnnxRuntimeCApi

/// Swift wrapper around the ONNX Runtime C API for inference.
/// Provides a clean interface for loading models and running inference.
final class OrtWrapper {
    
    let api: UnsafePointer<OrtApi>
    private var env: OpaquePointer?  // OrtEnv*
    private var sessionOptions: OpaquePointer?  // OrtSessionOptions*
    private var allocatorPtr: UnsafeMutablePointer<OrtAllocator>?
    
    /// Determine optimal thread count based on device CPU cores.
    /// Supertonic models benefit from more threads on high-core devices.
    private static func getOptimalThreadCount() -> Int32 {
        let cores = ProcessInfo.processInfo.processorCount
        switch cores {
        case 8...: return 4  // High-end devices: use 4 threads
        case 6..<8: return 3  // Mid-range: use 3 threads
        case 4..<6: return 2  // Budget: use 2 threads
        default: return 1     // Low-end: single thread
        }
    }
    
    /// Initialize the ONNX Runtime environment.
    init() throws {
        // Get the API pointer
        let base = OrtGetApiBase()
        guard let base = base else {
            throw TtsError.modelNotLoaded
        }
        
        // Get API version 17 (latest stable)
        guard let apiPtr = base.pointee.GetApi(17) else {
            throw TtsError.modelNotLoaded
        }
        self.api = apiPtr
        
        // Create environment
        var envPtr: OpaquePointer?
        let status = apiPtr.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "SupertonicTTS", &envPtr)
        try OrtWrapper.checkStatus(status, api: apiPtr)
        self.env = envPtr
        
        // Create session options
        var optionsPtr: OpaquePointer?
        let optStatus = apiPtr.pointee.CreateSessionOptions(&optionsPtr)
        try OrtWrapper.checkStatus(optStatus, api: apiPtr)
        self.sessionOptions = optionsPtr
        
        // Set graph optimization level
        let graphOptStatus = apiPtr.pointee.SetSessionGraphOptimizationLevel(optionsPtr, ORT_ENABLE_ALL)
        try OrtWrapper.checkStatus(graphOptStatus, api: apiPtr)
        
        // Set intra-op thread count (dynamic based on CPU cores)
        let threads = OrtWrapper.getOptimalThreadCount()
        NSLog("[OrtWrapper] CPU cores: %d, using %d threads for ONNX Runtime", ProcessInfo.processInfo.processorCount, threads)
        let threadStatus = apiPtr.pointee.SetIntraOpNumThreads(optionsPtr, threads)
        try OrtWrapper.checkStatus(threadStatus, api: apiPtr)
        
        // Get default allocator
        var allocPtr: UnsafeMutablePointer<OrtAllocator>?
        let allocStatus = apiPtr.pointee.GetAllocatorWithDefaultOptions(&allocPtr)
        try OrtWrapper.checkStatus(allocStatus, api: apiPtr)
        guard let alloc = allocPtr else {
            throw TtsError.modelNotLoaded
        }
        self.allocatorPtr = alloc
        
        NSLog("[OrtWrapper] ONNX Runtime initialized")
    }
    
    deinit {
        if let sessionOptions = sessionOptions {
            api.pointee.ReleaseSessionOptions(sessionOptions)
        }
        if let env = env {
            api.pointee.ReleaseEnv(env)
        }
        // Note: allocator from GetAllocatorWithDefaultOptions should NOT be released - it's a singleton
    }
    
    /// Load a model and create a session.
    func createSession(modelPath: String) throws -> OrtSession {
        guard let env = env, let sessionOptions = sessionOptions else {
            throw TtsError.modelNotLoaded
        }
        
        var sessionPtr: OpaquePointer?
        let status = modelPath.withCString { path in
            api.pointee.CreateSession(env, path, sessionOptions, &sessionPtr)
        }
        try OrtWrapper.checkStatus(status, api: api)
        
        guard let session = sessionPtr, let alloc = allocatorPtr else {
            throw TtsError.modelNotLoaded
        }
        
        return OrtSession(api: api, session: session, allocator: alloc)
    }
    
    static func checkStatus(_ status: OpaquePointer?, api: UnsafePointer<OrtApi>) throws {
        guard let status = status else { return }
        
        let errorCode = api.pointee.GetErrorCode(status)
        if errorCode != ORT_OK {
            let message = api.pointee.GetErrorMessage(status)
            let errorStr = message.map { String(cString: $0) } ?? "Unknown error"
            api.pointee.ReleaseStatus(status)
            throw TtsError.synthesisFailure("ORT Error: \(errorStr)")
        }
        api.pointee.ReleaseStatus(status)
    }
}

/// Represents an ONNX Runtime session.
final class OrtSession {
    private let api: UnsafePointer<OrtApi>
    private var session: OpaquePointer
    private let allocator: UnsafeMutablePointer<OrtAllocator>
    
    init(api: UnsafePointer<OrtApi>, session: OpaquePointer, allocator: UnsafeMutablePointer<OrtAllocator>) {
        self.api = api
        self.session = session
        self.allocator = allocator
    }
    
    deinit {
        api.pointee.ReleaseSession(session)
    }
    
    /// Run inference with the given inputs.
    func run(inputs: [String: OrtTensor], outputNames: [String]) throws -> [String: OrtTensor] {
        let inputNames = Array(inputs.keys)
        let inputValues = inputNames.map { inputs[$0]!.value }
        
        // Create output values array
        var outputValues = [OpaquePointer?](repeating: nil, count: outputNames.count)
        
        // Run inference
        try withArrayOfCStrings(inputNames) { inputNamesPtr in
            try withArrayOfCStrings(outputNames) { outputNamesPtr in
                let status = api.pointee.Run(
                    session,
                    nil,  // run options
                    inputNamesPtr,
                    inputValues.map { $0 as OpaquePointer? },
                    inputNames.count,
                    outputNamesPtr,
                    outputNames.count,
                    &outputValues
                )
                try checkStatus(status)
            }
        }
        
        // Convert outputs to tensors
        var result: [String: OrtTensor] = [:]
        for (i, name) in outputNames.enumerated() {
            if let value = outputValues[i] {
                result[name] = OrtTensor(api: api, value: value, allocator: allocator, ownsValue: true)
            }
        }
        
        return result
    }
    
    private func checkStatus(_ status: OpaquePointer?) throws {
        guard let status = status else { return }
        
        let errorCode = api.pointee.GetErrorCode(status)
        if errorCode != ORT_OK {
            let message = api.pointee.GetErrorMessage(status)
            let errorStr = message.map { String(cString: $0) } ?? "Unknown error"
            api.pointee.ReleaseStatus(status)
            throw TtsError.synthesisFailure("ORT Run Error: \(errorStr)")
        }
        api.pointee.ReleaseStatus(status)
    }
}

/// Represents an ONNX tensor value.
final class OrtTensor {
    fileprivate let api: UnsafePointer<OrtApi>
    fileprivate let value: OpaquePointer
    private let ownsValue: Bool
    /// Buffer pointer that must be deallocated when tensor is released.
    /// ONNX Runtime's CreateTensorWithDataAsOrtValue does NOT copy data,
    /// so we must keep the buffer alive for the tensor's lifetime.
    private let bufferPointer: UnsafeMutableRawPointer?
    
    init(api: UnsafePointer<OrtApi>, value: OpaquePointer, allocator: UnsafeMutablePointer<OrtAllocator>, ownsValue: Bool, bufferPointer: UnsafeMutableRawPointer? = nil) {
        self.api = api
        self.value = value
        self.ownsValue = ownsValue
        self.bufferPointer = bufferPointer
    }
    
    deinit {
        if ownsValue {
            api.pointee.ReleaseValue(value)
        }
        // Deallocate the buffer we allocated for tensor data
        bufferPointer?.deallocate()
    }
    
    /// Create a float tensor from data.
    static func createFloat(api: UnsafePointer<OrtApi>, data: [Float], shape: [Int64]) throws -> OrtTensor {
        var memoryInfo: OpaquePointer?
        let memStatus = api.pointee.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memoryInfo)
        if let status = memStatus {
            let errorCode = api.pointee.GetErrorCode(status)
            if errorCode != ORT_OK {
                api.pointee.ReleaseStatus(status)
                throw TtsError.synthesisFailure("Failed to create memory info")
            }
            api.pointee.ReleaseStatus(status)
        }
        defer { api.pointee.ReleaseMemoryInfo(memoryInfo) }
        
        var tensorValue: OpaquePointer?
        let byteCount = data.count * MemoryLayout<Float>.size
        
        // Need to copy data to a mutable buffer that outlives the function
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: data.count)
        data.withUnsafeBufferPointer { src in
            buffer.initialize(from: src.baseAddress!, count: data.count)
        }
        
        var shapeArray = shape
        let tensorStatus = api.pointee.CreateTensorWithDataAsOrtValue(
            memoryInfo,
            buffer,
            byteCount,
            &shapeArray,
            shape.count,
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
            &tensorValue
        )
        
        if let status = tensorStatus {
            let errorCode = api.pointee.GetErrorCode(status)
            if errorCode != ORT_OK {
                buffer.deallocate()
                api.pointee.ReleaseStatus(status)
                throw TtsError.synthesisFailure("Failed to create tensor")
            }
            api.pointee.ReleaseStatus(status)
        }
        
        guard let tensor = tensorValue else {
            buffer.deallocate()
            throw TtsError.synthesisFailure("Tensor creation returned nil")
        }
        
        // Get allocator for the return value
        var allocPtr: UnsafeMutablePointer<OrtAllocator>?
        let allocStatus = api.pointee.GetAllocatorWithDefaultOptions(&allocPtr)
        if let status = allocStatus {
            let errorCode = api.pointee.GetErrorCode(status)
            if errorCode != ORT_OK {
                buffer.deallocate()
                api.pointee.ReleaseValue(tensor)
                api.pointee.ReleaseStatus(status)
                throw TtsError.synthesisFailure("Failed to get allocator")
            }
            api.pointee.ReleaseStatus(status)
        }
        
        guard let alloc = allocPtr else {
            buffer.deallocate()
            api.pointee.ReleaseValue(tensor)
            throw TtsError.synthesisFailure("Allocator is nil")
        }
        
        // Pass buffer pointer to OrtTensor for deallocation in deinit
        return OrtTensor(api: api, value: tensor, allocator: alloc, ownsValue: true, bufferPointer: buffer)
    }
    
    /// Create an int64 tensor from data.
    static func createInt64(api: UnsafePointer<OrtApi>, data: [Int64], shape: [Int64]) throws -> OrtTensor {
        var memoryInfo: OpaquePointer?
        let memStatus = api.pointee.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memoryInfo)
        if let status = memStatus {
            let errorCode = api.pointee.GetErrorCode(status)
            if errorCode != ORT_OK {
                api.pointee.ReleaseStatus(status)
                throw TtsError.synthesisFailure("Failed to create memory info")
            }
            api.pointee.ReleaseStatus(status)
        }
        defer { api.pointee.ReleaseMemoryInfo(memoryInfo) }
        
        var tensorValue: OpaquePointer?
        let byteCount = data.count * MemoryLayout<Int64>.size
        
        let buffer = UnsafeMutablePointer<Int64>.allocate(capacity: data.count)
        data.withUnsafeBufferPointer { src in
            buffer.initialize(from: src.baseAddress!, count: data.count)
        }
        
        var shapeArray = shape
        let tensorStatus = api.pointee.CreateTensorWithDataAsOrtValue(
            memoryInfo,
            buffer,
            byteCount,
            &shapeArray,
            shape.count,
            ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
            &tensorValue
        )
        
        if let status = tensorStatus {
            let errorCode = api.pointee.GetErrorCode(status)
            if errorCode != ORT_OK {
                buffer.deallocate()
                api.pointee.ReleaseStatus(status)
                throw TtsError.synthesisFailure("Failed to create int64 tensor")
            }
            api.pointee.ReleaseStatus(status)
        }
        
        guard let tensor = tensorValue else {
            buffer.deallocate()
            throw TtsError.synthesisFailure("Int64 tensor creation returned nil")
        }
        
        var allocPtr: UnsafeMutablePointer<OrtAllocator>?
        let allocStatus = api.pointee.GetAllocatorWithDefaultOptions(&allocPtr)
        if let status = allocStatus {
            let errorCode = api.pointee.GetErrorCode(status)
            if errorCode != ORT_OK {
                buffer.deallocate()
                api.pointee.ReleaseValue(tensor)
                api.pointee.ReleaseStatus(status)
                throw TtsError.synthesisFailure("Failed to get allocator")
            }
            api.pointee.ReleaseStatus(status)
        }
        
        guard let alloc = allocPtr else {
            buffer.deallocate()
            api.pointee.ReleaseValue(tensor)
            throw TtsError.synthesisFailure("Allocator is nil")
        }
        
        // Pass buffer pointer to OrtTensor for deallocation in deinit
        return OrtTensor(api: api, value: tensor, allocator: alloc, ownsValue: true, bufferPointer: buffer)
    }
    
    /// Get the float data from this tensor.
    func getFloatData() throws -> [Float] {
        var dataPtr: UnsafeMutableRawPointer?
        let status = api.pointee.GetTensorMutableData(value, &dataPtr)
        if let status = status {
            let errorCode = api.pointee.GetErrorCode(status)
            if errorCode != ORT_OK {
                api.pointee.ReleaseStatus(status)
                throw TtsError.synthesisFailure("Failed to get tensor data")
            }
            api.pointee.ReleaseStatus(status)
        }
        
        guard let ptr = dataPtr else {
            throw TtsError.synthesisFailure("Tensor data pointer is nil")
        }
        
        // Get shape to determine total count
        var typeInfo: OpaquePointer?
        let typeStatus = api.pointee.GetTensorTypeAndShape(value, &typeInfo)
        if let status = typeStatus {
            let errorCode = api.pointee.GetErrorCode(status)
            if errorCode != ORT_OK {
                api.pointee.ReleaseStatus(status)
                throw TtsError.synthesisFailure("Failed to get tensor type info")
            }
            api.pointee.ReleaseStatus(status)
        }
        defer { api.pointee.ReleaseTensorTypeAndShapeInfo(typeInfo) }
        
        var count: Int = 0
        let countStatus = api.pointee.GetTensorShapeElementCount(typeInfo, &count)
        if let status = countStatus {
            let errorCode = api.pointee.GetErrorCode(status)
            if errorCode != ORT_OK {
                api.pointee.ReleaseStatus(status)
                throw TtsError.synthesisFailure("Failed to get tensor element count")
            }
            api.pointee.ReleaseStatus(status)
        }
        
        let floatPtr = ptr.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: floatPtr, count: count))
    }
}

// MARK: - Helper Functions

private func withArrayOfCStrings<R>(_ strings: [String], body: (UnsafeMutablePointer<UnsafePointer<CChar>?>) throws -> R) rethrows -> R {
    var cStrings = strings.map { strdup($0) }
    defer { cStrings.forEach { free($0) } }
    
    return try cStrings.withUnsafeMutableBufferPointer { buffer in
        let pointers = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: strings.count)
        defer { pointers.deallocate() }
        
        for i in 0..<strings.count {
            pointers[i] = UnsafePointer(buffer[i])
        }
        
        return try body(pointers)
    }
}
