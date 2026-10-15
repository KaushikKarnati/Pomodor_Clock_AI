import Foundation
import UIKit
import UserNotifications
@preconcurrency import ActivityKit

@MainActor protocol FocusPersisting {
    func load() throws -> SavedState
    func save(_ state: SavedState, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void)
}
@MainActor final class DiskStore: FocusPersisting {
    private let url: URL
    private let writer: StateFileWriter
    init() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("FocusTalk", isDirectory: true)
        #if DEBUG
        url = directory.appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "sessions-uitests.json" : "sessions.json")
        #else
        url = directory.appendingPathComponent("sessions.json")
        #endif
        writer = StateFileWriter(url: url)
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
    func save(_ state: SavedState, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        // Give already queued writes time to finish when the app backgrounds.
        let lease = PersistenceLease()
        writer.save(state) { result in
            Task { @MainActor in
                lease.end()
                completion(result)
            }
        }
    }
}

@MainActor private final class PersistenceLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Save focus session") { [weak self] in
            Task { @MainActor in self?.end() }
        }
    }
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }

}
@MainActor protocol SessionServing {
    func requestNotifications() async -> Bool
    func sync(session: FocusSession?, auto: Bool)
}

@MainActor final class SessionServices: NSObject, UNUserNotificationCenterDelegate, SessionServing {
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
