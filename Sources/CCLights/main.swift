import Foundation
import StatusLightCore

/// codex (OpenAI) hook 通过 stdin 传入的 JSON。codex hooks 与 Claude Code 不同：
/// 上下文全部在 stdin JSON 里（无 CLAUDE_* 环境变量），关键字段见下。
struct CodexHookInput {
    var sessionID: String?
    var cwd: String?
    var hookEventName: String?
}

/// 读取挂在 stdin 上的 codex hook JSON；stdin 是交互终端时返回 nil（正常 CLI 用法）。
func readCodexHookInputFromStdin() -> CodexHookInput? {
    guard isatty(STDIN_FILENO) == 0 else {
        return nil
    }

    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard !data.isEmpty,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    return CodexHookInput(
        sessionID: (json["session_id"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
        cwd: (json["cwd"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
        hookEventName: (json["hook_event_name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    )
}

enum CommandError: LocalizedError {
    case missingCommand
    case unknownCommand(String)
    case missingValue(String)

    var errorDescription: String? {
        switch self {
        case .missingCommand:
            return "缺少命令。"
        case .unknownCommand(let command):
            return "未知命令：\(command)"
        case .missingValue(let option):
            return "\(option) 缺少值。"
        }
    }
}

struct ParsedCommand {
    var command: String
    var message: String?
    var taskName: String?
    var sessionID: String?
    var sessionTitle: String?
    var workingDirectory: String?
    var terminalBundleIdentifier: String?
    var terminalTTY: String?
    var terminalPID: Int?
    var cmuxWorkspaceID: String?
    var cmuxSurfaceID: String?
    var cmuxSocketPath: String?
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

func parse(arguments: [String]) throws -> ParsedCommand {
    guard let command = arguments.first else {
        throw CommandError.missingCommand
    }

    var message: String?
    var taskName: String?
    var sessionID: String?
    var sessionTitle: String?
    var workingDirectory: String?
    var terminalBundleIdentifier: String?
    var terminalTTY: String?
    var terminalPID: Int?
    var cmuxWorkspaceID: String?
    var cmuxSurfaceID: String?
    var cmuxSocketPath: String?
    var index = 1

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--message", "-m":
            guard index + 1 < arguments.count else {
                throw CommandError.missingValue(argument)
            }
            message = arguments[index + 1]
            index += 2
        case "--task", "-t":
            guard index + 1 < arguments.count else {
                throw CommandError.missingValue(argument)
            }
            taskName = arguments[index + 1]
            index += 2
        case "--session", "-s":
            guard index + 1 < arguments.count else {
                throw CommandError.missingValue(argument)
            }
            sessionID = arguments[index + 1]
            index += 2
        case "--title":
            guard index + 1 < arguments.count else {
                throw CommandError.missingValue(argument)
            }
            sessionTitle = arguments[index + 1]
            index += 2
        case "--cwd":
            guard index + 1 < arguments.count else {
                throw CommandError.missingValue(argument)
            }
            workingDirectory = arguments[index + 1]
            index += 2
        case "--terminal-bundle":
            guard index + 1 < arguments.count else {
                throw CommandError.missingValue(argument)
            }
            terminalBundleIdentifier = arguments[index + 1]
            index += 2
        case "--tty":
            guard index + 1 < arguments.count else {
                throw CommandError.missingValue(argument)
            }
            terminalTTY = arguments[index + 1]
            index += 2
        case "--terminal-pid":
            guard index + 1 < arguments.count else {
                throw CommandError.missingValue(argument)
            }
            terminalPID = Int(arguments[index + 1])
            index += 2
        case "--cmux-workspace":
            guard index + 1 < arguments.count else {
                throw CommandError.missingValue(argument)
            }
            cmuxWorkspaceID = arguments[index + 1]
            index += 2
        case "--cmux-surface":
            guard index + 1 < arguments.count else {
                throw CommandError.missingValue(argument)
            }
            cmuxSurfaceID = arguments[index + 1]
            index += 2
        case "--cmux-socket":
            guard index + 1 < arguments.count else {
                throw CommandError.missingValue(argument)
            }
            cmuxSocketPath = arguments[index + 1]
            index += 2
        default:
            throw CommandError.unknownCommand(argument)
        }
    }

    return ParsedCommand(
        command: command,
        message: message,
        taskName: taskName,
        sessionID: sessionID,
        sessionTitle: sessionTitle,
        workingDirectory: workingDirectory,
        terminalBundleIdentifier: terminalBundleIdentifier,
        terminalTTY: terminalTTY,
        terminalPID: terminalPID,
        cmuxWorkspaceID: cmuxWorkspaceID,
        cmuxSurfaceID: cmuxSurfaceID,
        cmuxSocketPath: cmuxSocketPath
    )
}

func usage() -> String {
    """
    用法:
      cc-lights idle [--session ID] [--cwd 路径] [--title 名称] [--terminal-bundle ID] [--tty TTY] [--terminal-pid PID] [--cmux-workspace ID] [--cmux-surface ID] [--cmux-socket 路径] [--message 文本] [--task 任务名]
      cc-lights offline [--session ID] [--cwd 路径] [--title 名称] [--terminal-bundle ID] [--tty TTY] [--terminal-pid PID] [--cmux-workspace ID] [--cmux-surface ID] [--cmux-socket 路径] [--message 文本] [--task 任务名]
      cc-lights working [--session ID] [--cwd 路径] [--title 名称] [--terminal-bundle ID] [--tty TTY] [--terminal-pid PID] [--cmux-workspace ID] [--cmux-surface ID] [--cmux-socket 路径] [--message 文本] [--task 任务名]
      cc-lights waiting [--session ID] [--cwd 路径] [--title 名称] [--terminal-bundle ID] [--tty TTY] [--terminal-pid PID] [--cmux-workspace ID] [--cmux-surface ID] [--cmux-socket 路径] [--message 文本] [--task 任务名]
      cc-lights error [--session ID] [--cwd 路径] [--title 名称] [--terminal-bundle ID] [--tty TTY] [--terminal-pid PID] [--cmux-workspace ID] [--cmux-surface ID] [--cmux-socket 路径] [--message 文本] [--task 任务名]
      cc-lights reset [--session ID] [--cwd 路径] [--title 名称] [--terminal-bundle ID] [--tty TTY] [--terminal-pid PID] [--cmux-workspace ID] [--cmux-surface ID] [--cmux-socket 路径]
      cc-lights remove [--session ID]
      cc-lights show [--session ID]
      cc-lights path [--session ID]
      cc-lights hook <state> [--message 文本]

     状态 state（来自 codex hook 事件）:
      hook working    # SessionStart / UserPromptSubmit / PreToolUse / PostToolUse
      hook waiting    # PermissionRequest
      hook idle       # Stop
      hook error      # StopFailure
      hook remove     # SessionEnd
     说明: hook 模式的 stdin 必须是 codex 传入的 JSON（含 session_id / cwd）。
     无 stdin 时回退到普通参数解析（--session / --cwd）。
    """
}

func printPayload(_ payload: StatusPayload) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(payload)
    if let json = String(data: data, encoding: .utf8) {
        print(json)
    }
}

func printPayloads(_ payloads: [StatusPayload]) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(payloads)
    if let json = String(data: data, encoding: .utf8) {
        print(json)
    }
}

func firstEnvironmentValue(for keys: [String]) -> String? {
    let environment = ProcessInfo.processInfo.environment
    for key in keys {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            continue
        }
        return value
    }
    return nil
}

func resolvedWorkingDirectory(from parsed: ParsedCommand) -> String {
    if let workingDirectory = parsed.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
       !workingDirectory.isEmpty {
        return workingDirectory
    }

    if let workingDirectory = firstEnvironmentValue(for: [
        "CLAUDE_PROJECT_DIR",
        "CLAUDE_WORKING_DIRECTORY",
        "CLAUDE_CWD",
        "PWD"
    ]) {
        return workingDirectory
    }

    return FileManager.default.currentDirectoryPath
}

func resolvedSessionID(from parsed: ParsedCommand, terminalTTY: String? = nil) -> String {
    if let sessionID = parsed.sessionID, !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return sessionID
    }

    if let sessionID = firstEnvironmentValue(for: [
        "CLAUDE_SESSION_ID",
        "CLAUDE_CODE_SESSION_ID"
    ]) {
        return sessionID
    }

    if let terminalTTY, !terminalTTY.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return terminalTTY
    }

    return resolvedWorkingDirectory(from: parsed)
}

func resolvedTerminalBundleIdentifier(from parsed: ParsedCommand) -> String? {
    if let terminalBundleIdentifier = parsed.terminalBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
       !terminalBundleIdentifier.isEmpty {
        return terminalBundleIdentifier
    }

    if let cmuxBundleID = firstEnvironmentValue(for: ["CMUX_BUNDLE_ID"]) {
        return cmuxBundleID
    }

    if resolvedCmuxWorkspaceID(from: parsed) != nil || resolvedCmuxSurfaceID(from: parsed) != nil {
        return "com.cmuxterm.app"
    }

    guard let termProgram = firstEnvironmentValue(for: ["TERM_PROGRAM"]) else {
        return nil
    }

    switch termProgram {
    case "iTerm.app":
        return "com.googlecode.iterm2"
    case "Apple_Terminal":
        return "com.apple.Terminal"
    case "vscode":
        return "com.microsoft.VSCode"
    case "ghostty":
        return "com.mitchellh.ghostty"
    default:
        return nil
    }
}

func resolvedTerminalTTY(from parsed: ParsedCommand) -> String? {
    if let terminalTTY = parsed.terminalTTY?.trimmingCharacters(in: .whitespacesAndNewlines),
       !terminalTTY.isEmpty {
        return terminalTTY
    }

    if let terminalTTY = firstEnvironmentValue(for: ["TTY", "SSH_TTY"]) {
        return terminalTTY
    }

    return currentTTY()
}

/// 宿主终端模拟器进程的 PID。多个副本共用同一 bundle id（如复制出的多个 Ghostty.app）时，
/// 只有进程 PID 能区分具体实例，App 侧据此精确激活对应窗口。
func resolvedTerminalPID(from parsed: ParsedCommand) -> Int? {
    if let terminalPID = parsed.terminalPID {
        return terminalPID
    }

    return terminalEmulatorPIDFromProcessTree().map(Int.init)
}

func resolvedCmuxWorkspaceID(from parsed: ParsedCommand) -> String? {
    if let cmuxWorkspaceID = parsed.cmuxWorkspaceID?.trimmingCharacters(in: .whitespacesAndNewlines),
       !cmuxWorkspaceID.isEmpty {
        return cmuxWorkspaceID
    }

    return firstEnvironmentValue(for: ["CMUX_WORKSPACE_ID", "CMUX_TAB_ID"])
}

func resolvedCmuxSurfaceID(from parsed: ParsedCommand) -> String? {
    if let cmuxSurfaceID = parsed.cmuxSurfaceID?.trimmingCharacters(in: .whitespacesAndNewlines),
       !cmuxSurfaceID.isEmpty {
        return cmuxSurfaceID
    }

    return firstEnvironmentValue(for: ["CMUX_SURFACE_ID", "CMUX_PANEL_ID"])
}

func resolvedCmuxSocketPath(from parsed: ParsedCommand) -> String? {
    if let cmuxSocketPath = parsed.cmuxSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines),
       !cmuxSocketPath.isEmpty {
        return cmuxSocketPath
    }

    return firstEnvironmentValue(for: ["CMUX_SOCKET_PATH"])
}

