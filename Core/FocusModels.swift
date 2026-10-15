import Foundation

struct FocusBlock: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var minutes: Int
    var isBreak = false
    var goal: String = ""
    var seconds: TimeInterval { Double(minutes * 60) }

    init(id: UUID = UUID(), title: String, minutes: Int, isBreak: Bool = false, goal: String = "") {
        self.id = id
        self.title = title
        self.minutes = minutes
        self.isBreak = isBreak
        self.goal = goal
    }

    enum CodingKeys: String, CodingKey {
        case id, title, minutes, isBreak, goal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.minutes = try container.decode(Int.self, forKey: .minutes)
        self.isBreak = try container.decodeIfPresent(Bool.self, forKey: .isBreak) ?? false
        self.goal = try container.decodeIfPresent(String.self, forKey: .goal) ?? ""
    }
}
struct FocusPlan: Codable, Equatable, Sendable {
    var blocks: [FocusBlock]
    var budgetMinutes: Int
    var totalMinutes: Int { blocks.reduce(0) { $0 + $1.minutes } }
    var focusBlockCount: Int { blocks.filter { !$0.isBreak }.count }
    func validated() throws -> Self {
        guard !blocks.isEmpty, blocks.count <= 30 else { throw PlanError.invalid("Add between 1 and 30 blocks.") }
        guard Set(blocks.map(\.id)).count == blocks.count,
              blocks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 160 && (1...120).contains($0.minutes) }) else {
            throw PlanError.invalid("Each block needs a title and a duration of 1–120 minutes.")
        }
        guard (1...480).contains(budgetMinutes), totalMinutes <= budgetMinutes else {
            throw PlanError.invalid("The plan must fit within your available time (up to 8 hours).")
        }
        return self
    }
    /// Earlier builds could lengthen a block from the dial without raising the budget, which made
    /// otherwise valid saved sessions fail validation and blocked every save. Accept those files.
    func repairingBudget() -> Self {
        var plan = self
        if plan.totalMinutes > plan.budgetMinutes, plan.totalMinutes <= 480 { plan.budgetMinutes = plan.totalMinutes }
        return plan
    }
}
enum PlanError: LocalizedError { case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
enum SessionStatus: String, Codable, Sendable { case ready, running, paused, finished, ended }
struct FocusSession: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var plan: FocusPlan
    var index = 0
    var status: SessionStatus = .ready
    var remaining: TimeInterval
    var deadline: Date?
    var createdAt: Date
    var completed: [UUID] = []
    var skipped: [UUID] = []
    init(plan: FocusPlan, now: Date = .now) {
        self.plan = plan; remaining = plan.blocks.first?.seconds ?? 0; createdAt = now
    }
    var current: FocusBlock? { plan.blocks.indices.contains(index) ? plan.blocks[index] : nil }
    var isActive: Bool { status == .running || status == .paused }
    func secondsLeft(at now: Date) -> TimeInterval { max(0, status == .running ? (deadline?.timeIntervalSince(now) ?? remaining) : remaining) }
    func sessionSecondsLeft(at now: Date) -> TimeInterval {
        guard status != .finished, status != .ended else { return 0 }
        return secondsLeft(at: now) + plan.blocks.dropFirst(index + 1).reduce(0) { $0 + $1.seconds }
    }
    mutating func start(at now: Date) {
        guard current != nil, [.ready, .paused].contains(status) else { return }
        status = .running; deadline = now.addingTimeInterval(remaining)
    }
    mutating func pause(at now: Date) {
        guard status == .running else { return }; remaining = secondsLeft(at: now); deadline = nil; status = .paused
    }
    /// Advances from persisted deadlines, never from callback counts. Returns elapsed block count.
    @discardableResult mutating func reconcile(at now: Date, auto: Bool) -> Int {
        var count = 0
        while status == .running, let end = deadline, end <= now, let block = current {
            completed.append(block.id); count += 1; index += 1
            guard let next = current else { status = .finished; remaining = 0; deadline = nil; break }
            remaining = next.seconds
            if auto { deadline = end.addingTimeInterval(remaining) }
            else { status = .paused; deadline = nil }
        }
        return count
    }
    mutating func extend(at now: Date) {
        guard current != nil, [.ready,.paused,.running].contains(status), plan.totalMinutes + 5 <= 480,
              plan.blocks[index].minutes + 5 <= 120 else { return }
        remaining = secondsLeft(at: now) + 300; plan.blocks[index].minutes += 5
        plan.budgetMinutes = max(plan.budgetMinutes, plan.totalMinutes)
        if status == .running { deadline = now.addingTimeInterval(remaining) }
    }
    /// Changes the remaining time without invalidating the persisted plan budget.
    mutating func setRemainingMinutes(_ minutes: Int, at now: Date) throws {
        guard isActive, plan.blocks.indices.contains(index), (1...120).contains(minutes) else {
            throw PlanError.invalid("Choose a duration from 1 to 120 minutes.")
        }
        var updated = plan
        updated.blocks[index].minutes = max(updated.blocks[index].minutes, minutes)
        updated.budgetMinutes = max(updated.budgetMinutes, updated.totalMinutes)
        plan = try updated.validated()
        remaining = Double(minutes * 60)
        deadline = status == .running ? now.addingTimeInterval(remaining) : nil
    }

