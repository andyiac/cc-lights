import Foundation
import StatusLightCore

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
        terminalTTY: terminalTTY
    )
}

func usage() -> String {
    """
    用法:
      cc-statusctl idle [--session ID] [--cwd 路径] [--title 名称] [--terminal-bundle ID] [--tty TTY] [--message 文本] [--task 任务名]
      cc-statusctl offline [--session ID] [--cwd 路径] [--title 名称] [--terminal-bundle ID] [--tty TTY] [--message 文本] [--task 任务名]
      cc-statusctl working [--session ID] [--cwd 路径] [--title 名称] [--terminal-bundle ID] [--tty TTY] [--message 文本] [--task 任务名]
      cc-statusctl waiting [--session ID] [--cwd 路径] [--title 名称] [--terminal-bundle ID] [--tty TTY] [--message 文本] [--task 任务名]
      cc-statusctl error [--session ID] [--cwd 路径] [--title 名称] [--terminal-bundle ID] [--tty TTY] [--message 文本] [--task 任务名]
      cc-statusctl reset [--session ID] [--cwd 路径] [--title 名称] [--terminal-bundle ID] [--tty TTY]
      cc-statusctl remove [--session ID]
      cc-statusctl show [--session ID]
      cc-statusctl path [--session ID]
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
    let parsed = try parse(arguments: Array(CommandLine.arguments.dropFirst()))

    switch parsed.command {
    case "idle", "offline", "working", "waiting", "error":
        guard let state = StatusState(rawValue: parsed.command) else {
            throw CommandError.unknownCommand(parsed.command)
        }

        let terminalTTY = resolvedTerminalTTY(from: parsed)
        let payload = StatusPayload(
            state: state,
            message: parsed.message,
            taskName: parsed.taskName,
            sessionID: resolvedSessionID(from: parsed, terminalTTY: terminalTTY),
            sessionTitle: parsed.sessionTitle,
            workingDirectory: resolvedWorkingDirectory(from: parsed),
            terminalBundleIdentifier: resolvedTerminalBundleIdentifier(from: parsed),
            terminalTTY: terminalTTY
        )
        try StatusFileStore.write(payload)
        print("已更新为：\(state.displayName)（\(payload.displayTitle)）")
    case "remove":
        let sessionID = resolvedSessionID(from: parsed, terminalTTY: resolvedTerminalTTY(from: parsed))
        let removed = try StatusFileStore.removeSession(sessionID)
        print(removed ? "已移除 session：\(sessionID)" : "session 不存在：\(sessionID)")
    case "reset":
        let terminalTTY = resolvedTerminalTTY(from: parsed)
        try StatusFileStore.reset(
            sessionID: resolvedSessionID(from: parsed, terminalTTY: terminalTTY),
            sessionTitle: parsed.sessionTitle,
            workingDirectory: resolvedWorkingDirectory(from: parsed),
            terminalBundleIdentifier: resolvedTerminalBundleIdentifier(from: parsed),
            terminalTTY: terminalTTY
        )
        print("已重置为：\(StatusState.idle.displayName)")
    case "show":
        if let sessionID = parsed.sessionID {
            if let payload = try StatusFileStore.readSession(sessionID) {
                try printPayload(payload)
            } else {
                print("尚未写入此 session 状态。")
            }
        } else {
            let payloads = try StatusFileStore.readAllSessions()
            if payloads.isEmpty {
                print("尚未写入状态。")
            } else {
                try printPayloads(payloads)
            }
        }
    case "path":
        if let sessionID = parsed.sessionID {
            print(StatusFileStore.sessionFileURL(for: sessionID).path)
        } else {
            print(StatusFileStore.sessionsDirectoryURL.path)
        }
    case "help", "--help", "-h":
        print(usage())
    default:
        throw CommandError.unknownCommand(parsed.command)
    }
} catch {
    fputs("\(error.localizedDescription)\n\n\(usage())\n", stderr)
    exit(64)
}
