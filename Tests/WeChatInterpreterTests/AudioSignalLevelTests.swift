import AVFoundation
import Testing
@testable import WeChatInterpreter

@Test func signalLevelDistinguishesMissingFramesFromSilence() {
    var level = AudioSignalLevel()
    #expect(level.samples == 0)
    #expect(!level.hasSignal)
    level.observe(0)
    #expect(level.samples == 1)
    #expect(!level.hasSignal)
}

@Test(arguments: [false, true])
func signalLevelReadsBothPCMChannelsAndOnlyValidFrames(interleaved: Bool) throws {
    let format = try #require(AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: interleaved
    ))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
    buffer.frameLength = 4
    for block in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
        let data = try #require(block.mData).assumingMemoryBound(to: Float.self)
        for index in 0..<Int(block.mDataByteSize) / 4 { data[index] = 0 }
    }
    let channels = try #require(buffer.floatChannelData)
    // 有效声音只在右声道，不能只检测第一声道。
    channels[interleaved ? 0 : 1][interleaved ? 3 : 1] = -0.5
    // 容量尾部不属于有效帧，不能把未播放的内存算作音频信号。
    channels[0][interleaved ? 6 : 3] = 1
    buffer.frameLength = 2
    var level = AudioSignalLevel()
    level.observe(buffer)
    #expect(level.samples == 4)
    #expect(level.peak == 0.5)
    #expect(level.hasSignal)
}

@Test func signalLevelRejectsNonFiniteSamples() {
    var level = AudioSignalLevel()
    level.observe(Float.nan)
    level.observe(Float.infinity)
    level.observe(-Float.infinity)
    #expect(level.samples == 0)
    #expect(!level.hasSignal)
    level.observe(-0.25)
    #expect(level.peak == 0.25)
    #expect(level.hasSignal)
}

@Test func signalLevelNormalizesIntegerSpeech() throws {
    let format = try #require(AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 22_050, channels: 1, interleaved: false
    ))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
    buffer.frameLength = 1
    let channels = try #require(buffer.int16ChannelData)
    channels[0][0] = -16384
    var level = AudioSignalLevel()
    level.observe(buffer)
    #expect(level.peak == 0.5)
    #expect(level.samples == 1)
}
