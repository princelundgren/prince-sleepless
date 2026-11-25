import Foundation

/// The file holding the last `kern.bootsessionuuid` the helper saw, as its UUID string, in a
/// directory only its owner can enter. The helper, running as root, uses `standard`.
public struct BootFile: Sendable {
    /// `/Library/Application Support/PrinceSleepless/boot-session`.
    public static let standard = BootFile(directory: URL(fileURLWithPath: "/Library/Application Support/PrinceSleepless", isDirectory: true))

    public let directory: URL

    /// `boot-session` inside `directory`.
    public var file: URL { directory.appending(path: "boot-session", directoryHint: .notDirectory) }

    public init(directory: URL) {
        self.directory = directory
    }

    /// `.missing` when no file exists, `.unreadable` when it can't be read or isn't a UUID.
    public func read() -> StoredBoot {
        let contents: Data
        do {
            contents = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            return .missing
        } catch {
            return .unreadable
        }
        let text = String(decoding: contents, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return UUID(uuidString: text).map(StoredBoot.session) ?? .unreadable
    }

    /// Writes `session` atomically, creating the directory if needed and leaving it 0700 and the
    /// file 0600. Throws the file system's error; the file then keeps its last value.
    public func store(_ session: UUID) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try Data(session.uuidString.utf8).write(to: file, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
