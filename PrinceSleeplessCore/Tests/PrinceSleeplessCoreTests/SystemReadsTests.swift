import XCTest
@testable import PrinceSleeplessCore

/// These read the Mac running the tests; they only read.
final class SystemReadsTests: XCTestCase {
    func testSleepFlagReads() {
        XCTAssertNotNil(SleepFlagReader.read())
    }

    func testBootSessionReadsTheSameWithinABoot() throws {
        let first = try XCTUnwrap(BootSession.current())
        XCTAssertEqual(BootSession.current(), first)
    }
}
