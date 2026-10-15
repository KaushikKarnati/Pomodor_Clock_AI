import Foundation
import UserNotifications
@preconcurrency import ActivityKit

@MainActor protocol FocusPersisting {
    func load() throws -> SavedState
    func save(_ state: SavedState) throws
}
@MainActor final class DiskStore: FocusPersisting {
    private let url: URL
    init() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("FocusTalk", isDirectory: true)
        #if DEBUG
        url = directory.appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "sessions-uitests.json" : "sessions.json")
        #else
        url = directory.appendingPathComponent("sessions.json")
        #endif
    }
    func load() throws -> SavedState {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-ui-state") { return SavedState() }
        #endif
        guard FileManager.default.fileExists(atPath: url.path) else { return SavedState() }
        let state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
        guard state.version == 1 else { throw PlanError.invalid("This saved file uses a newer version of FocusTalk.") }
        if let session = state.session {
            _ = try session.plan.validated()
            guard session.index >= 0, session.index <= session.plan.blocks.count,
                  session.remaining.isFinite, session.remaining >= 0,
                  (session.status != .running || session.deadline != nil),
                  (!session.isActive || session.index < session.plan.blocks.count) else { throw PlanError.invalid("The saved timer could not be read safely.") }
        }
        return state
    }
    func save(_ state: SavedState) throws {
        let destination = self.url
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(state)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                #if DEBUG
                print("Failed to save state in background: \(error)")
                #endif
            }
        }
    }
}
@MainActor final class SessionServices: NSObject, UNUserNotificationCenterDelegate {
    private var syncTask: Task<Void, Never>?
    override init() { super.init(); UNUserNotificationCenter.current().delegate = self }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [] }
    func requestNotifications() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
    func sync(session: FocusSession?, auto: Bool) {
        syncTask?.cancel()
        syncTask = Task {
            let center = UNUserNotificationCenter.current()
            let requestGeneration = UUID().uuidString
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            if let session {
                for (index, boundary) in session.boundaries(auto: auto).enumerated() where boundary.0 > .now {
                    guard !Task.isCancelled else { return }
                    let content = UNMutableNotificationContent()
                    content.title = "\(boundary.1) finished"
                    content.body = auto ? "Your focus session is progressing. Open FocusTalk to see what's next." : "Ready for the next block? Open FocusTalk and tap Start."
                    content.sound = UNNotificationSound(named: .init(rawValue: "bell.wav"))
                    let request = UNNotificationRequest(identifier: "\(requestGeneration)-\(session.id)-\(index)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, boundary.0.timeIntervalSinceNow), repeats: false))
                    try? await center.add(request)
                    if Task.isCancelled { center.removePendingNotificationRequests(withIdentifiers: [request.identifier]); return }
                }
            }
            guard !Task.isCancelled else { return }
            await updateActivity(session, auto: auto)
        }
    }
    private func updateActivity(_ session: FocusSession?, auto: Bool) async {
        guard let session, session.isActive, let block = session.current else {
            for activity in Activity<SessionActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }; return
        }
        let end = session.deadline ?? Date.now.addingTimeInterval(session.remaining)
        let finalEnd = end.addingTimeInterval(session.plan.blocks.dropFirst(session.index + 1).reduce(0) { $0 + $1.seconds })
        // With automatic progression, count down the full session so the system can
        // keep updating accurately without requiring background app execution.
        let displayEnd = auto ? finalEnd : end
        let displayRemaining = session.secondsLeft(at: .now) + (auto ? session.plan.blocks.dropFirst(session.index + 1).reduce(0) { $0 + $1.seconds } : 0)
        let duration = auto ? Double(session.plan.totalMinutes * 60) : block.seconds
        let content = ActivityContent(state: SessionActivityAttributes.ContentState(start: displayEnd.addingTimeInterval(-duration), title: block.title, end: displayEnd, sessionEnd: finalEnd, isRunning: session.status == .running, remaining: displayRemaining, position: "\(session.index + 1) of \(session.plan.blocks.count)"), staleDate: session.status == .running ? displayEnd : nil)
        for activity in Activity<SessionActivityAttributes>.activities where activity.attributes.sessionID != session.id.uuidString {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard !Task.isCancelled else { return }
        if let existing = Activity<SessionActivityAttributes>.activities.first(where: { $0.attributes.sessionID == session.id.uuidString }) { await existing.update(content) }
        else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: SessionActivityAttributes(sessionID: session.id.uuidString), content: content, pushType: nil)
        }
    }
}
