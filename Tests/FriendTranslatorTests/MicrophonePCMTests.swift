import AVFoundation
import CoreMedia
import Speech
import Testing
@testable import FriendTranslator

@Test(arguments: [false, true])
func microphonePCMCopiesInterleavedAndPlanarAudio(interleaved: Bool) throws {
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: interleaved))
    let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
    source.frameLength = 4
    let buffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
    for (channel, buffer) in buffers.enumerated() {
        let data = try #require(buffer.mData).assumingMemoryBound(to: Float.self)
        for index in 0..<Int(buffer.mDataByteSize) / MemoryLayout<Float>.size {
            data[index] = Float(channel * 10 + index) / 100
        }
    }
    let sample = try makeMicrophoneSample(source)
    let copied = try #require(try MicrophonePCM.copy(sample))
    #expect(copied.format == format)
    #expect(copied.frameLength == 4)
    let output = UnsafeMutableAudioBufferListPointer(copied.mutableAudioBufferList)
    for (original, copy) in zip(buffers, output) {
        #expect(original.mData != copy.mData)
        #expect(original.mDataByteSize == copy.mDataByteSize)
        #expect(memcmp(original.mData!, copy.mData!, Int(original.mDataByteSize)) == 0)
    }
    // 更改 CMSampleBuffer 的存储也不能更改送往 Speech 的 PCM。
    let storage = try #require(CMSampleBufferGetDataBuffer(sample))
    #expect(CMBlockBufferFillDataBytes(with: 0, blockBuffer: storage, offsetIntoDestination: 0, dataLength: CMBlockBufferGetDataLength(storage)) == noErr)
    #expect(output[0].mData!.assumingMemoryBound(to: Float.self)[1] == 0.01)
    // 使用生产代码的新入口；不创建识别任务，因此不请求权限或上传音频。
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.append(copied)
    request.endAudio()
}

@Test func microphonePCMSupportsIntegerPCM() throws {
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
    let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
    source.frameLength = 2
    let data = try #require(source.int16ChannelData)
    data[0][0] = -1200
    data[0][1] = 1200
    let sample = try makeMicrophoneSample(source)
    let copy = try #require(try MicrophonePCM.copy(sample))
    #expect(copy.int16ChannelData?[0][0] == -1200)
    #expect(copy.int16ChannelData?[0][1] == 1200)
}

@Test(arguments: [false, true])
func microphonePCMMixesThreeChannelsWithoutLayout(interleaved: Bool) throws {
    // 复现真实失败回调：44.1 kHz、3 声道、512 帧，CMSampleBuffer 没有声道布局。
    let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 3))
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 44_100,
        interleaved: interleaved, channelLayout: layout
    )
    let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
    source.frameLength = 512
    let input = try #require(source.floatChannelData)
    for channel in 0..<3 {
        for frame in 0..<512 {
            let value: Float = frame % 3 == channel ? (channel == 1 ? -0.6 : 0.9) : 0
            input[interleaved ? 0 : channel][frame * Int(source.stride) + (interleaved ? channel : 0)] = value
        }
    }
    let sample = try makeMicrophoneSample(source)
    let mono = try #require(try MicrophonePCM.copy(sample))
    #expect(mono.format.channelCount == 1)
    #expect(mono.format.sampleRate == 44_100)
    #expect(mono.frameLength == 512)
    let output = try #require(mono.floatChannelData)
    for frame in 0..<512 {
        let expected: Float = frame % 3 == 1 ? -0.2 : 0.3
        #expect(abs(output[0][frame] - expected) < 0.000_001)
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.append(mono)
    request.endAudio()
}

@Test func microphonePCMDropsUnreadyEmptyAndInvalidBuffers() throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
    source.frameLength = 2
    let unready = try makeMicrophoneSample(source, ready: false, includeData: false)
    #expect(!CMSampleBufferDataIsReady(unready))
    #expect(try MicrophonePCM.copy(unready) == nil)
    let invalid = try makeMicrophoneSample(source)
    #expect(CMSampleBufferInvalidate(invalid) == noErr)
    #expect(try MicrophonePCM.copy(invalid) == nil)
    source.frameLength = 0
    #expect(try MicrophonePCM.copy(makeMicrophoneSample(source, includeData: false)) == nil)
}

@Test func microphonePCMRejectsMissingAudioDataWithoutCrashing() throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
    source.frameLength = 2
    let sample = try makeMicrophoneSample(source, includeData: false)
    #expect(throws: InterpreterError.self) { try MicrophonePCM.copy(sample) }
}

private func makeMicrophoneSample(
    _ pcm: AVAudioPCMBuffer, ready: Bool = true, includeData: Bool = true
) throws -> CMSampleBuffer {
    var description: CMAudioFormatDescription?
    #expect(CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault, asbd: pcm.format.streamDescription,
        layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
        extensions: nil, formatDescriptionOut: &description
    ) == noErr)
    var sample: CMSampleBuffer?
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: CMTimeScale(pcm.format.sampleRate)),
        presentationTimeStamp: .zero, decodeTimeStamp: .invalid
    )
    #expect(CMSampleBufferCreate(
        allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: ready,
        makeDataReadyCallback: nil, refcon: nil, formatDescription: description,
        sampleCount: Int(pcm.frameLength), sampleTimingEntryCount: pcm.frameLength == 0 ? 0 : 1,
        sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
        sampleBufferOut: &sample
    ) == noErr)
    let result = try #require(sample)
    if includeData {
        #expect(CMSampleBufferSetDataBufferFromAudioBufferList(
            result, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0, bufferList: pcm.audioBufferList
        ) == noErr)
    }
    return result
}
