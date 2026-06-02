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
}

func parse(arguments: [String]) throws -> ParsedCommand {
    guard let command = arguments.first else {
        throw CommandError.missingCommand
    }

    var message: String?
    var taskName: String?
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
        default:
            throw CommandError.unknownCommand(argument)
        }
    }

    return ParsedCommand(command: command, message: message, taskName: taskName)
}

func usage() -> String {
    """
    用法:
      cc-statusctl idle [--message 文本] [--task 任务名]
      cc-statusctl offline [--message 文本] [--task 任务名]
      cc-statusctl working [--message 文本] [--task 任务名]
      cc-statusctl waiting [--message 文本] [--task 任务名]
      cc-statusctl error [--message 文本] [--task 任务名]
      cc-statusctl reset
      cc-statusctl show
      cc-statusctl path
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

do {
    let parsed = try parse(arguments: Array(CommandLine.arguments.dropFirst()))

    switch parsed.command {
    case "idle", "offline", "working", "waiting", "error":
        guard let state = StatusState(rawValue: parsed.command) else {
            throw CommandError.unknownCommand(parsed.command)
        }

        let payload = StatusPayload(state: state, message: parsed.message, taskName: parsed.taskName)
        try StatusFileStore.write(payload)
        print("已更新为：\(state.displayName)")
    case "reset":
        try StatusFileStore.reset()
        print("已重置为：\(StatusState.idle.displayName)")
    case "show":
        if let payload = try StatusFileStore.read() {
            try printPayload(payload)
        } else {
            print("尚未写入状态。")
        }
    case "path":
        print(StatusFileStore.statusFileURL.path)
    case "help", "--help", "-h":
        print(usage())
    default:
        throw CommandError.unknownCommand(parsed.command)
    }
} catch {
    fputs("\(error.localizedDescription)\n\n\(usage())\n", stderr)
    exit(64)
}
