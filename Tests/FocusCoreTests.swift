import XCTest
@testable import FocusCore
final class FocusCoreTests: XCTestCase {
    func testLegacySpokenReplyPreferenceDoesNotBreakSavedSettings() throws {
        let data = Data(#"{"voice":true,"tick":false,"haptics":true,"auto":false}"#.utf8)
        let settings = try JSONDecoder().decode(FocusSettings.self, from: data)
        XCTAssertFalse(settings.tick)
        XCTAssertTrue(settings.haptics)
        XCTAssertFalse(settings.auto)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        XCTAssertEqual(encoded?["voice"] as? Bool, true)
    }
    func testFullSessionCountdownAcrossBreakBoundary() {
        let plan = FocusPlan(blocks: [.init(title: "Read book", minutes: 25), .init(title: "Break", minutes: 5, isBreak: true)], budgetMinutes: 30)
        var session = FocusSession(plan: plan, now: now)
        session.start(at: now)
        XCTAssertEqual(session.sessionSecondsLeft(at: now), 1800)
        let boundary = now.addingTimeInterval(1500)
        session.reconcile(at: boundary, auto: true)
        XCTAssertEqual(session.sessionSecondsLeft(at: boundary), 300)
        session.pause(at: boundary.addingTimeInterval(20))
        XCTAssertEqual(session.sessionSecondsLeft(at: boundary.addingTimeInterval(200)), 280)
        session.end(at: boundary.addingTimeInterval(200))
        XCTAssertEqual(session.sessionSecondsLeft(at: boundary.addingTimeInterval(200)), 0)
    }
    func testVoiceOffSurvivesReloadAndMissingPreferenceDefaultsOn() throws {
        let restored = try JSONDecoder().decode(FocusSettings.self, from: JSONEncoder().encode(FocusSettings(voice: false)))
        XCTAssertFalse(restored.voice)
        XCTAssertTrue(try JSONDecoder().decode(FocusSettings.self, from: Data("{}".utf8)).voice)
    }

    func testDialIncreaseRemainsValidAfterReload() throws {
        var session = FocusSession(plan: FocusPlan(blocks: [.init(title: "Focus", minutes: 25)], budgetMinutes: 25), now: now)
        session.start(at: now)
        try session.setRemainingMinutes(30, at: now.addingTimeInterval(20))
        let restored = try JSONDecoder().decode(FocusSession.self, from: JSONEncoder().encode(session))
        XCTAssertNoThrow(try restored.plan.validated())
        XCTAssertEqual(restored.plan.budgetMinutes, 30)
        XCTAssertEqual(restored.deadline, now.addingTimeInterval(1820))
    }

    func testDialLimitRejectsChangeWithoutMutatingSession() throws {
        let plan = FocusPlan(blocks: [.init(title: "First", minutes: 1)] + (0..<4).map { _ in .init(title: "Work", minutes: 119) }, budgetMinutes: 480)
        var session = FocusSession(plan: plan, now: now)
        session.start(at: now)
        let original = session
        XCTAssertThrowsError(try session.setRemainingMinutes(60, at: now))
        XCTAssertEqual(session, original)
        XCTAssertThrowsError(try session.setRemainingMinutes(-1, at: now))
        XCTAssertEqual(session, original)
    }

    func testTimelineDoesNotDriftWithElapsedTimeAndFollowsPause() {
        var session = FocusSession(plan: plan(), now: now)
        session.start(at: now)
        let later = now.addingTimeInterval(30)
        XCTAssertEqual(session.timelineStartDates(at: now), session.timelineStartDates(at: later))
        session.pause(at: later)
        let resume = now.addingTimeInterval(100)
        XCTAssertEqual(session.timelineStartDates(at: resume)[1], resume.addingTimeInterval(90))
        session.start(at: resume)
        session.reconcile(at: resume.addingTimeInterval(100), auto: true)
        XCTAssertEqual(session.timelineStartDates(at: resume.addingTimeInterval(100))[2], resume.addingTimeInterval(150))
    }

    func testExtremeDecodedDurationsAreRejectedWithoutOverflow() {
        XCTAssertThrowsError(try FocusPlan(blocks: [.init(title: "One", minutes: Int.max), .init(title: "Two", minutes: Int.max)], budgetMinutes: 480).validated())
    }

    let now = Date(timeIntervalSince1970: 1000)
    func plan() -> FocusPlan { FocusPlan(blocks: [.init(title: "Write", minutes: 2), .init(title: "Rest", minutes: 1, isBreak: true), .init(title: "Review", minutes: 2)], budgetMinutes: 5) }
    func testRelaunchAdvancesAcrossMultipleDeadlinesExactlyOnce() throws {
        var original = FocusSession(plan: plan(), now: now); original.start(at: now)
        var restored = try JSONDecoder().decode(FocusSession.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.reconcile(at: now.addingTimeInterval(190), auto: true), 2)
        XCTAssertEqual(restored.index, 2); XCTAssertEqual(restored.secondsLeft(at: now.addingTimeInterval(190)), 110)
        XCTAssertEqual(restored.reconcile(at: now.addingTimeInterval(190), auto: true), 0)
        XCTAssertEqual(restored.reconcile(at: now.addingTimeInterval(400), auto: true), 1)
        XCTAssertEqual(restored.status, .finished); XCTAssertEqual(restored.completed.count, 3)
    }
    func testManualProgressionNeverConsumesNextBlock() {
        var s = FocusSession(plan: plan(), now: now); s.start(at: now)
        XCTAssertEqual(s.reconcile(at: now.addingTimeInterval(900), auto: false), 1)
        XCTAssertEqual(s.status, .paused); XCTAssertEqual(s.remaining, 60)
        s.start(at: now.addingTimeInterval(900)); XCTAssertEqual(s.deadline, now.addingTimeInterval(960))
    }
    func testPauseExtensionAndSkip() {
        var s = FocusSession(plan: plan(), now: now); s.start(at: now); s.pause(at: now.addingTimeInterval(30))
        XCTAssertEqual(s.remaining, 90); XCTAssertNil(s.deadline)
        s.extend(at: now.addingTimeInterval(800)); XCTAssertEqual(s.remaining, 390)
        s.start(at: now.addingTimeInterval(900)); XCTAssertEqual(s.deadline, now.addingTimeInterval(1290))
        s.skip(at: now.addingTimeInterval(910), auto: true)
        XCTAssertEqual(s.skipped.count, 1); XCTAssertEqual(s.deadline, now.addingTimeInterval(970))
    }
    func testNotificationsFollowExtensionsAndPause() {
        var s = FocusSession(plan: plan(), now: now); s.start(at: now)
        XCTAssertEqual(s.boundaries(auto: true).map(\.0), [120,180,300].map { now.addingTimeInterval(Double($0)) })
        s.extend(at: now); XCTAssertEqual(s.boundaries(auto: true).last?.0, now.addingTimeInterval(600))
        s.pause(at: now); XCTAssertTrue(s.boundaries(auto: true).isEmpty)
    }
    func testInvalidPlansRejected() {
        XCTAssertThrowsError(try FocusPlan(blocks: [], budgetMinutes: 20).validated())
        XCTAssertThrowsError(try FocusPlan(blocks: [.init(title: "", minutes: 2)], budgetMinutes: 2).validated())
        XCTAssertThrowsError(try FocusPlan(blocks: [.init(title: "Task", minutes: 0)], budgetMinutes: 2).validated())
        XCTAssertThrowsError(try FocusPlan(blocks: plan().blocks, budgetMinutes: 4).validated())
        XCTAssertNoThrow(try plan().validated())
    }
    func testEndAndCompletedCannotRestart() {
        var s = FocusSession(plan: plan(), now: now); s.start(at: now); s.end(at: now)
        s.start(at: now); XCTAssertEqual(s.status, .ended); XCTAssertTrue(s.boundaries(auto: true).isEmpty)
    }
}
