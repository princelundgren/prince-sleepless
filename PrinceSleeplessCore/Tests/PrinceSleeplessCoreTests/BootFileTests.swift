import XCTest
@testable import PrinceSleeplessCore

final class BootFileTests: XCTestCase {
    private var root: URL!
    private var bootFile: BootFile!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "BootFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        bootFile = BootFile(directory: root.appending(path: "PrinceSleepless", directoryHint: .isDirectory))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func mode(of url: URL) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    func testMissingDirectoryReadsMissing() {
        XCTAssertEqual(bootFile.read(), .missing)
    }

    func testGarbageReadsUnreadable() throws {
        try FileManager.default.createDirectory(at: bootFile.directory, withIntermediateDirectories: false)
        try Data("not a uuid".utf8).write(to: bootFile.file)

        XCTAssertEqual(bootFile.read(), .unreadable)
    }

    func testStoredSessionReadsBack() throws {
        let session = UUID()

        try bootFile.store(session)

        XCTAssertEqual(bootFile.read(), .session(session))
    }

    func testStoreLeavesDirectory0700AndFile0600() throws {
        try bootFile.store(UUID())

        XCTAssertEqual(try mode(of: bootFile.directory), 0o700)
        XCTAssertEqual(try mode(of: bootFile.file), 0o600)
    }

    func testStoreTightensAnExistingDirectoryTo0700() throws {
        try FileManager.default.createDirectory(at: bootFile.directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])

        try bootFile.store(UUID())

        XCTAssertEqual(try mode(of: bootFile.directory), 0o700)
    }
}
