import XCTest
@testable import PrinceSleeplessCore

final class BootCheckTests: XCTestCase {
    private let current = UUID()

    func testBootCheck() {
        XCTAssertFalse(BootCheck.isNewBoot(stored: .missing, current: current), "a missing file is a registration")
        XCTAssertTrue(BootCheck.isNewBoot(stored: .unreadable, current: current))
        XCTAssertFalse(BootCheck.isNewBoot(stored: .session(current), current: current))
        XCTAssertTrue(BootCheck.isNewBoot(stored: .session(UUID()), current: current))
    }
}
