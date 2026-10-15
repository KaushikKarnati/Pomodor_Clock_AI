import Foundation
import Observation
import AVFoundation

@MainActor @Observable final class VoiceService: NSObject, AVSpeechSynthesizerDelegate {
    var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

@MainActor @Observable final class FocusStore {
    var saved = SavedState()
    var now = Date.now
    var error: String?
    var notice: String?
    var proposal: FocusPlan?
    var reply = ""
    var said = ""
    var busy = false
    var isForeground = true
    var isListening = false
    var isRattling = false
    var toastMessage: String?

    var session: FocusSession? { saved.session }
    var settings: FocusSettings { saved.settings }
    var aiUnavailable: String? { planner.unavailableReason }

    /// Remaining time on the CURRENT block (in seconds)
    var remaining: Double {
        if let s = session, s.isActive {
            return s.secondsLeft(at: now)
        } else if let p = proposal, let first = p.blocks.first {
            return first.seconds
        }
        return 0
    }

    /// Remaining minutes on current block (for tomato dial 0–60)
    var currentBlockMinutes: Double {
        return remaining / 60.0
    }

    /// Current whole seconds on active block (for countdown readout)
    var displaySeconds: Int {
        max(0, Int(remaining.rounded(.down)))
    }

    /// Remaining time for the entire session across all blocks
    var sessionRemaining: Double {
        session?.sessionSecondsLeft(at: now) ?? (proposal?.blocks.reduce(0) { $0 + $1.seconds } ?? 0)
    }

    let audio: any FocusAudioPlaying
    let voice = VoiceService()
    private let disk: any FocusPersisting
    private let planner: any FocusPlanning
    private let services = SessionServices()
    private var ticker: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var lastSecond: Int?
    private var persistenceBlocked = false

