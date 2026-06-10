import Foundation

public enum StatusState: String, CaseIterable, Codable {
    case offline
    case working
    case waiting
    case idle
    case error

    public var displayName: String {
        switch self {
        case .offline:
            return "无会话"
        case .working:
            return "工作中"
        case .waiting:
            return "等待决策"
        case .idle:
            return "空闲/完成"
        case .error:
            return "错误"
        }
    }

    public var tooltip: String {
        switch self {
        case .offline:
            return "无 Claude Code 会话"
        case .working:
            return "Claude Code 正在工作，无需干预"
        case .waiting:
            return "等待你的决策 — 请点击查看"
        case .idle:
            return "空闲/完成 — 可发起新任务"
        case .error:
            return "API 错误 — 请点击查看"
        }
    }

    public var priority: Int {
        switch self {
        case .offline:
            return 0
        case .idle:
            return 1
        case .working:
            return 2
        case .waiting:
            return 3
        case .error:
            return 4
        }
    }
}
