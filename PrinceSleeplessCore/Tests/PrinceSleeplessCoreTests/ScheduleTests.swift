import XCTest
@testable import PrinceSleeplessCore

final class ScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }

    private let everyDay: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    private let mondayToFriday: Set<Int> = [2, 3, 4, 5, 6]

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func window(_ start: TimeOfDay, _ end: TimeOfDay, weekdays: Set<Int>) -> ScheduleWindow {
        ScheduleWindow(start: start, end: end, weekdays: weekdays, mode: .automatic)
    }

    func testNextBoundaryInsideWindowIsItsEnd() {
        let schedule = window(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 18, minute: 0), weekdays: mondayToFriday)
        let mondayTen = date("2026-11-23T10:00:00+01:00")

        let boundary = schedule.nextBoundary(after: mondayTen, calendar: calendar)

        XCTAssertEqual(boundary?.kind, .end)
        XCTAssertEqual(boundary?.date, date("2026-11-23T18:00:00+01:00"))
        XCTAssertEqual(boundary?.window, DateInterval(start: date("2026-11-23T08:00:00+01:00"), end: date("2026-11-23T18:00:00+01:00")))
    }

    func testWindowCrossingMidnightBelongsToItsStartDay() {
        let schedule = window(TimeOfDay(hour: 22, minute: 0), TimeOfDay(hour: 2, minute: 0), weekdays: [6])
        let fridayNight = DateInterval(start: date("2026-11-27T22:00:00+01:00"), end: date("2026-11-28T02:00:00+01:00"))
        let saturdayOne = date("2026-11-28T01:00:00+01:00")
        let saturdayTen = date("2026-11-28T22:00:00+01:00")

        let insideEnd = schedule.nextBoundary(after: saturdayOne, calendar: calendar)
        let nextStart = schedule.nextBoundary(after: saturdayTen, calendar: calendar)

        XCTAssertEqual(insideEnd?.kind, .end)
        XCTAssertEqual(insideEnd?.date, date("2026-11-28T02:00:00+01:00"))
        XCTAssertEqual(schedule.window(containing: saturdayOne, calendar: calendar), fridayNight)
        XCTAssertEqual(schedule.latestBoundary(atOrBefore: saturdayOne, calendar: calendar),
                       Boundary(kind: .start, date: fridayNight.start, window: fridayNight))
        XCTAssertEqual(nextStart?.kind, .start)
        XCTAssertEqual(nextStart?.date, date("2026-12-04T22:00:00+01:00"))
        XCTAssertNil(schedule.window(containing: saturdayTen, calendar: calendar))
    }

    func testSkipsDaysNotInWeekdays() {
        let schedule = window(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 18, minute: 0), weekdays: [2])
        let tuesdayNine = date("2026-11-24T09:00:00+01:00")

        let boundary = schedule.nextBoundary(after: tuesdayNine, calendar: calendar)

        XCTAssertEqual(boundary?.kind, .start)
        XCTAssertEqual(boundary?.date, date("2026-11-30T08:00:00+01:00"))
        XCTAssertNil(schedule.window(containing: tuesdayNine, calendar: calendar))
    }

    func testStartEqualsEndYieldsNothing() {
        let schedule = window(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 8, minute: 0), weekdays: everyDay)
        let now = date("2026-11-24T08:00:00+01:00")

        XCTAssertNil(schedule.nextBoundary(after: now, calendar: calendar))
        XCTAssertNil(schedule.latestBoundary(atOrBefore: now, calendar: calendar))
        XCTAssertNil(schedule.window(containing: now, calendar: calendar))
    }

    func testBoundaryActsOnceAfterClockMovesBack() {
        let schedule = window(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 18, minute: 0), weekdays: everyDay)
        let today = schedule.latestBoundary(atOrBefore: date("2026-11-24T19:00:00+01:00"), calendar: calendar)!
        let yesterday = schedule.latestBoundary(atOrBefore: date("2026-11-23T19:00:00+01:00"), calendar: calendar)!

        XCTAssertFalse(ScheduleWindow.shouldAct(on: today, lastActed: today))
        XCTAssertFalse(ScheduleWindow.shouldAct(on: yesterday, lastActed: today))
        XCTAssertTrue(ScheduleWindow.shouldAct(on: today, lastActed: yesterday))
        XCTAssertTrue(ScheduleWindow.shouldAct(on: today, lastActed: nil))
    }

    func testSpringForwardKeepsTheWindow() {
        // Clocks jump 02:00 to 03:00 on 2026-03-29, so a 02:30 start never happens.
        let schedule = window(TimeOfDay(hour: 2, minute: 30), TimeOfDay(hour: 6, minute: 0), weekdays: everyDay)
        let threeCEST = date("2026-03-29T03:00:00+02:00")

        let start = schedule.nextBoundary(after: date("2026-03-29T00:00:00+01:00"), calendar: calendar)
        let afterStart = start.flatMap { schedule.nextBoundary(after: $0.date, calendar: calendar) }

        XCTAssertEqual(start?.kind, .start)
        XCTAssertGreaterThanOrEqual(start!.date, threeCEST)
        XCTAssertEqual(afterStart?.kind, .end)
        XCTAssertEqual(afterStart?.date, date("2026-03-29T06:00:00+02:00"))
        XCTAssertNotNil(schedule.window(containing: date("2026-03-29T04:00:00+02:00"), calendar: calendar))
    }

    func testWindowInsideSpringForwardGapIsSkippedThatDay() {
        // Clocks jump 02:00 to 03:00 on 2026-03-29, so neither 02:10 nor 02:50 happens that day.
        let schedule = window(TimeOfDay(hour: 2, minute: 10), TimeOfDay(hour: 2, minute: 50), weekdays: [1])

        let boundary = schedule.nextBoundary(after: date("2026-03-28T12:00:00+01:00"), calendar: calendar)

        XCTAssertEqual(boundary?.kind, .start)
        XCTAssertEqual(boundary?.date, date("2026-04-05T02:10:00+02:00"))
    }

    func testFallBackRepeatedHourActsOnce() {
        // Clocks go back 03:00 to 02:00 on 2026-10-25, so 02:30 happens at +02:00 and again at +01:00.
        let schedule = window(TimeOfDay(hour: 22, minute: 0), TimeOfDay(hour: 2, minute: 30), weekdays: [7])
        let firstEnd = schedule.nextBoundary(after: date("2026-10-24T23:00:00+02:00"), calendar: calendar)!

        let repeatedEnd = schedule.nextBoundary(after: firstEnd.date, calendar: calendar)

        XCTAssertEqual(firstEnd.kind, .end)
        XCTAssertEqual(firstEnd.date, date("2026-10-25T02:30:00+02:00"))
        XCTAssertEqual(repeatedEnd?.kind, .end)
        XCTAssertEqual(repeatedEnd?.date, date("2026-10-25T02:30:00+01:00"))
        XCTAssertFalse(ScheduleWindow.shouldAct(on: repeatedEnd!, lastActed: firstEnd))
    }

    func testFallBackWindowInsideRepeatedHourActsOnce() {
        // Both 02:10 and 02:50 happen twice on 2026-10-25: at +02:00, then again at +01:00.
        let schedule = window(TimeOfDay(hour: 2, minute: 10), TimeOfDay(hour: 2, minute: 50), weekdays: [1])
        let afterTheNight = date("2026-10-25T03:00:00+01:00")
        var cursor = date("2026-10-25T00:00:00+02:00")
        var lastActed: Boundary?
        var acted: [Boundary] = []

        while let boundary = schedule.nextBoundary(after: cursor, calendar: calendar), boundary.date < afterTheNight {
            if ScheduleWindow.shouldAct(on: boundary, lastActed: lastActed) {
                acted.append(boundary)
                lastActed = boundary
            }
            cursor = boundary.date
        }

        XCTAssertEqual(acted.map(\.kind), [.start, .end])
        XCTAssertEqual(acted.map(\.date), [date("2026-10-25T02:10:00+02:00"), date("2026-10-25T02:50:00+02:00")])
    }
}
