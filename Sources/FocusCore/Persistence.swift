import Foundation

public final class LocalRepository {
    public let directory: URL
    public var stateURL: URL { directory.appendingPathComponent("state.json") }
    public var backupURL: URL { directory.appendingPathComponent("previous-good.json") }
    public init(directory: URL) { self.directory = directory }
    public static func encode(_ state: AppState) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(state.validated())
    }
    public static func decode(_ data: Data) throws -> AppState {
        guard data.count <= 100_000_000 else { throw DataError.invalid("Die Sicherungsdatei ist zu groß.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppState.self, from: data).validated()
    }
    public func load() throws -> AppState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return AppState() }
        return try Self.decode(Data(contentsOf: stateURL))
    }
    public func save(_ state: AppState) throws {
        let data = try Self.encode(state)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: stateURL.path) {
            let previous = try Data(contentsOf: stateURL)
            _ = try Self.decode(previous) // Never overwrite unreadable originals.
            try previous.write(to: backupURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        }
        try data.write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }
    public func restore(_ replacement: AppState) throws {
        let data = try Self.encode(replacement)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: stateURL.path) {
            let safe = directory.appendingPathComponent("before-restore-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: stateURL, to: safe)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: safe.path)
        }
        try data.write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }
}
