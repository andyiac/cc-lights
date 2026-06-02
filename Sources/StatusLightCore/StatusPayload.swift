import Foundation

public struct StatusPayload: Codable, Equatable {
    public var state: StatusState
    public var message: String?
    public var taskName: String?
    public var updatedAt: Date

    public init(
        state: StatusState,
        message: String? = nil,
        taskName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.state = state
        self.message = message
        self.taskName = taskName
        self.updatedAt = updatedAt
    }
}
