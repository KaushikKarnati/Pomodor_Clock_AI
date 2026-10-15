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

    func testDialChangeStartedOnAnEarlierBlockIsNotAppliedToTheNextBlock() {
        let store = makeStore()
        store.runDemo()
        store.propose(words: "start")
        let first = store.session?.current?.id
        store.skip()
        let second = store.session?.current
        XCTAssertNotEqual(second?.id, first)
        XCTAssertFalse(store.setManualMinutes(10, expectedBlock: first))
        XCTAssertEqual(store.session?.current?.minutes, second?.minutes)
        XCTAssertTrue(store.setManualMinutes(10, expectedBlock: second?.id))
        XCTAssertEqual(store.session!.secondsLeft(at: .now), 600, accuracy: 1)
        store.setForeground(false)
    }

    func testRejectedDialChangeReportsFailure() {
        let store = makeStore()
        store.setManualMinutes(25)
        XCTAssertFalse(store.setManualMinutes(121))
        XCTAssertEqual(store.session!.secondsLeft(at: .now), 1500, accuracy: 1)
        store.setForeground(false)
    }

    func testChoosingAnObjectPersistsItAndLoadsItsSounds() {
        let disk = MemoryDisk()
        let audio = RecordingAudio()
        let store = FocusStore(disk: disk, planner: StubPlanner(), audio: audio, services: StubServices())
        XCTAssertEqual(audio.selections.last?.alarm, "bell")
        store.selectObject(.hourglass)
        XCTAssertEqual(disk.state.settings.object, .hourglass)
        XCTAssertEqual(audio.selections.last, SoundSelection(wind: "wind-sand", tickOdd: "tick-sand-odd", tickEven: "tick-sand-even", alarm: "alarm-glassChime"))
        store.setSound("none", for: .tick)
        XCTAssertNil(audio.selections.last?.tickOdd)
        XCTAssertFalse(disk.state.settings.tick)
        store.setSound("gong", for: .alarm)
        XCTAssertEqual(audio.previews.last?.id, "gong")
        XCTAssertEqual(audio.selections.last?.alarm, "alarm-gong")
    }

    func testRepeatedLimitMessageIsPublishedAgain() {
        let store = makeStore()
        store.setManualMinutes(60)
        for _ in 0..<13 { store.extend() }  // 60 → 120 minutes, then one rejected
        XCTAssertEqual(store.notice, "This block or session has reached its time limit.")
        store.notice = nil
        store.extend()
        XCTAssertEqual(store.notice, "This block or session has reached its time limit.")
        store.setForeground(false)
    }
}

@MainActor private final class RecordingAudio: FocusAudioPlaying {
    var selections: [SoundSelection] = []
    var previews: [SoundOption] = []
    func tick(odd: Bool, sound: Bool, haptics: Bool) {}
    func ratchet(notches: Int, haptics: Bool) {}
    func bell() {}
    func stop() {}
    func configure(_ selection: SoundSelection) { selections.append(selection) }
    func preview(_ option: SoundOption) { previews.append(option) }
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

final class RatchetPlaybackTests: XCTestCase {
    func testSameNotchCountGetsFasterCadenceWhenTurnedFaster() {
        var slow = RatchetCadence()
        var fast = RatchetCadence()
        _ = slow.update(notches: 1, at: 1)
        _ = fast.update(notches: 1, at: 1)
        let isolated = slow.update(notches: 1, at: 1.15)
        let rolling = fast.update(notches: 1, at: 1.015)
        XCTAssertEqual(isolated.repeats, 1)
        XCTAssertEqual(isolated.rate, 1)
        XCTAssertEqual(rolling.repeats, 3)
        XCTAssertEqual(rolling.rate, 2, accuracy: 0.001)
        let resumed = fast.update(notches: 1, at: 2)
        XCTAssertEqual(resumed.repeats, 1)
        XCTAssertEqual(resumed.rate, 1)
    }

    func testCrossedNotchesDetermineSpeedRatherThanCallbackFrequency() {
        var cadence = RatchetCadence()
        _ = cadence.update(notches: 1, at: 1)
        let burst = cadence.update(notches: 4, at: 1.06)
        XCTAssertEqual(burst.repeats, 3)
        XCTAssertEqual(burst.rate, 2, accuracy: 0.001)
    }

    func testRapidRequestsDoNotCutOffAnAudibleClick() {
        let done = expectation(description: "Ratchet playback")
        DispatchQueue.global().async {
            let clip = TestAudioClip()
            let sounds = SoundPlayers(players: ["ratchet": clip])
            sounds.play("ratchet")
            clip.currentTime = 0.005
            for _ in 0..<100 { sounds.play("ratchet", repeats: 3, rate: 2) }
            XCTAssertEqual(clip.rate, 2)
            XCTAssertEqual(clip.starts, 1)
            XCTAssertEqual(clip.currentTime, 0.005)
            clip.isPlaying = false // Natural completion allows the next click.
            sounds.play("ratchet", repeats: 3)
            XCTAssertEqual(clip.starts, 2)
            XCTAssertEqual(clip.numberOfLoops, 2)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }

    func testFastJumpIsShortAndStopCancelsIt() {
        let done = expectation(description: "Bounded immediate playback")
        DispatchQueue.global().async {
            let clip = TestAudioClip()
            let sounds = SoundPlayers(players: ["ratchet": clip])
            sounds.play("ratchet", repeats: 60)
            XCTAssertEqual(clip.starts, 1)
            XCTAssertEqual(clip.numberOfLoops, 2)
            sounds.stop()
            XCTAssertFalse(clip.isPlaying)
            sounds.play("ratchet")
            XCTAssertEqual(clip.numberOfLoops, 0)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }
}

private final class TestAudioClip: AudioClipPlaying {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var numberOfLoops = 0
    var rate: Float = 1
    var starts = 0
    func play() -> Bool { starts += 1; isPlaying = true; return true }
    func stop() { isPlaying = false }
}
