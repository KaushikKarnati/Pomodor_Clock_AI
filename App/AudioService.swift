import AVFoundation
import UIKit

@MainActor protocol FocusAudioPlaying {
    func tick(odd: Bool, sound: Bool, haptics: Bool)
    func ratchet(notches: Int, haptics: Bool)
    func bell()
    func stop()
}
@MainActor final class AudioService: FocusAudioPlaying {
    private let sounds = SoundPlayers()
    private let ratchetFeedback = UIImpactFeedbackGenerator(style: .rigid)
    private let tickOddFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let tickEvenFeedback = UIImpactFeedbackGenerator(style: .light)
    private var lastRatchetHaptic: TimeInterval = -.infinity
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
        ambient()
        let sounds = self.sounds
        AudioSessionCoordinator.shared.perform { sounds.prepare() }
        ratchetFeedback.prepare()
        tickOddFeedback.prepare()
        tickEvenFeedback.prepare()
    }

    func ambient() {
        AudioSessionCoordinator.shared.prepareAmbient()
    }

    private func play(_ name: String) {
        guard !interrupted, UIApplication.shared.applicationState == .active else { return }
        let sounds = self.sounds
        AudioSessionCoordinator.shared.perform { sounds.play(name) }
    }

    func tick(odd: Bool, sound: Bool, haptics: Bool) {
        if sound { play(odd ? "tickOdd" : "tickEven") }
        if haptics {
            let generator = odd ? tickOddFeedback : tickEvenFeedback
            generator.impactOccurred()
            generator.prepare()
        }
    }

    func ratchet(notches: Int, haptics: Bool) {
        guard notches > 0, !interrupted, UIApplication.shared.applicationState == .active else { return }
        let requestedAt = ProcessInfo.processInfo.systemUptime
        let sounds = self.sounds
        AudioSessionCoordinator.shared.perform {
            // Do not replay old gesture events after slow audio-session transitions.
            guard ProcessInfo.processInfo.systemUptime - requestedAt < 0.1 else { return }
            sounds.ratchet(notches: notches)
        }
        // Haptics have their own rate limit; it must not discard audible clicks.
        if haptics, requestedAt - lastRatchetHaptic >= 0.03 {
            lastRatchetHaptic = requestedAt
            ratchetFeedback.impactOccurred()
            ratchetFeedback.prepare()
        }
    }

    func bell() { play("bell") }

    func stop() {
        let sounds = self.sounds
        AudioSessionCoordinator.shared.perform { sounds.stop() }
    }
}

/// Only accessed from the shared audio worker, including implicit activation in
/// prepareToPlay/play. Haptic generators remain on the main actor.
private final class SoundPlayers: @unchecked Sendable {
    private var players: [String: AVAudioPlayer] = [:]
    private var ratchetPlayers: [AVAudioPlayer] = []
    private var ratchetIndex = 0
    private var ratchetSchedule = RatchetSchedule()
    func prepare() {
        dispatchPrecondition(condition: .notOnQueue(.main))
        for name in ["tickOdd", "tickEven", "bell"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "wav"),
               let player = try? AVAudioPlayer(contentsOf: url) {
                player.prepareToPlay()
                players[name] = player
            }
        }
        if let url = Bundle.main.url(forResource: "ratchet", withExtension: "wav") {
            // A 22 ms sample plus the 43 ms scheduling horizon needs at most nine
            // voices at 8 ms spacing. Twelve prewarmed players leave headroom.
            for _ in 0..<12 {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    ratchetPlayers.append(player)
                }
            }
        }
    }
    func ratchet(notches: Int) {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let clock = ratchetPlayers.first else { return }
        for time in ratchetSchedule.clicks(crossedNotches: notches, at: clock.deviceCurrentTime) {
            let player = ratchetPlayers[ratchetIndex]
            ratchetIndex = (ratchetIndex + 1) % ratchetPlayers.count
            player.currentTime = 0
            player.play(atTime: time)
        }
    }

    func play(_ name: String) {
        dispatchPrecondition(condition: .notOnQueue(.main))
        if name == "bell" { players["tickOdd"]?.stop(); players["tickEven"]?.stop() }
        guard let player = players[name] else { return }
        player.currentTime = 0
        player.play()
    }
    func stop() {
        dispatchPrecondition(condition: .notOnQueue(.main))
        players.values.forEach { $0.stop() }
        ratchetPlayers.forEach { $0.stop() }
        ratchetSchedule.reset()
        ratchetIndex = 0
    }
}

