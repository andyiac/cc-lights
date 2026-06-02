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
            return "Claude Code 工作中..."
        case .waiting:
            return "等待你的决策 — 点击查看"
        case .idle:
            return "空闲 — 无任务"
        case .error:
            return "发生错误 — 点击查看"
        }
    }
}
