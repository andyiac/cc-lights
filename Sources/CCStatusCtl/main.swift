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

func resolvedSessionID(from parsed: ParsedCommand) -> String {
    if let sessionID = parsed.sessionID, !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return sessionID
    }

    if let sessionID = firstEnvironmentValue(for: [
        "CLAUDE_SESSION_ID",
        "CLAUDE_CODE_SESSION_ID"
    ]) {
        return sessionID
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

do {
    let parsed = try parse(arguments: Array(CommandLine.arguments.dropFirst()))

    switch parsed.command {
    case "idle", "offline", "working", "waiting", "error":
        guard let state = StatusState(rawValue: parsed.command) else {
            throw CommandError.unknownCommand(parsed.command)
        }

        let payload = StatusPayload(
            state: state,
            message: parsed.message,
            taskName: parsed.taskName,
            sessionID: resolvedSessionID(from: parsed),
            sessionTitle: parsed.sessionTitle,
            workingDirectory: resolvedWorkingDirectory(from: parsed),
            terminalBundleIdentifier: resolvedTerminalBundleIdentifier(from: parsed),
            terminalTTY: resolvedTerminalTTY(from: parsed)
        )
        try StatusFileStore.write(payload)
        print("已更新为：\(state.displayName)（\(payload.displayTitle)）")
    case "remove":
        let sessionID = resolvedSessionID(from: parsed)
        let removed = try StatusFileStore.removeSession(sessionID)
        print(removed ? "已移除 session：\(sessionID)" : "session 不存在：\(sessionID)")
    case "reset":
        try StatusFileStore.reset(
            sessionID: resolvedSessionID(from: parsed),
            sessionTitle: parsed.sessionTitle,
            workingDirectory: resolvedWorkingDirectory(from: parsed),
            terminalBundleIdentifier: resolvedTerminalBundleIdentifier(from: parsed),
            terminalTTY: resolvedTerminalTTY(from: parsed)
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