func currentTTY() -> String? {
    // 1) 交互式终端里直接 tty 有效。
    if let tty = ttyFromCommand(), tty != "not a tty" {
        return tty
    }

    // 2) hook 子进程的 stdin 是管道，tty 失效；控制终端会被进程链继承。
    //    沿父进程链向上找第一个真实 tty（中间可能有脱离终端的 shell 层）。
    return ttyFromProcessTree()
}

private func ttyFromCommand() -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tty")
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }

    guard process.terminationStatus == 0 else {
        return nil
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !output.isEmpty,
        output != "not a tty" else {
        return nil
    }

    return output
}

private func ttyFromProcessTree() -> String? {
    var pid = getppid()
    // 最多向上 8 层，避免极端情况下的无限循环。
    for _ in 0..<8 {
        guard pid > 1 else { break }
        guard let (ppid, tty) = psInfo(pid: pid) else { break }
        if let tty {
            // ps 输出形如 "ttys003"，AppleScript 里终端的 tty 是 "/dev/ttys003"。
            return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        }
        guard let ppid, ppid != pid else { break }
        pid = ppid
    }
    return nil
}

/// 沿父进程链向上定位 GUI 终端模拟器进程（如 Ghostty）的 pid。
/// 进程链形如 cc-lights → [脱离终端的 shell] → claude(ttysNNN) → login(ttysNNN) → ghostty(无 tty)。
/// 终端模拟器是「带 tty 的进程区段」正上方那个失去控制终端的祖先，即最顶层 tty 进程的父进程。
/// 注意不能取「第一个无 tty 的祖先」：hook 常经由脱离终端的中间 shell 启动，那层也无 tty 但并非模拟器。
private func terminalEmulatorPIDFromProcessTree() -> Int32? {
    var pid = getppid()
    var sawTTY = false
    // 最多向上 16 层，覆盖 shell/login 等中间层，同时避免极端情况下的无限循环。
    for _ in 0..<16 {
        guard pid > 1 else { break }
        guard let (ppid, tty) = psInfo(pid: pid) else { break }
        if tty != nil {
            sawTTY = true
        } else if sawTTY {
            // 已越过 tty 进程区段后遇到的第一个无 tty 祖先，即终端模拟器进程。
            return pid
        }
        // 尚未见到 tty 就遇到的无 tty 祖先（如 hook 的中间 shell）跳过，继续向上找。
        guard let ppid, ppid != pid else { break }
        pid = ppid
    }
    return nil
}

