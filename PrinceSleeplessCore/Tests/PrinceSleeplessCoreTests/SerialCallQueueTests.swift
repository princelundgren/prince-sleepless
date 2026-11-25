import XCTest
@testable import PrinceSleeplessCore

final class SerialCallQueueTests: XCTestCase {
    func testFirstCallStartsAtOnce() {
        var queue = SerialCallQueue<String>()

        let ticket = queue.enqueue("keepAwake")

        XCTAssertEqual(ticket?.call, "keepAwake")
        XCTAssertEqual(queue.running?.call, "keepAwake")
    }

    func testCallWaitsWhileAnotherRuns() {
        var queue = SerialCallQueue<String>()
        _ = queue.enqueue("keepAwake")

        XCTAssertNil(queue.enqueue("allowSleep"))
        XCTAssertEqual(queue.running?.call, "keepAwake")
    }

    func testCompletingStartsTheWaitingCallsInOrder() throws {
        var queue = SerialCallQueue<String>()
        let first = try XCTUnwrap(queue.enqueue("a"))
        _ = queue.enqueue("b")
        _ = queue.enqueue("c")

        XCTAssertTrue(queue.complete(first))
        let second = try XCTUnwrap(queue.running)
        XCTAssertEqual(second.call, "b")
        XCTAssertTrue(queue.complete(second))
        let third = try XCTUnwrap(queue.running)
        XCTAssertEqual(third.call, "c")
        XCTAssertTrue(queue.complete(third))
        XCTAssertNil(queue.running)
    }

    func testSecondCompletionOfATicketChangesNothing() throws {
        var queue = SerialCallQueue<String>()
        let first = try XCTUnwrap(queue.enqueue("a"))
        _ = queue.enqueue("b")
        XCTAssertTrue(queue.complete(first))

        XCTAssertFalse(queue.complete(first))
        XCTAssertEqual(queue.running?.call, "b")
    }

    func testAnEqualCallIsAnotherTicket() throws {
        var queue = SerialCallQueue<String>()
        let first = try XCTUnwrap(queue.enqueue("keepAwake"))
        _ = queue.enqueue("keepAwake")
        XCTAssertTrue(queue.complete(first))

        XCTAssertFalse(queue.complete(first))
        XCTAssertNotNil(queue.running)
    }

    func testQueueStartsAgainOnceEmptied() throws {
        var queue = SerialCallQueue<String>()
        let first = try XCTUnwrap(queue.enqueue("a"))
        XCTAssertTrue(queue.complete(first))

        XCTAssertEqual(queue.enqueue("b")?.call, "b")
    }
}
