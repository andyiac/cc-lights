import Foundation

public struct StatusPayload: Codable, Equatable {
    public var state: StatusState
    public var message: String?
    public var taskName: String?
    public var sessionID: String
    public var sessionTitle: String?
    public var workingDirectory: String?
    public var terminalBundleIdentifier: String?
    public var terminalTTY: String?
    /// 宿主终端模拟器进程的 PID。用于区分 bundle id 相同的多个副本（如复制出的多个 Ghostty.app）。
    public var terminalPID: Int?
    public var cmuxWorkspaceID: String?
    public var cmuxSurfaceID: String?
    public var cmuxSocketPath: String?
    public var updatedAt: Date

    public init(
        state: StatusState,
        message: String? = nil,
        taskName: String? = nil,
        sessionID: String = "default",
        sessionTitle: String? = nil,
        workingDirectory: String? = nil,
        terminalBundleIdentifier: String? = nil,
        terminalTTY: String? = nil,
        terminalPID: Int? = nil,
        cmuxWorkspaceID: String? = nil,
        cmuxSurfaceID: String? = nil,
        cmuxSocketPath: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.state = state
        self.message = message
        self.taskName = taskName
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.workingDirectory = workingDirectory
        self.terminalBundleIdentifier = terminalBundleIdentifier
        self.terminalTTY = terminalTTY
        self.terminalPID = terminalPID
        self.cmuxWorkspaceID = cmuxWorkspaceID
        self.cmuxSurfaceID = cmuxSurfaceID
        self.cmuxSocketPath = cmuxSocketPath
        self.updatedAt = updatedAt
    }

    public var displayTitle: String {
        if let sessionTitle, !sessionTitle.isEmpty {
            return sessionTitle
        }

        if let workingDirectory, !workingDirectory.isEmpty {
            return URL(fileURLWithPath: workingDirectory).lastPathComponent
        }

        return sessionID
    }

    enum CodingKeys: String, CodingKey {
        case state
        case message
        case taskName
        case sessionID
        case sessionTitle
        case workingDirectory
        case terminalBundleIdentifier
        case terminalTTY
        case terminalPID
        case cmuxWorkspaceID
        case cmuxSurfaceID
        case cmuxSocketPath
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(StatusState.self, forKey: .state)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        taskName = try container.decodeIfPresent(String.self, forKey: .taskName)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? "default"
        sessionTitle = try container.decodeIfPresent(String.self, forKey: .sessionTitle)
        let decodedWorkingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        if let decodedWorkingDirectory, !decodedWorkingDirectory.isEmpty {
            workingDirectory = decodedWorkingDirectory
        } else if FileManager.default.fileExists(atPath: sessionID) {
            workingDirectory = sessionID
        } else {
            workingDirectory = nil
        }
        terminalBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .terminalBundleIdentifier)
        terminalTTY = try container.decodeIfPresent(String.self, forKey: .terminalTTY)
        terminalPID = try container.decodeIfPresent(Int.self, forKey: .terminalPID)
        cmuxWorkspaceID = try container.decodeIfPresent(String.self, forKey: .cmuxWorkspaceID)
        cmuxSurfaceID = try container.decodeIfPresent(String.self, forKey: .cmuxSurfaceID)
        cmuxSocketPath = try container.decodeIfPresent(String.self, forKey: .cmuxSocketPath)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
