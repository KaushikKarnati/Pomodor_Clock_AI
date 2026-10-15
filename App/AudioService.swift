import AVFoundation
import UIKit

@MainActor protocol FocusAudioPlaying {
    func tick(odd: Bool, sound: Bool, haptics: Bool)
    func ratchet(notches: Int, haptics: Bool)
    func bell()
    func stop()
    /// Loads the person's chosen winding, ticking and alarm sounds.
    func configure(_ selection: SoundSelection)
    /// Plays one option once so it can be auditioned in Settings.
    func preview(_ option: SoundOption)
    /// Clears a stale interruption: iOS does not promise an `.ended` for every `.began`.
    func resumeAfterForeground()
}
extension FocusAudioPlaying {
    func configure(_ selection: SoundSelection) {}
    func preview(_ option: SoundOption) {}
    func resumeAfterForeground() {}
}
@MainActor final class AudioService: FocusAudioPlaying {
    private let sounds = SoundPlayers()
    private var selection: SoundSelection?
    private let ratchetFeedback = UIImpactFeedbackGenerator(style: .rigid)
    private let tickOddFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let tickEvenFeedback = UIImpactFeedbackGenerator(style: .light)
    private var lastRatchetHaptic: TimeInterval = -.infinity
    private var ratchetCadence = RatchetCadence()
    private var interrupted = false
    private var interruptionObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            // A `.began` for an app that was suspended is never followed by `.ended`; treating it as a
            // live interruption would mute every tick, click and bell until relaunch.
            let reason = notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
            if reason == AVAudioSession.InterruptionReason.appWasSuspended.rawValue { return }
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

    private func play(_ name: String, repeats: Int = 1, rate: Float = 1, allowInactive: Bool = false) {
        let state = UIApplication.shared.applicationState
        guard !interrupted, state == .active || (allowInactive && state == .inactive) else { return }
        let sounds = self.sounds
        AudioSessionCoordinator.shared.perform { sounds.play(name, repeats: repeats, rate: rate) }
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
        guard notches > 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let cadence = ratchetCadence.update(notches: notches, at: now)
        play("ratchet", repeats: cadence.repeats, rate: cadence.rate)
        if haptics, now - lastRatchetHaptic >= 0.03 {
            lastRatchetHaptic = now
            ratchetFeedback.impactOccurred()
            ratchetFeedback.prepare()
        }
    }

    /// A block end must be heard even with Control Center or a banner over the app.
    func bell() { play("bell", allowInactive: true) }

    func stop() {
        ratchetCadence = RatchetCadence()
        let sounds = self.sounds
        AudioSessionCoordinator.shared.perform { sounds.stop() }
    }

    func resumeAfterForeground() {
        interrupted = false
        ambient()
    }

    func configure(_ selection: SoundSelection) {
        guard selection != self.selection else { return }
        self.selection = selection
        let sounds = self.sounds
        AudioSessionCoordinator.shared.perform { sounds.load(selection) }
    }

    func preview(_ option: SoundOption) {
        guard !interrupted, UIApplication.shared.applicationState == .active, !option.files.isEmpty else { return }
        let files = option.files
        let sounds = self.sounds
        AudioSessionCoordinator.shared.perform { sounds.preview(files) }
    }
}

/// Measures elapsed time per crossed notch, independently of display refresh rate.
struct RatchetCadence {
    private var previousTime: TimeInterval?
    mutating func update(notches: Int, at time: TimeInterval) -> (repeats: Int, rate: Float) {
        let elapsed = previousTime.map { time - $0 }
        previousTime = time
        guard let elapsed, elapsed > 0, elapsed < 0.2 else {
            return (min(3, max(1, notches)), 1)
        }
        let interval = elapsed / Double(max(1, notches))
        // Slow turns retain isolated original clicks. Quick turns produce a
        // short rolling burst whose spacing shrinks with measured dial speed.
        guard interval < 0.065 else { return (1, 1) }
        let speed = min(1, max(0, (0.065 - interval) / 0.05))
        return (speed > 0.4 ? 3 : 2, Float(1 + speed))
    }
}

/// Only accessed from the shared audio worker, including implicit activation in
/// prepareToPlay/play. Haptic generators remain on the main actor.
protocol AudioClipPlaying: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get set }
    var numberOfLoops: Int { get set }
    var rate: Float { get set }
    @discardableResult func play() -> Bool
    func stop()
}
extension AVAudioPlayer: AudioClipPlaying {}

/// Players are keyed by role ("ratchet", "tickOdd", "tickEven", "bell"); each role plays
/// whichever file the person selected. The Classic files keep the original names.
final class SoundPlayers: @unchecked Sendable {
    private var players: [String: any AudioClipPlaying]
    private var files: [String: String] = ["tickOdd": "tickOdd", "tickEven": "tickEven", "ratchet": "ratchet", "bell": "bell"]
    private var previewPlayer: AVAudioPlayer?
    init(players: [String: any AudioClipPlaying] = [:]) { self.players = players }
    func prepare() {
        dispatchPrecondition(condition: .notOnQueue(.main))
        for (role, file) in files where players[role] == nil {
            players[role] = Self.makePlayer(file, role: role)
        }
    }
    /// Swaps only the roles whose file changed. A role with no file (ticking off) is silent.
    func load(_ selection: SoundSelection) {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let wanted: [String: String?] = ["ratchet": selection.wind, "tickOdd": selection.tickOdd, "tickEven": selection.tickEven, "bell": selection.alarm]
        for (role, file) in wanted {
            guard let file else { players[role]?.stop(); players[role] = nil; files[role] = nil; continue }
            guard files[role] != file || players[role] == nil else { continue }
            players[role]?.stop()
            files[role] = file
            players[role] = Self.makePlayer(file, role: role)
        }
    }
    func preview(_ fileNames: [String]) {
        dispatchPrecondition(condition: .notOnQueue(.main))
        previewPlayer?.stop()
        pairedPreview?.stop()
        pairedPreview = nil
        // Ticks preview as a short odd/even pair so their alternation can be heard.
        guard let first = fileNames.first, let player = Self.makePlayer(first, role: "preview") else { return }
        previewPlayer = player
        player.play()
        if fileNames.count == 2, let second = Self.makePlayer(fileNames[1], role: "preview") {
            second.play(atTime: player.deviceCurrentTime + 0.5)
            pairedPreview = second
        }
    }
    private var pairedPreview: AVAudioPlayer?
    private static func makePlayer(_ file: String, role: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: file, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.enableRate = role == "ratchet"
        player.prepareToPlay()
        return player
    }
    func play(_ name: String, repeats: Int = 1, rate: Float = 1) {
        dispatchPrecondition(condition: .notOnQueue(.main))
        if name == "bell" { players["tickOdd"]?.stop(); players["tickEven"]?.stop() }
        // Ticks wait for a ringing alarm (alarms run 2–5 s) instead of talking over it.
        if name == "tickOdd" || name == "tickEven", players["bell"]?.isPlaying == true { return }
        guard let player = players[name] else { return }
        // Adjust an active burst without rewinding its audible transient.
        // Finite loops keep the tail below 66 ms without timers or a backlog.
        if name == "ratchet" { player.rate = min(2, max(1, rate)) }
        if name == "ratchet", player.isPlaying { return }
        player.numberOfLoops = name == "ratchet" ? min(3, max(1, repeats)) - 1 : 0
        player.currentTime = 0
        player.play()
    }
    func stop() {
        dispatchPrecondition(condition: .notOnQueue(.main))
        players.values.forEach { $0.stop() }
        previewPlayer?.stop()
        pairedPreview?.stop()
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
