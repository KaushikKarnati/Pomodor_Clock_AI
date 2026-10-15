import AVFoundation
import CoreHaptics
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
    private var ambientConfigured = false
    private var interruptionObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                guard let self else { return }
                self.interrupted = raw == AVAudioSession.InterruptionType.began.rawValue
                if self.interrupted { self.ambientConfigured = false; self.stop() }
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
        guard !ambientConfigured else { return }
        ambientConfigured = true
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, mode: .default)
            try? session.setActive(true)
        }
    }

    private func play(_ name: String) {
        guard !interrupted, UIApplication.shared.applicationState == .active else { return }
        if name == "bell" { players["tickOdd"]?.stop(); players["tickEven"]?.stop() }
        guard let player = players[name] else { return }
        if player.isPlaying {
            player.currentTime = 0
        } else {
            player.play()
        }
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
