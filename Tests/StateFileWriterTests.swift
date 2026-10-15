import XCTest
@testable import FocusCore

final class StateFileWriterTests: XCTestCase {
    func testQueuedWritesPreserveLatestState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sessions.json")
        let writer = StateFileWriter(url: url)
        let done = expectation(description: "All queued saves complete")
        done.expectedFulfillmentCount = 100
        for index in 0..<100 {
            var state = SavedState()
            state.version = index
            writer.save(state) { result in
                if case .failure(let error) = result { XCTFail("Save failed: \(error)") }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 10)
        let restored = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
        XCTAssertEqual(restored.version, 99)
    }

    func testWriteFailureIsReportedAndLaterSaveCanRecover() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("blocked")
        try Data().write(to: blocker)
        let url = blocker.appendingPathComponent("sessions.json")
        let writer = StateFileWriter(url: url)
        let failed = expectation(description: "Write failure reaches caller")
        writer.save(SavedState()) { result in
            if case .success = result { XCTFail("Expected write failure") }
            failed.fulfill()
        }
        wait(for: [failed], timeout: 5)
        try FileManager.default.removeItem(at: blocker)
        let recovered = expectation(description: "Writer recovers")
        writer.save(SavedState()) { result in
            if case .failure(let error) = result { XCTFail("Recovery failed: \(error)") }
            recovered.fulfill()
        }
        wait(for: [recovered], timeout: 5)
        XCTAssertNoThrow(try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url)))
    }
}
