import AVFoundation
import Foundation

/// 只保留样本数量和峰值，不保留音频内容。
struct AudioSignalLevel: Equatable, Sendable {
    private(set) var samples = 0
    private(set) var peak: Float = 0

    var hasSignal: Bool { peak > 0.000_001 }

    mutating func observe(_ value: Float) {
        guard value.isFinite else { return }
        samples += 1
        peak = max(peak, abs(value))
    }

    mutating func observe(_ buffer: AVAudioPCMBuffer) {
        let blocks = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        for block in blocks {
            guard let data = block.mData else { continue }
            let validSamples = Int(buffer.frameLength) * Int(block.mNumberChannels)
            switch buffer.format.commonFormat {
            case .pcmFormatFloat32:
                for index in 0..<min(validSamples, Int(block.mDataByteSize) / 4) {
                    observe(data.assumingMemoryBound(to: Float.self)[index])
                }
            case .pcmFormatFloat64:
                for index in 0..<min(validSamples, Int(block.mDataByteSize) / 8) {
                    observe(Float(data.assumingMemoryBound(to: Double.self)[index]))
                }
            case .pcmFormatInt16:
                for index in 0..<min(validSamples, Int(block.mDataByteSize) / 2) {
                    observe(Float(data.assumingMemoryBound(to: Int16.self)[index]) / 32768)
                }
            case .pcmFormatInt32:
                for index in 0..<min(validSamples, Int(block.mDataByteSize) / 4) {
                    observe(Float(data.assumingMemoryBound(to: Int32.self)[index]) / 2147483648)
                }
            default: break
            }
        }
    }
}
