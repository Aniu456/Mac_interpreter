import AVFoundation
import CoreMedia

enum MicrophonePCM {
    // AVCapture 的设备原生格式不一定能被 Speech 的 CMSampleBuffer 桥接正确处理。
    static var captureSettings: [String: Any] { [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: true,
    ] }

    /// 返回独立持有的 PCM 数据；空帧、尚未就绪或失效的回调不送入识别器。
    static func copy(_ sample: CMSampleBuffer) throws -> AVAudioPCMBuffer? {
        guard CMSampleBufferIsValid(sample), CMSampleBufferDataIsReady(sample) else { return nil }
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0 else { return nil }
        guard frames <= Int(Int32.max),
              let description = CMSampleBufferGetFormatDescription(sample),
              CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio,
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              stream.pointee.mFormatID == kAudioFormatLinearPCM,
              stream.pointee.mSampleRate.isFinite, stream.pointee.mSampleRate > 0,
              stream.pointee.mChannelsPerFrame > 0, stream.pointee.mBytesPerFrame > 0 else {
            throw InterpreterError("麦克风返回了无法识别的音频格式，请检查麦克风后重试。")
        }
        // MacBook 麦克风可能返回无声道布局的 3 声道 PCM；不带布局的初始化器只支持 1～2 声道。
        let channels = stream.pointee.mChannelsPerFrame
        let layout = channels > 2
            ? AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels) : nil
        guard let format = AVAudioFormat(streamDescription: stream, channelLayout: layout),
              format.commonFormat != .otherFormat else {
            throw InterpreterError("麦克风返回了无法识别的音频格式，请检查麦克风后重试。")
        }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
            throw InterpreterError("无法分配麦克风音频缓冲区，请重试。")
        }
        pcm.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList
        )
        guard status == noErr else {
            throw InterpreterError("麦克风音频数据读取失败（\(status)），请重新开始录音。")
        }
        return channels > 2 ? try downmixToMono(pcm) : pcm
    }

    private static func downmixToMono(_ pcm: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let layout = pcm.format.channelLayout else {
            throw InterpreterError("无法读取麦克风的声道布局，请重新开始录音。")
        }
        let floatFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: pcm.format.sampleRate,
            interleaved: false, channelLayout: layout
        )
        guard let planar = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: pcm.frameLength),
              let converter = AVAudioConverter(from: pcm.format, to: floatFormat),
              let monoFormat = AVAudioFormat(standardFormatWithSampleRate: pcm.format.sampleRate, channels: 1),
              let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: pcm.frameLength) else {
            throw InterpreterError("无法转换麦克风的多声道音频，请重新开始录音。")
        }
        try converter.convert(to: planar, from: pcm)
        mono.frameLength = planar.frameLength
        guard let input = planar.floatChannelData, let output = mono.floatChannelData else {
            throw InterpreterError("无法读取麦克风的多声道音频，请重新开始录音。")
        }
        let channels = Int(planar.format.channelCount)
        for frame in 0..<Int(planar.frameLength) {
            var sample: Float = 0
            for channel in 0..<channels { sample += input[channel][frame] / Float(channels) }
            output[0][frame] = sample
        }
        return mono
    }
}
