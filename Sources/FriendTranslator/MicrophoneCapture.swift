@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

/// 配置、启动、停止及音频回调均在同一队列执行；不更改系统默认设备。
final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    // 两种语言轮流使用同一麦克风；新会话必须排在旧会话清理之后。
    private static let captureQueue = DispatchQueue(label: "dev.benny.interpreter.microphone")
    private let queue = MicrophoneCapture.captureQueue
    private let session = AVCaptureSession()
    private var receiveAudio: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var endAudio: (@Sendable () -> Void)?
    private var acceptingAudio = false
    private var errorObserver: NSObjectProtocol?
    private let onFailure: @Sendable (String) -> Void

    init(onFailure: @escaping @Sendable (String) -> Void) { self.onFailure = onFailure }

    func start(uid: String, request: SFSpeechAudioBufferRecognitionRequest) async throws {
        try await start(uid: uid, receiveAudio: { request.append($0) }, endAudio: { request.endAudio() })
    }

    func start(
        uid: String,
        receiveAudio: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        endAudio: @escaping @Sendable () -> Void = {}
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard let device = AVCaptureDevice(uniqueID: uid), device.hasMediaType(.audio) else {
                        throw InterpreterError("找不到所选麦克风，请检查设备后重试。")
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureAudioDataOutput()
                    output.audioSettings = MicrophonePCM.captureSettings
                    session.beginConfiguration()
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        throw InterpreterError("无法连接所选麦克风，请检查设备是否可用。")
                    }
                    session.addInput(input)
                    guard session.canAddOutput(output) else {
                        session.removeInput(input)
                        session.commitConfiguration()
                        throw InterpreterError("无法建立麦克风音频输出。")
                    }
                    session.addOutput(output)
                    output.setSampleBufferDelegate(self, queue: queue)
                    session.commitConfiguration()
                    self.receiveAudio = receiveAudio
                    self.endAudio = endAudio
                    acceptingAudio = true
                    errorObserver = NotificationCenter.default.addObserver(
                        forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
                    ) { @Sendable [weak self] notification in
                        let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
                            ?? "麦克风采集会话中断。"
                        self?.onFailure(message)
                    }
                    session.startRunning()
                    guard session.isRunning else { throw InterpreterError("麦克风未能启动，请检查权限和设备连接。") }
                    continuation.resume()
                } catch {
                    teardown()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop(cancelling task: SFSpeechRecognitionTask? = nil) {
        queue.async { [self] in
            teardown()
            // 先排空采集回调、结束输入，再取消识别，避免取消后仍追加音频。
            task?.cancel()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard acceptingAudio, let receiveAudio else { return }
        do {
            if let pcm = try MicrophonePCM.copy(sampleBuffer) { receiveAudio(pcm) }
        } catch {
            acceptingAudio = false
            onFailure(error.localizedDescription)
        }
    }

    private func teardown() {
        let finishAudio = endAudio
        acceptingAudio = false
        receiveAudio = nil
        endAudio = nil
        if let errorObserver { NotificationCenter.default.removeObserver(errorObserver) }
        errorObserver = nil
        for case let output as AVCaptureAudioDataOutput in session.outputs {
            output.setSampleBufferDelegate(nil, queue: nil)
        }
        session.stopRunning()
        finishAudio?()
        for output in session.outputs { session.removeOutput(output) }
        for input in session.inputs { session.removeInput(input) }
    }
}
