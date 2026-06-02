import Foundation

public enum StatusFileStore {
    public static let appSupportDirectoryName = "ClaudeCodeStatusLight"
    public static let statusFileName = "status.json"

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

    public static func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
    }

    public static func read() throws -> StatusPayload? {
        let url = statusFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StatusPayload.self, from: data)
    }

    public static func write(_ payload: StatusPayload) throws {
        try ensureDirectoryExists()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: statusFileURL, options: .atomic)
    }

    public static func reset() throws {
        try write(StatusPayload(state: .idle))
    }
}