    /// Past rows use the original schedule; current/future rows follow remaining time.
    /// Paused rows assume resuming now, since a future resume time is unknowable.
    func timelineStartDates(at now: Date) -> [Date] {
        var date = createdAt
        return plan.blocks.enumerated().map { offset, block in
            if offset == index, isActive {
                date = now.addingTimeInterval(secondsLeft(at: now) - block.seconds)
            }
            let start = date
            date = date.addingTimeInterval(block.seconds)
            return start
        }
    }

    mutating func skip(at now: Date, auto: Bool) {
        guard let block = current, [.ready,.paused,.running].contains(status) else { return }
        let wasRunning = status == .running
        skipped.append(block.id); index += 1
        guard let next = current else { status = .finished; deadline = nil; remaining = 0; return }
        remaining = next.seconds; status = wasRunning && auto ? .running : .paused
        deadline = status == .running ? now.addingTimeInterval(remaining) : nil
    }
    mutating func end(at now: Date) { remaining = secondsLeft(at: now); status = .ended; deadline = nil }
    func boundaries(auto: Bool) -> [(Date, String)] {
        guard status == .running, let deadline, let current else { return [] }
        var result = [(deadline, current.title)]; var date = deadline
        if auto { for block in plan.blocks.dropFirst(index + 1) { date = date.addingTimeInterval(block.seconds); result.append((date, block.title)) } }
        return result
    }
}
struct FocusSettings: Codable, Equatable, Sendable {
    var voice = true
    var tick = true
    var haptics = true
    var auto = true
    var object: TimerObjectID = .tomato
    var windSound = SoundCatalog.classic
    var tickSound = SoundCatalog.classic
    var alarmSound = SoundCatalog.classic

    enum CodingKeys: String, CodingKey {
        case voice, tick, haptics, auto, object, windSound, tickSound, alarmSound
    }

    init(voice: Bool = true, tick: Bool = true, haptics: Bool = true, auto: Bool = true) {
        self.voice = voice
        self.tick = tick
        self.haptics = haptics
        self.auto = auto
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tick = try container.decodeIfPresent(Bool.self, forKey: .tick) ?? true
        self.haptics = try container.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        self.auto = try container.decodeIfPresent(Bool.self, forKey: .auto) ?? true
        self.voice = try container.decodeIfPresent(Bool.self, forKey: .voice) ?? true
        // Appearance keys are optional and lenient: an unknown value must never block loading
        // (a load failure blocks all writes for that launch).
        let objectName = (try? container.decodeIfPresent(String.self, forKey: .object)) ?? nil
        self.object = objectName.flatMap(TimerObjectID.init(rawValue:)) ?? .tomato
        self.windSound = Self.known((try? container.decodeIfPresent(String.self, forKey: .windSound)) ?? nil, for: .wind)
        self.tickSound = Self.known((try? container.decodeIfPresent(String.self, forKey: .tickSound)) ?? nil, for: .tick)
        self.alarmSound = Self.known((try? container.decodeIfPresent(String.self, forKey: .alarmSound)) ?? nil, for: .alarm)
        if tickSound == SoundCatalog.none { tick = false; tickSound = SoundCatalog.classic }
    }

    private static func known(_ id: String?, for role: SoundRole) -> String {
        guard let id, SoundCatalog.isKnown(id, for: role) else { return SoundCatalog.classic }
        return id
    }
}
struct SavedState: Codable, Sendable {
    var version = 1
    var session: FocusSession?
    var history: [FocusSession] = []
    var settings = FocusSettings()
}
