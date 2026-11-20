import AVFoundation
import Foundation
import Speech

/// Live speech-to-text for the mic button. Stops on its own after a short pause.
@MainActor
@Observable
final class SpeechRecognizer {
    var transcript = ""
    var isRecording = false
    var level: Float = 0
    var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var onFinish: ((String) -> Void)?

    func start(onFinish: @escaping (String) -> Void) async {
        errorMessage = nil
        guard await Self.authorize() else {
            errorMessage = "Allow Microphone and Speech Recognition for Pilot in iPhone Settings."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        self.onFinish = onFinish
        transcript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = false }
            request = req

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                req.append(buffer)
                let lvl = Self.rms(buffer)
                Task { @MainActor in self?.level = lvl }
            }
            engine.prepare()
            try engine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        self.restartSilenceTimer()
                        if result.isFinal { self.stop() }
                    }
                    if error != nil, self.isRecording { self.stop() }
                }
            }
            restartSilenceTimer(after: 6)
        } catch {
            errorMessage = "Couldn't start the microphone."
            stop()
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        silenceTask?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let done = onFinish
        onFinish = nil
        if !text.isEmpty { done?(text) }
    }

    private func restartSilenceTimer(after seconds: Double = 1.6) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return min(1, sqrt(sum / Float(n)) * 12)
    }
}
