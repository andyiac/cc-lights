import XCTest
@testable import StatusLightCore

final class StatusPayloadTests: XCTestCase {
    func testStatusStateDisplayNamesMatchPRDStates() {
        XCTAssertEqual(StatusState.offline.displayName, "无会话")
        XCTAssertEqual(StatusState.working.displayName, "工作中")
        XCTAssertEqual(StatusState.waiting.displayName, "等待决策")
        XCTAssertEqual(StatusState.idle.displayName, "空闲/完成")
        XCTAssertEqual(StatusState.error.displayName, "错误")
    }

    func testPayloadRoundTripsThroughJSON() throws {
        let payload = StatusPayload(
            state: .waiting,
            message: "需要确认",
            taskName: "重构 API",
            sessionID: "session-123",
            sessionTitle: "API 重构",
            workingDirectory: "/tmp/api",
            terminalBundleIdentifier: "com.googlecode.iterm2",
            terminalTTY: "/dev/ttys001",
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatusPayload.self, from: data)

        XCTAssertEqual(decoded, payload)
    }

    func testLegacyPayloadDecodesWithDefaultSessionID() throws {
        let json = """
        {
          "state": "idle",
          "updatedAt": "2026-06-02T10:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatusPayload.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.sessionID, StatusFileStore.defaultSessionID)
        XCTAssertEqual(decoded.state, .idle)
    }

    func testDecodingUsesDirectorySessionIDAsWorkingDirectory() throws {
        let directory = NSTemporaryDirectory()
        let json = """
        {
          "sessionID": "\(directory)",
          "state": "idle",
          "updatedAt": "2026-06-02T10:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StatusPayload.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.workingDirectory, directory)
    }

    func testRemoveSessionDeletesFileAndIsIdempotent() throws {
        let sessionID = "test-remove-\(UUID().uuidString)"
        let url = StatusFileStore.sessionFileURL(for: sessionID)
        defer { try? FileManager.default.removeItem(at: url) }

        try StatusFileStore.write(StatusPayload(state: .working, sessionID: sessionID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        XCTAssertTrue(try StatusFileStore.removeSession(sessionID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        // 再次移除应静默返回 false（幂等）
        XCTAssertFalse(try StatusFileStore.removeSession(sessionID))
    }

    func testAggregateUsesHighestPriorityState() {
        let payloads = [
            StatusPayload(state: .idle, sessionID: "idle"),
            StatusPayload(state: .working, sessionID: "working"),
            StatusPayload(state: .waiting, sessionID: "waiting"),
            StatusPayload(state: .error, sessionID: "error")
        ]

        XCTAssertEqual(StatusFileStore.aggregate(payloads).state, .error)
        XCTAssertEqual(StatusFileStore.aggregate([]).state, .offline)
    }
}
