@preconcurrency import AVFoundation
import CoreML
import FluidAudio
import Foundation
import Testing

// 显式提供本地模型和合成音频时才运行：不录音、不下载模型、不调用云服务。
@Test(.enabled(if: ProcessInfo.processInfo.environment["INTERPRETER_ASR_FIXTURE"] != nil))
func localEnglishTranscribesSyntheticAudio() async throws {
    let audio = try #require(ProcessInfo.processInfo.environment["INTERPRETER_ASR_FIXTURE"])
    let models = try #require(ProcessInfo.processInfo.environment["INTERPRETER_ASR_MODELS"])
    let config = MLModelConfiguration()
    config.computeUnits = .cpuAndNeuralEngine
    let engine = StreamingEouAsrManager(configuration: config, chunkSize: .ms320, eouDebounceMs: 400)
    try await engine.loadModels(from: URL(fileURLWithPath: models))
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: audio))
    var transcript = ""
    while file.framePosition < file.length {
        let frame = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
        try file.read(into: frame)
        try await engine.appendAudio(frame)
        try await engine.processBufferedAudio()
        if await engine.eouDetected {
            let silence = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.processingFormat.sampleRate)))
    silence.frameLength = silence.frameCapacity
    for buffer in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
        if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
    }
    try await engine.appendAudio(silence)
    try await engine.processBufferedAudio()
    transcript += try await engine.finish() + " "
            await engine.reset()
        }
    }
    let silence = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.processingFormat.sampleRate)))
    silence.frameLength = silence.frameCapacity
    for buffer in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
        if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
    }
    try await engine.appendAudio(silence)
    try await engine.processBufferedAudio()
    transcript += try await engine.finish()
    print("Local English fixture transcript: \(transcript)")
    #expect(transcript.lowercased().contains("meeting"))
    #expect(transcript.lowercased().contains("tomorrow"))
    #expect(transcript.lowercased().contains("morning"))
    #expect(transcript.lowercased().contains("notebook"))
}
