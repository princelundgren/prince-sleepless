import XCTest
@testable import PrinceSleeplessCore

final class GuardBookTests: XCTestCase {
    func testRestoreOnlyAfterLastGuardLeaves() {
        var book = GuardBook()
        book.guardConnection(1)
        book.guardConnection(2)

        XCTAssertFalse(book.release(1))
        XCTAssertFalse(book.isEmpty)
        XCTAssertTrue(book.release(2))
        XCTAssertTrue(book.isEmpty)
        XCTAssertFalse(book.release(3))
    }

    func testGuardingOneConnectionTwiceIsOneGuard() {
        var book = GuardBook()
        book.guardConnection(1)
        book.guardConnection(1)

        XCTAssertTrue(book.release(1))
        XCTAssertFalse(book.release(1))
    }
}
