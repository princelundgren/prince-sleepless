import XCTest
@testable import PrinceSleeplessCore

final class KeepAwakeDurationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testDurations() {
        let now = date("2026-11-24T19:00:00Z")
        XCTAssertEqual(KeepAwakeDuration.until(TimeOfDay(hour: 18, minute: 0)).endDate(from: now, calendar: calendar), date("2026-11-25T18:00:00Z"))
        XCTAssertEqual(KeepAwakeDuration.minutes(30).endDate(from: now, calendar: calendar), now.addingTimeInterval(1_800))
        XCTAssertNil(KeepAwakeDuration.indefinitely.endDate(from: now, calendar: calendar))
    }

    func testUntilLaterTodayEndsToday() {
        let now = date("2026-11-24T10:00:00Z")
        XCTAssertEqual(KeepAwakeDuration.until(TimeOfDay(hour: 18, minute: 0)).endDate(from: now, calendar: calendar), date("2026-11-24T18:00:00Z"))
    }

    func testUntilTheCurrentMinuteEndsTomorrow() {
        let now = date("2026-11-24T18:00:00Z")
        XCTAssertEqual(KeepAwakeDuration.until(TimeOfDay(hour: 18, minute: 0)).endDate(from: now, calendar: calendar), date("2026-11-25T18:00:00Z"))
    }

    func testUntilASkippedTimeEndsAtTheFirstInstantAfterTheGap() {
        var stockholm = Calendar(identifier: .gregorian)
        stockholm.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let now = date("2026-03-28T20:00:00Z")
        // Clocks jump 02:00 to 03:00 on 2026-03-29, so 02:30 never happens; 03:00 CEST is 01:00 UTC.
        XCTAssertEqual(KeepAwakeDuration.until(TimeOfDay(hour: 2, minute: 30)).endDate(from: now, calendar: stockholm), date("2026-03-29T01:00:00Z"))
    }
}
