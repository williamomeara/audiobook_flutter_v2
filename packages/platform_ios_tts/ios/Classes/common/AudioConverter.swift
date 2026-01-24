import Foundation

/// Utility for converting audio samples to WAV format.
class AudioConverter {
    
    /// Convert Float32 samples to WAV data.
    /// - Parameters:
    ///   - samples: Audio samples as Float32 array (values in range -1.0 to 1.0)
    ///   - sampleRate: Sample rate in Hz (e.g., 22050, 24000)
    /// - Returns: WAV file data with proper headers
    static func toWav(samples: [Float], sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = numChannels * bitsPerSample / 8
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(samples.count * 2)  // 16-bit = 2 bytes per sample
        let fileSize = 36 + dataSize
        
        var buffer = Data()
        
        // RIFF header
        buffer.append(contentsOf: "RIFF".utf8)
        buffer.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        buffer.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        buffer.append(contentsOf: "fmt ".utf8)
        buffer.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // chunk size
        buffer.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // PCM format
        buffer.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        buffer.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        buffer.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        buffer.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        buffer.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        // data chunk
        buffer.append(contentsOf: "data".utf8)
        buffer.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        // Convert Float32 samples to Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * 32767)
            buffer.append(contentsOf: withUnsafeBytes(of: int16.littleEndian) { Array($0) })
        }
        
        return buffer
    }
    
    /// Write samples to a WAV file.
    /// - Parameters:
    ///   - samples: Audio samples as Float32 array
    ///   - sampleRate: Sample rate in Hz
    ///   - path: File path to write to
    static func writeWav(samples: [Float], sampleRate: Int, to path: String) throws {
        let wavData = toWav(samples: samples, sampleRate: sampleRate)
        try wavData.write(to: URL(fileURLWithPath: path))
    }
    
    /// Calculate duration in milliseconds from sample count and rate.
    static func durationMs(sampleCount: Int, sampleRate: Int) -> Int64 {
        return Int64(sampleCount) * 1000 / Int64(sampleRate)
    }
}
