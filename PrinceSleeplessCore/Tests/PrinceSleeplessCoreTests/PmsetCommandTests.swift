import XCTest
@testable import PrinceSleeplessCore

final class PmsetCommandTests: XCTestCase {
    func testPmsetArguments() {
        XCTAssertEqual(PmsetCommand.executable, "/usr/bin/pmset")
        XCTAssertEqual(PmsetCommand.arguments(disableSleep: true), ["-a", "disablesleep", "1"])
        XCTAssertEqual(PmsetCommand.arguments(disableSleep: false), ["-a", "disablesleep", "0"])
    }
}
