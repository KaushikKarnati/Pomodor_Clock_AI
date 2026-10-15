import XCTest
@testable import FocusTalk

@MainActor final class FocusStoreTests: XCTestCase {
    private func makeStore(disk: MemoryDisk = MemoryDisk(), planner: StubPlanner = StubPlanner()) -> FocusStore {
        FocusStore(disk: disk, planner: planner, audio: SilentAudio(), services: StubServices())
    }

    func testAcceptCommandKeepsAndStartsProposalWithoutCallingAI() {
        let planner = StubPlanner()
        let store = makeStore(planner: planner)
        store.runDemo()
        let proposal = store.proposal
        store.propose(words: " Start! ")
        XCTAssertEqual(store.session?.plan, proposal)
        XCTAssertEqual(store.session?.status, .running)
        XCTAssertNil(store.proposal)
        XCTAssertEqual(planner.calls, 0)
        store.setForeground(false)
    }

    func testDialChangesPersistValidStateAndUseFreshDeadline() throws {
        let disk = MemoryDisk()
        let store = makeStore(disk: disk)
        store.setManualMinutes(25)
        store.setManualMinutes(30)
        XCTAssertNoThrow(try disk.state.session?.plan.validated())
        XCTAssertEqual(disk.state.session?.plan.budgetMinutes, 30)
        XCTAssertEqual(store.session!.secondsLeft(at: .now), 1800, accuracy: 1)
        store.setForeground(false)
        let reloaded = makeStore(disk: disk)
        XCTAssertNil(reloaded.error)
        XCTAssertEqual(reloaded.session?.plan.totalMinutes, 30)
        reloaded.setForeground(false)
    }

    func testWriteFailureReachesStore() {
        let disk = MemoryDisk()
        let store = makeStore(disk: disk)
        disk.failWrites = true
        store.saveSettings(FocusSettings(voice: false))
        XCTAssertTrue(store.error?.contains("Couldn't save") == true)
    }

    func testLoadFailurePreservesFileByBlockingWrites() {
        let disk = MemoryDisk()
        disk.failLoads = true
        let store = makeStore(disk: disk)
        store.setManualMinutes(25)
        XCTAssertEqual(disk.saveCount, 0)
        XCTAssertTrue(store.error?.contains("preserved") == true)
        store.setForeground(false)
    }

    func testIdlePausedAndBackgroundClockDoesNotPoll() async throws {
        let store = makeStore()
        let idleNow = store.now
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(store.now, idleNow)
        store.setManualMinutes(25)
        store.startPause()
        let pausedNow = store.now
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(store.now, pausedNow)
        store.startPause()
        store.setForeground(false)
        let backgroundNow = store.now
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(store.now, backgroundNow)
        store.setForeground(true)
        XCTAssertGreaterThan(store.now, backgroundNow)
        store.setForeground(false)
    }

    func testRunningClockDoesNotPublishAtFiveHertz() async throws {
        let store = makeStore()
        store.setManualMinutes(25)
        defer { store.setForeground(false) }
        var last = store.now
        var changes = 0
        let end = Date.now.addingTimeInterval(2.4)
        while Date.now < end {
            try await Task.sleep(for: .milliseconds(20))
            if store.now != last { changes += 1; last = store.now }
        }
        XCTAssertGreaterThanOrEqual(changes, 2)
        XCTAssertLessThanOrEqual(changes, 3)
    }

    func testAIStartsNewPlanButRequiresAcceptanceForReplacement() async {
        let planner = StubPlanner()
        let store = makeStore(planner: planner)
        store.propose(words: "Read for 25 minutes")
        while store.busy { await Task.yield() }
        XCTAssertEqual(store.session?.status, .running)
        let firstID = store.session?.id
        store.propose(words: "Revise my plan")
        while store.busy { await Task.yield() }
        XCTAssertEqual(store.session?.id, firstID)
        XCTAssertNotNil(store.proposal)
        store.propose(words: "start")
        XCTAssertNotEqual(store.session?.id, firstID)
        XCTAssertEqual(store.saved.history.first?.id, firstID)
        store.setForeground(false)
    }

    func testPlannerFailureStopsBusyAndExposesError() async {
        let planner = StubPlanner()
        planner.fail = true
        let store = makeStore(planner: planner)
        store.propose(words: "Read")
        while store.busy { await Task.yield() }
        XCTAssertEqual(store.error, "AI unavailable")
        XCTAssertNil(store.proposal)
    }

    func testStartOverArchivesActiveSession() {
        let store = makeStore()
        store.setManualMinutes(25)
        let id = store.session?.id
        store.startOver()
        XCTAssertNil(store.session)
        XCTAssertEqual(store.saved.history.first?.id, id)
        XCTAssertEqual(store.saved.history.first?.status, .ended)
    }
}

@MainActor private final class MemoryDisk: FocusPersisting {
    var state = SavedState(settings: FocusSettings(voice: false))
    var failWrites = false
    var failLoads = false
    var saveCount = 0
    func load() throws -> SavedState {
        if failLoads { throw PlanError.invalid("Unreadable test file") }
        return state
    }
    func save(_ state: SavedState, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        saveCount += 1
        if failWrites { completion(.failure(PlanError.invalid("Disk full"))) }
        else { self.state = state; completion(.success(())) }
    }
}
@MainActor private final class StubPlanner: FocusPlanning {
    var unavailableReason: String? { nil }
    var calls = 0
    var fail = false
    func propose(words: String, budget: Int, current: FocusPlan?) async throws -> PlanningAnswer {
        calls += 1
        if fail { throw PlanError.invalid("AI unavailable") }
        return PlanningAnswer(plan: FocusPlan(blocks: [.init(title: "Read", minutes: 25)], budgetMinutes: 25), reply: "Ready")
    }
}
@MainActor private final class SilentAudio: FocusAudioPlaying {
    func tick(odd: Bool, sound: Bool, haptics: Bool) {}
    func ratchet(notches: Int, haptics: Bool) {}
    func bell() {}
    func stop() {}
}
@MainActor private final class StubServices: SessionServing {
    func requestNotifications() async -> Bool { true }
    func sync(session: FocusSession?, auto: Bool) {}
}

final class AudioWorkQueueTests: XCTestCase {
    func testAsyncCompletionKeepsLaterAudioOperationsOrderedAndOffMain() {
        let queue = AudioWorkQueue()
        let trace = AudioTrace()
        let finished = expectation(description: "Ordered audio operations finish")
        queue.enqueue { done in
            XCTAssertFalse(Thread.isMainThread)
            trace.append("activate")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                trace.append("activation completed")
                done()
            }
        }
        queue.enqueue { done in
            XCTAssertFalse(Thread.isMainThread)
            trace.append("prepare player")
            done()
        }
        queue.enqueue { done in
            XCTAssertFalse(Thread.isMainThread)
            trace.append("play")
            done()
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)
        XCTAssertEqual(trace.values, ["activate", "activation completed", "prepare player", "play"])
    }

    func testTeardownContinuationFinishesBeforeNewRecording() {
        let queue = AudioWorkQueue()
        let trace = AudioTrace()
        let finished = expectation(description: "Teardown finishes before restart")
        queue.enqueue { done in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                queue.continueOnWorker {
                    XCTAssertFalse(Thread.isMainThread)
                    trace.append("restore category")
                    done()
                }
            }
        }
        queue.enqueue { done in
            trace.append("new recording")
            done()
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)
        XCTAssertEqual(trace.values, ["restore category", "new recording"])
    }
}

private final class AudioTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var values: [String] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }
    func append(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        entries.append(value)
    }
}
