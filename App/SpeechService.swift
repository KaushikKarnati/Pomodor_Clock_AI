import Foundation
import Speech
import AVFoundation
import Observation

/// Apple's on-device Speech recognizer. No audio files or cloud fallback.
@MainActor @Observable final class SpeechService {
    var text = ""
    var isRecording = false
    var isPreparing = false
    var error: String?
    var onFinished: ((String) -> Void)?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?
    private var generation = UUID()
    private var ownsAudioSession = false
    func start() async {
        guard !isRecording, !isPreparing else { return }
        isPreparing = true; error = nil; text = ""
        let token = UUID(); generation = token
        defer { if generation == token { isPreparing = false } }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard generation == token else { return }
        guard mic else { error = "Microphone access is off. You can type below, or enable access in Settings."; return }
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard generation == token else { return }
        guard authorization == .authorized else { error = "Speech recognition access is off. Type your request below."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            error = "On-device English speech recognition isn't available. Type your request below."; return
        }
        do {
            ownsAudioSession = true
            try await AudioSessionCoordinator.shared.prepareRecording()
            guard generation == token else { return }
            let audioEngine = AVAudioEngine()
            let bufferRequest = SFSpeechAudioBufferRecognitionRequest()
            bufferRequest.requiresOnDeviceRecognition = true; bufferRequest.shouldReportPartialResults = true
            let input = audioEngine.inputNode; let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { throw PlanError.invalid("No microphone is available. Type your request instead.") }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in bufferRequest.append(buffer) }
            engine = audioEngine; request = bufferRequest
            recognition = recognizer.recognitionTask(with: bufferRequest) { [weak self] result, failure in
                let transcription = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                let message = failure?.localizedDescription
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if let transcription, self.text != transcription {
                        self.text = transcription; self.armSilence(seconds: 2, token: token)
                    }
                    if final { self.finish() }
                    else if let message { self.error = "Speech stopped: \(message). You can edit the text below."; self.stop() }
                }
            }
            audioEngine.prepare(); try audioEngine.start(); isRecording = true
            armSilence(seconds: 12, token: token)
        } catch {
            guard generation == token else { return }
            self.error = error.localizedDescription
            stop()
        }
    }
    private func armSilence(seconds: Double, token: UUID) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.generation == token else { return }; self.finish()
        }
    }
    func finish() {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasRecording = isRecording
        stop()
        if wasRecording, !words.isEmpty { onFinished?(words) }
    }
    func stop() {
        generation = UUID(); silence?.cancel(); silence = nil
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        request?.endAudio(); request = nil; recognition?.cancel(); recognition = nil
        isRecording = false; isPreparing = false
        if ownsAudioSession {
            ownsAudioSession = false
            AudioSessionCoordinator.shared.finishRecording()
        }
    }
}
