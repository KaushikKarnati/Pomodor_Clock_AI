import AVFoundation
import UIKit

@MainActor protocol FocusAudioPlaying {
    func tick(odd: Bool, sound: Bool, haptics: Bool)
    func ratchet(haptics: Bool)
    func bell()
    func stop()
}
@MainActor final class AudioService: FocusAudioPlaying {
    private var players: [String: AVAudioPlayer] = [:]
    private let ratchetFeedback = UIImpactFeedbackGenerator(style: .rigid)
    private let tickOddFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let tickEvenFeedback = UIImpactFeedbackGenerator(style: .light)
    private var lastRatchet = Date.distantPast
    private var interrupted = false
    private var interruptionObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                guard let self else { return }
                self.interrupted = raw == AVAudioSession.InterruptionType.began.rawValue
                if self.interrupted { self.stop() }
                else { AudioSessionCoordinator.shared.prepareAmbient() }
            }
        }
        for name in ["tickOdd", "tickEven", "ratchet", "bell"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "wav"), let player = try? AVAudioPlayer(contentsOf: url) {
                player.prepareToPlay()
                players[name] = player
            }
        }
        ratchetFeedback.prepare()
        tickOddFeedback.prepare()
        tickEvenFeedback.prepare()
        ambient()
    }

    func ambient() {
        AudioSessionCoordinator.shared.prepareAmbient()
    }

    private func play(_ name: String) {
        guard !interrupted, UIApplication.shared.applicationState == .active else { return }
        if name == "bell" { players["tickOdd"]?.stop(); players["tickEven"]?.stop() }
        guard let player = players[name] else { return }
        player.currentTime = 0
        player.play()
    }

    func tick(odd: Bool, sound: Bool, haptics: Bool) {
        if sound { play(odd ? "tickOdd" : "tickEven") }
        if haptics {
            let generator = odd ? tickOddFeedback : tickEvenFeedback
            generator.impactOccurred()
            generator.prepare()
        }
    }

    func ratchet(haptics: Bool) {
        guard Date.now.timeIntervalSince(lastRatchet) > 0.03 else { return }
        lastRatchet = .now
        play("ratchet")
        if haptics {
            ratchetFeedback.impactOccurred()
            ratchetFeedback.prepare()
        }
    }

    func bell() { play("bell") }

    func stop() {
        players.values.forEach { $0.stop() }
    }
}

/// All category/activation changes share one queue, including rapid mic restarts.
/// `recording` is accessed only by that queue.
final class AudioSessionCoordinator: @unchecked Sendable {
    static let shared = AudioSessionCoordinator()
    private let queue = DispatchQueue(label: "com.focustalk.audio-session", qos: .userInitiated)
    private var recording = false

    func prepareAmbient() {
        queue.async { [self] in
            guard !recording else { return }
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, mode: .default)
            try? session.setActive(true)
        }
    }

    func prepareRecording() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                let result = Result<Void, Error> {
                    recording = true
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
                    try session.setActive(true)
                }
                continuation.resume(with: result)
            }
        }
    }

    func finishRecording() {
        queue.async { [self] in
            recording = false
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(.ambient, mode: .default)
        }
    }
}