/// A FIFO that waits for each asynchronous operation's completion before starting
/// the next. A plain serial DispatchQueue alone does not order async callbacks.
final class AudioWorkQueue: @unchecked Sendable {
    typealias Completion = @Sendable () -> Void
    typealias Operation = @Sendable (@escaping Completion) -> Void
    private let queue = DispatchQueue(label: "com.focustalk.audio-session", qos: .userInitiated)
    private var pending: [Operation] = []
    private var running = false

    func enqueue(_ operation: @escaping Operation) {
        queue.async { [self] in
            pending.append(operation)
            runNext()
        }
    }
    func continueOnWorker(_ operation: @escaping @Sendable () -> Void) {
        queue.async(execute: operation)
    }
    private func runNext() {
        guard !running, !pending.isEmpty else { return }
        running = true
        let operation = pending.removeFirst()
        operation { [self] in
            queue.async { [self] in
                running = false
                runNext()
            }
        }
    }
}

/// Session transitions and player operations share the same asynchronous FIFO.
/// `recording` is accessed only on the worker, never in a system callback.
final class AudioSessionCoordinator: @unchecked Sendable {
    static let shared = AudioSessionCoordinator()
    private let work = AudioWorkQueue()
    private var recording = false

    func perform(_ operation: @escaping @Sendable () -> Void) {
        work.enqueue { done in operation(); done() }
    }

    func prepareAmbient() {
        work.enqueue { [self] done in
            guard !recording else { done(); return }
            let session = AVAudioSession.sharedInstance()
            do { try session.setCategory(.ambient, mode: .default) }
            catch { done(); return }
            activate(session) { _ in done() }
        }
    }

    func prepareRecording() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            work.enqueue { [self] done in
                recording = true
                let session = AVAudioSession.sharedInstance()
                do {
                    try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
                } catch {
                    continuation.resume(throwing: error)
                    done()
                    return
                }
                activate(session) { result in
                    continuation.resume(with: result)
                    done()
                }
            }
        }
    }

    func finishRecording() {
        work.enqueue { [self] done in
            recording = false
            let session = AVAudioSession.sharedInstance()
            deactivate(session) { [self] _ in
                work.continueOnWorker {
                    try? session.setCategory(.ambient, mode: .default)
                    done()
                }
            }
        }
    }

    private func activate(_ session: AVAudioSession, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        if #available(iOS 27.0, *) {
            session.activate(options: []) { activated, error in
                completion(Self.result(succeeded: activated, error: error))
            }
        } else {
            dispatchPrecondition(condition: .notOnQueue(.main))
            completion(Result { try session.setActive(true) })
        }
    }

    private func deactivate(_ session: AVAudioSession, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        if #available(iOS 27.0, *) {
            session.deactivate(options: [.notifyOthersOnDeactivation]) { deactivated, error in
                completion(Self.result(succeeded: deactivated, error: error))
            }
        } else {
            dispatchPrecondition(condition: .notOnQueue(.main))
            completion(Result { try session.setActive(false, options: .notifyOthersOnDeactivation) })
        }
    }

    private static func result(succeeded: Bool, error: Error?) -> Result<Void, Error> {
        if let error { return .failure(error) }
        return succeeded ? .success(()) : .failure(PlanError.invalid("The audio session could not change state. Try again."))
    }
}