    init(disk: any FocusPersisting = DiskStore(), planner: any FocusPlanning = PlanningService(), audio: any FocusAudioPlaying = AudioService()) {
        self.disk = disk; self.planner = planner; self.audio = audio
        do { saved = try disk.load() } catch { self.error = "Saved data could not be opened. It has been preserved. \(error.localizedDescription)"; persistenceBlocked = true }
        let autoAdvance = settings.auto
        _ = saved.session?.reconcile(at: .now, auto: autoAdvance)
        archiveFinished(); persist(); services.sync(session: session, auto: settings.auto)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                let isRunning = await (self?.session?.status == .running)
                try? await Task.sleep(nanoseconds: isRunning ? 200_000_000 : 500_000_000)
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func toast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    func tick() {
        guard let s = session, s.status == .running else {
            lastSecond = nil
            return
        }
        now = .now
        let autoAdvance = settings.auto
        let prevBlock = s.current
        let transitions = saved.session?.reconcile(at: now, auto: autoAdvance) ?? 0
        if transitions > 0 {
            archiveFinished(); persist(); services.sync(session: session, auto: settings.auto)
            if isForeground && !isListening {
                audio.bell()
                triggerRattle()
            }
            lastSecond = nil

            if let s = session {
                if s.status == .finished {
                    toast("Session done")
                    if settings.voice {
                        voice.speak("That’s the whole session. Nice work.")
                    }
                } else if let next = s.current {
                    toast("Now: \(next.title)")
                    if settings.voice {
                        let lead = (prevBlock?.isBreak == true) ? "Break’s over." : "Time’s up."
                        let line: String
                        if next.isBreak {
                            line = "\(lead) Take a \(next.minutes) minute break."
                        } else {
                            let goalPart = next.goal.isEmpty ? "" : " \(next.goal)."
                            line = "\(lead) Next: \(next.title).\(goalPart) \(next.minutes) minutes."
                        }
                        voice.speak(line)
                    }
                }
            }
        }
        guard isForeground, !isListening, session?.status == .running, transitions == 0 else { lastSecond = nil; return }
        let second = Int(remaining.rounded(.down))
        if second != lastSecond {
            if lastSecond != nil, second > 0 { audio.tick(odd: second % 2 != 0, sound: settings.tick, haptics: settings.haptics) }
            lastSecond = second
        }
    }

    private func triggerRattle() {
        isRattling = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1600))
            self?.isRattling = false
        }
    }

    func setForeground(_ active: Bool) {
        isForeground = active; lastSecond = nil
        if !active { audio.stop(); voice.stop(); persist() }
        else {
            now = .now; let autoAdvance = settings.auto; _ = saved.session?.reconcile(at: now, auto: autoAdvance)
            archiveFinished(); persist(); services.sync(session: session, auto: settings.auto)
        }
    }

    func setListening(_ value: Bool) {
        isListening = value
        lastSecond = nil
        if value {
            audio.stop()
            voice.stop()
        }
    }

    func saveSettings(_ value: FocusSettings) {
        tick(); saved.settings = value; persist(); services.sync(session: session, auto: value.auto)
    }

    func propose(words: String, budget: Int = 30) {
        cancelGeneration()
        busy = true
        reply = ""
        said = words
        proposal = nil

        // Check local quick command
        if let cmd = matchQuickCommand(words) {
            busy = false
            handleQuickCommand(cmd)
            return
        }

        let current = session?.plan
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await planner.propose(words: words, budget: budget, current: current)
                guard !Task.isCancelled else { return }
                proposal = result.plan
                reply = result.reply
                busy = false
                if settings.voice, !result.reply.isEmpty {
                    voice.speak(result.reply)
                }
            } catch {
                guard !Task.isCancelled else { return }
                busy = false
                self.error = error.localizedDescription
            }
        }
    }

    private func matchQuickCommand(_ text: String) -> String? {
        let w = text.lowercased().trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespacesAndNewlines)
        if proposal != nil && ["start", "go", "begin", "let's go", "lets go", "looks good", "sounds good", "do it", "start session"].contains(w) {
            return "accept"
        }
        if session?.status == .running && ["pause", "hold on", "wait"].contains(w) {
            return "pause"
        }
        if session?.status == .paused && ["resume", "continue", "keep going", "unpause", "start"].contains(w) {
            return "resume"
        }
        if session?.isActive == true && ["skip", "skip this block", "next", "next block"].contains(w) {
            return "skip"
        }
        if session?.isActive == true && ["add 5 minutes", "add five minutes", "five more minutes", "5 more minutes", "plus 5"].contains(w) {
            return "plus"
        }
        if session?.isActive == true && ["end session", "stop session", "finish session"].contains(w) {
            return "end"
        }
        return nil
    }

    private func handleQuickCommand(_ cmd: String) {
        switch cmd {
        case "accept":
            if let p = proposal {
                apply(p, startImmediately: true)
                reply = "Starting now."
                if settings.voice { voice.speak(reply) }
            }
        case "pause":
            if session?.status == .running {
                startPause()
                reply = "Paused."
                if settings.voice { voice.speak(reply) }
            }
        case "resume":
            if session?.status == .paused {
                startPause()
                reply = "Back to it."
                if settings.voice { voice.speak(reply) }
            }
        case "skip":
            skip()
            reply = "Skipped."
            if settings.voice { voice.speak(reply) }
        case "plus":
            extend()
            reply = "Added five minutes."
            if settings.voice { voice.speak(reply) }
        case "end":
            end()
            reply = "Session ended."
            if settings.voice { voice.speak(reply) }
        default:
            break
        }
    }

    func cancelGeneration() { generationTask?.cancel(); generationTask = nil; busy = false }

    func apply(_ plan: FocusPlan, startImmediately: Bool = true) {
        do {
            let valid = try plan.validated()
            if var previous = saved.session, previous.isActive { previous.end(at: .now); saved.history.insert(previous, at: 0) }
            saved.session = FocusSession(plan: valid)
            proposal = nil
            cancelGeneration()
            if let first = valid.blocks.first {
                toast("Now: \(first.title)")
                if settings.voice && startImmediately {
                    let goalText = first.goal.isEmpty ? "" : " \(first.goal)."
                    voice.speak(first.isBreak ? "Starting with break, \(first.minutes) minutes." : "First up: \(first.title).\(goalText) \(first.minutes) minutes.")
                }
            }
            if startImmediately { startPause() } else { changed() }
        } catch { self.error = error.localizedDescription }
    }

    func setManualMinutes(_ minutes: Int) {
        if minutes == 0 {
            if session?.isActive == true {
                advanceBlockToNext()
            } else {
                saved.session = nil
                changed()
            }
            return
        }
        if var s = saved.session, s.isActive {
            let idx = s.index
            s.plan.blocks[idx].minutes = max(s.plan.blocks[idx].minutes, minutes)
            s.remaining = Double(minutes * 60)
            if s.status == .running {
                s.deadline = now.addingTimeInterval(s.remaining)
            }
            saved.session = s
            toast("\(minutes) minute\(minutes == 1 ? "" : "s") on the timer")
            changed()
        } else {
            let plan = FocusPlan(blocks: [.init(title: "Focus", minutes: minutes)], budgetMinutes: minutes)
            apply(plan, startImmediately: true)
            toast("\(minutes) minute\(minutes == 1 ? "" : "s") on the timer")
            if settings.voice {
                voice.speak("Timer set for \(minutes) minute\(minutes == 1 ? "." : "s.")")
            }
        }
    }

    private func advanceBlockToNext() {
        skip()
    }

    func startPause() {
        tick()
        if session?.status == .running {
            saved.session?.pause(at: .now)
            audio.stop()
            toast("Paused")
        } else {
            saved.session?.start(at: .now)
            if let cur = session?.current {
                toast("Now: \(cur.title)")
            }
            Task { [weak self] in
                guard let self else { return }
                if !(await services.requestNotifications()) {
                    notice = "Notifications are off. The timer still works; enable notifications in Settings for alerts while locked."
                }
                services.sync(session: session, auto: settings.auto)
            }
        }
        changed()
    }

    func extend() {
        tick()
        saved.session?.extend(at: .now)
        toast("Added 5 minutes")
        changed()
    }

    func skip() {
        tick()
        let autoAdvance = settings.auto
        saved.session?.skip(at: .now, auto: autoAdvance)
        archiveFinished()
        if let cur = session?.current, session?.isActive == true {
            toast("Now: \(cur.title)")
        } else if session?.status == .finished {
            toast("Session done")
        } else {
            toast("Skipped")
        }
        changed()
    }

    func end() {
        saved.session?.end(at: .now)
        archiveFinished()
        audio.stop()
        voice.stop()
        toast("Session ended")
        changed()
    }

    func startOver() {
        cancelGeneration()
        audio.stop()
        voice.stop()
        saved.session = nil
        proposal = nil
        reply = ""
        said = ""
        toast("Started over")
        changed()
    }

    func clear() {
        if session?.isActive == true { end() }
        saved.session = nil
        proposal = nil
        changed()
    }

    func runDemo() {
        cancelGeneration()
        voice.stop()
        said = "I've got two and a half hours tonight. I need to finish the client deck, study SQL for about forty minutes, and reply to three emails. Dinner somewhere in the middle."
        reply = "Here’s your evening: five focus blocks with dinner in the middle, done in about two and a half hours. First up, the client deck."
        let demoBlocks: [FocusBlock] = [
            .init(title: "Client deck", minutes: 25, isBreak: false, goal: "Outline the story and the first slides"),
            .init(title: "Short break", minutes: 5, isBreak: true),
            .init(title: "Client deck", minutes: 25, isBreak: false, goal: "Finish the slides and send for review"),
            .init(title: "Short break", minutes: 5, isBreak: true),
            .init(title: "SQL study", minutes: 25, isBreak: false, goal: "Joins and window functions"),
            .init(title: "Dinner", minutes: 30, isBreak: true),
            .init(title: "SQL study", minutes: 15, isBreak: false, goal: "Practice problems"),
            .init(title: "Short break", minutes: 5, isBreak: true),
            .init(title: "Emails", minutes: 15, isBreak: false, goal: "Reply to all three")
        ]
        proposal = FocusPlan(blocks: demoBlocks, budgetMinutes: 150)
        toast("Plan ready")
        if settings.voice {
            voice.speak(reply)
        }
    }

    func deleteHistory(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) { saved.history.remove(at: index) }
        persist()
    }

    private func changed() {
        now = .now
        lastSecond = nil
        persist()
        services.sync(session: session, auto: settings.auto)
    }

    private func archiveFinished() {
        guard let s = session, s.status == .finished || s.status == .ended else { return }
        if !saved.history.contains(where: { $0.id == s.id }) { saved.history.insert(s, at: 0) }
    }

    private func persist() {
        guard !persistenceBlocked else { return }
        do { try disk.save(saved) } catch { self.error = "Couldn't save this session: \(error.localizedDescription)" }
    }
}