/// 读取进程的父 pid 与控制终端；tty 为 "??"/"?"（无控制终端）时返回 nil。
private func psInfo(pid: Int32) -> (ppid: Int32?, tty: String?)? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-o", "ppid=,tty=", "-p", String(pid)]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }

    guard process.terminationStatus == 0 else {
        return nil
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let line = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !line.isEmpty else {
        return nil
    }

    let fields = line.split(separator: " ", omittingEmptySubsequences: true)
    let ppid = fields.first.flatMap { Int32($0) }
    let ttyField = fields.count >= 2 ? String(fields[1]) : nil
    let tty = (ttyField == "??" || ttyField == "?" || ttyField?.isEmpty == true) ? nil : ttyField
    return (ppid, tty)
}

do {
    var arguments = Array(CommandLine.arguments.dropFirst())
    let isHookMode = arguments.first == "hook"
    if isHookMode {
        arguments.removeFirst()
    }

    let parsed = try parse(arguments: arguments)
    let codexHook = isHookMode ? readCodexHookInputFromStdin() : nil

    // codex 上下文全部走 stdin JSON：session_id / cwd 合并进解析结果，
    // 命令行显式传入的 --session / --cwd 优先级更高。
    var effective = parsed
    if let codexHook {
        if effective.sessionID == nil, let sessionID = codexHook.sessionID {
            effective.sessionID = sessionID
        }
        if effective.workingDirectory == nil, let cwd = codexHook.cwd {
            effective.workingDirectory = cwd
        }
    }

    // hook 模式静默：codex 把 stdout 纯文本当作额外上下文注入（污染对话），
    // Stop 事件则必须输出合法 JSON（`{"continue":true}`）。
    func emit(_ message: String) {
        if !isHookMode {
            print(message)
        }
    }

    switch effective.command {
    case "idle", "offline", "working", "waiting", "error":
        guard let state = StatusState(rawValue: effective.command) else {
            throw CommandError.unknownCommand(effective.command)
        }

        let terminalTTY = resolvedTerminalTTY(from: effective)
        let payload = StatusPayload(
            state: state,
            message: effective.message,
            taskName: effective.taskName,
            sessionID: resolvedSessionID(from: effective, terminalTTY: terminalTTY),
            sessionTitle: effective.sessionTitle,
            workingDirectory: resolvedWorkingDirectory(from: effective),
            terminalBundleIdentifier: resolvedTerminalBundleIdentifier(from: effective),
            terminalTTY: terminalTTY,
            terminalPID: resolvedTerminalPID(from: effective),
            cmuxWorkspaceID: resolvedCmuxWorkspaceID(from: effective),
            cmuxSurfaceID: resolvedCmuxSurfaceID(from: effective),
            cmuxSocketPath: resolvedCmuxSocketPath(from: effective)
        )
        try StatusFileStore.write(payload)
        emit("已更新为：\(state.displayName)（\(payload.displayTitle)）")
        if isHookMode, codexHook?.hookEventName == "Stop" {
            print(#"{"continue":true}"#)
        }
    case "remove":
        let sessionID = resolvedSessionID(from: effective, terminalTTY: resolvedTerminalTTY(from: effective))
        let removed = try StatusFileStore.removeSession(sessionID)
        emit(removed ? "已移除 session：\(sessionID)" : "session 不存在：\(sessionID)")
    case "reset":
        let terminalTTY = resolvedTerminalTTY(from: effective)
        try StatusFileStore.reset(
            sessionID: resolvedSessionID(from: effective, terminalTTY: terminalTTY),
            sessionTitle: effective.sessionTitle,
            workingDirectory: resolvedWorkingDirectory(from: effective),
            terminalBundleIdentifier: resolvedTerminalBundleIdentifier(from: effective),
            terminalTTY: terminalTTY,
            terminalPID: resolvedTerminalPID(from: effective),
            cmuxWorkspaceID: resolvedCmuxWorkspaceID(from: effective),
            cmuxSurfaceID: resolvedCmuxSurfaceID(from: effective),
            cmuxSocketPath: resolvedCmuxSocketPath(from: effective)
        )
        emit("已重置为：\(StatusState.idle.displayName)")
    case "show":
        if let sessionID = effective.sessionID {
            if let payload = try StatusFileStore.readSession(sessionID) {
                try printPayload(payload)
            } else {
                emit("尚未写入此 session 状态。")
            }
        } else {
            let payloads = try StatusFileStore.readAllSessions()
            if payloads.isEmpty {
                emit("尚未写入状态。")
            } else {
                try printPayloads(payloads)
            }
        }
    case "path":
        if let sessionID = effective.sessionID {
            print(StatusFileStore.sessionFileURL(for: sessionID).path)
        } else {
            print(StatusFileStore.sessionsDirectoryURL.path)
        }
    case "help", "--help", "-h":
        print(usage())
    default:
        throw CommandError.unknownCommand(effective.command)
    }
} catch {
    fputs("\(error.localizedDescription)\n\n\(usage())\n", stderr)
    exit(64)
}
