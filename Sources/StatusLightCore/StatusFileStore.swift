import Foundation

public enum StatusFileStore {
    public static let appSupportDirectoryName = "ClaudeCodeStatusLight"
    public static let statusFileName = "status.json"
    public static let sessionsDirectoryName = "sessions"
    public static let defaultSessionID = "default"

    public static var applicationSupportDirectory: URL {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return baseDirectory.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
    }

    public static var statusFileURL: URL {
        applicationSupportDirectory.appendingPathComponent(statusFileName, isDirectory: false)
    }

    public static var sessionsDirectoryURL: URL {
        applicationSupportDirectory.appendingPathComponent(sessionsDirectoryName, isDirectory: true)
    }

    public static func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: sessionsDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    public static func read() throws -> StatusPayload? {
        if let payload = try readSession(defaultSessionID) {
            return payload
        }

        return try readLegacyStatusFile()
    }

    public static func readSession(_ sessionID: String) throws -> StatusPayload? {
        let url = sessionFileURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return try readPayload(at: url)
    }

    public static func readAllSessions() throws -> [StatusPayload] {
        try ensureDirectoryExists()

        let urls = try FileManager.default.contentsOfDirectory(
            at: sessionsDirectoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        var payloads = try urls.map(readPayload(at:))

        if payloads.isEmpty, let legacyPayload = try readLegacyStatusFile() {
            payloads.append(legacyPayload)
        }

        return stableSort(payloads)
    }

    /// 稳定排序：灯的顺序只由会话身份（终端 TTY，其次 sessionID）决定，
    /// 不随状态优先级、更新时间变化，保证菜单栏灯位固定不跳。
    public static func stableSort(_ payloads: [StatusPayload]) -> [StatusPayload] {
        payloads.sorted { stableSortKey($0) < stableSortKey($1) }
    }

    /// 会话的稳定排序键：有 TTY 用 TTY（/dev/ttys005 天然按终端号排），否则退回 sessionID。
    public static func stableSortKey(_ payload: StatusPayload) -> String {
        let tty = payload.terminalTTY ?? ""
        return tty.isEmpty ? payload.sessionID : tty
    }

    public static func write(_ payload: StatusPayload) throws {
        try ensureDirectoryExists()

        var payload = payload
        payload.sessionID = normalizedSessionID(payload.sessionID)

        // 合并旧值：未显式提供的终端定位信息保留下来，避免每次状态更新把它们清空，
        // 否则只在某个 hook（如 SessionStart）捕获一次的 TTY 会被随后的 working/idle 抹掉。
        if let existing = try? readPayload(at: sessionFileURL(for: payload.sessionID)) {
            payload.terminalTTY = payload.terminalTTY ?? existing.terminalTTY
            payload.terminalPID = payload.terminalPID ?? existing.terminalPID
            payload.terminalBundleIdentifier = payload.terminalBundleIdentifier ?? existing.terminalBundleIdentifier
            payload.cmuxWorkspaceID = payload.cmuxWorkspaceID ?? existing.cmuxWorkspaceID
            payload.cmuxSurfaceID = payload.cmuxSurfaceID ?? existing.cmuxSurfaceID
            payload.cmuxSocketPath = payload.cmuxSocketPath ?? existing.cmuxSocketPath
            payload.sessionTitle = payload.sessionTitle ?? existing.sessionTitle
            payload.workingDirectory = payload.workingDirectory ?? existing.workingDirectory
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: sessionFileURL(for: payload.sessionID), options: .atomic)
    }

    public static func reset() throws {
        try reset(sessionID: defaultSessionID)
    }

    public static func reset(
        sessionID: String,
        sessionTitle: String? = nil,
        workingDirectory: String? = nil,
        terminalBundleIdentifier: String? = nil,
        terminalTTY: String? = nil,
        terminalPID: Int? = nil,
        cmuxWorkspaceID: String? = nil,
        cmuxSurfaceID: String? = nil,
        cmuxSocketPath: String? = nil
    ) throws {
        try write(
            StatusPayload(
                state: .idle,
                sessionID: normalizedSessionID(sessionID),
                sessionTitle: sessionTitle,
                workingDirectory: workingDirectory,
                terminalBundleIdentifier: terminalBundleIdentifier,
                terminalTTY: terminalTTY,
                terminalPID: terminalPID,
                cmuxWorkspaceID: cmuxWorkspaceID,
                cmuxSurfaceID: cmuxSurfaceID,
                cmuxSocketPath: cmuxSocketPath
            )
        )
    }

    public static func aggregate(_ payloads: [StatusPayload]) -> StatusPayload {
        guard let payload = payloads.max(by: { lhs, rhs in
            if lhs.state.priority == rhs.state.priority {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.state.priority < rhs.state.priority
        }) else {
            return StatusPayload(state: .offline, sessionID: "aggregate", sessionTitle: "所有会话")
        }

        return payload
    }

    /// 清理超过 maxAge 未更新的 session 文件，兜底处理被强杀/崩溃、未触发 SessionEnd 的残留。
    /// 返回被删除的数量。
    @discardableResult
    public static func pruneStale(olderThan maxAge: TimeInterval) throws -> Int {
        let cutoff = Date().addingTimeInterval(-maxAge)
        var removed = try pruneFiles { $0.updatedAt < cutoff }

        if FileManager.default.fileExists(atPath: statusFileURL.path),
           let legacyPayload = try? readPayload(at: statusFileURL),
           legacyPayload.updatedAt < cutoff {
            try FileManager.default.removeItem(at: statusFileURL)
            removed += 1
        }

        return removed
    }

    /// 清理 idle 状态且超过 maxAge 未更新的 session 文件。
    /// idle 意味着会话已结束（Stop hook 已写入），正常几秒内就会被 SessionEnd 的 remove 删除；
    /// 存活超过 maxAge 的基本是 SessionEnd 未触发的残留（强杀/关终端/崩溃），由 App 周期性兜底清理。
    /// 返回被删除的数量。
    @discardableResult
    public static func pruneIdle(olderThan maxAge: TimeInterval) throws -> Int {
        let cutoff = Date().addingTimeInterval(-maxAge)
        return try pruneFiles { $0.state == .idle && $0.updatedAt < cutoff }
    }

    private static func pruneFiles(where shouldRemove: (StatusPayload) -> Bool) throws -> Int {
        try ensureDirectoryExists()

        let urls = try FileManager.default.contentsOfDirectory(
            at: sessionsDirectoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        var removed = 0
        for url in urls {
            guard let payload = try? readPayload(at: url), shouldRemove(payload) else {
                continue
            }
            try FileManager.default.removeItem(at: url)
            removed += 1
        }

        return removed
    }

    /// 删除指定 session 的状态文件。文件不存在时静默返回（幂等）。
    @discardableResult
    public static func removeSession(_ sessionID: String) throws -> Bool {
        let url = sessionFileURL(for: normalizedSessionID(sessionID))
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        try FileManager.default.removeItem(at: url)
        return true
    }

    /// 删除所有 session 状态文件与遗留 status.json，灯全部熄灭。返回被删除的数量。
    @discardableResult
    public static func removeAllSessions() throws -> Int {
        try ensureDirectoryExists()

        let urls = try FileManager.default.contentsOfDirectory(
            at: sessionsDirectoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        var removed = 0
        for url in urls {
            try FileManager.default.removeItem(at: url)
            removed += 1
        }

        if FileManager.default.fileExists(atPath: statusFileURL.path) {
            try FileManager.default.removeItem(at: statusFileURL)
            removed += 1
        }

        return removed
    }

    public static func sessionFileURL(for sessionID: String) -> URL {
        sessionsDirectoryURL.appendingPathComponent("\(safeFileName(for: sessionID)).json", isDirectory: false)
    }

    public static func normalizedSessionID(_ sessionID: String) -> String {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultSessionID : trimmed
    }

    private static func readLegacyStatusFile() throws -> StatusPayload? {
        guard FileManager.default.fileExists(atPath: statusFileURL.path) else {
            return nil
        }

        var payload = try readPayload(at: statusFileURL)
        payload.sessionID = normalizedSessionID(payload.sessionID)
        return payload
    }

    private static func readPayload(at url: URL) throws -> StatusPayload {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StatusPayload.self, from: data)
    }

    private static func safeFileName(for sessionID: String) -> String {
        let normalized = normalizedSessionID(sessionID)
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitizedScalars = normalized.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : "_"
        }
        let sanitized = String(sanitizedScalars).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        let prefix = String((sanitized.isEmpty ? defaultSessionID : sanitized).prefix(80))
        return "\(prefix)-\(stableHash(normalized))"
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
