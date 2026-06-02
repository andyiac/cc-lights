import XCTest
@testable import StatusLightCore

final class StatusPayloadTests: XCTestCase {
    func testStatusStateDisplayNamesMatchPRDStates() {
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
}
