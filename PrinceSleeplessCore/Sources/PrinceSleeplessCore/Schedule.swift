import Foundation

/// What the schedule does at a boundary.
public enum ScheduleMode: String, Codable, Sendable {
    /// The boundary switches keep-awake on or off itself.
    case automatic
    /// The boundary sends a notification that offers the switch.
    case notify
}

/// A start or end of one occurrence of a schedule window.
public struct Boundary: Equatable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable {
        case start
        case end
    }

    public var kind: Kind
    public var date: Date
    /// The occurrence this boundary belongs to, from its first start to its first end.
    ///
    /// A time repeated by a daylight-saving fall-back gives two boundaries of the same kind that
    /// share this interval. Test whether a date is inside a window with
    /// `ScheduleWindow.window(containing:calendar:)`, which excludes the end; `DateInterval.contains`
    /// includes it.
    public var window: DateInterval

    public init(kind: Kind, date: Date, window: DateInterval) {
        self.kind = kind
        self.date = date
        self.window = window
    }
}

/// A daily keep-awake window, on the weekdays it applies to.
///
/// An occurrence belongs to the day it starts on: an `end` at or before `start` ends on the next
/// day. A `start` equal to `end` is no window, and every query returns `nil`. `weekdays` holds
/// `Calendar` weekday numbers, 1 being Sunday. Pure: callers pass the date and the calendar.
public struct ScheduleWindow: Equatable, Sendable, Codable {
    public var start: TimeOfDay
    public var end: TimeOfDay
    public var weekdays: Set<Int>
    public var mode: ScheduleMode

    public init(start: TimeOfDay, end: TimeOfDay, weekdays: Set<Int>, mode: ScheduleMode) {
        self.start = start
        self.end = end
        self.weekdays = weekdays
        self.mode = mode
    }

    private static let searchDays = 8

    /// The first boundary strictly after `date`, or `nil` when no window starts within the next
    /// 8 days.
    ///
    /// A time a spring-forward gap skips resolves to the first instant after the gap, so an
    /// occurrence the gap swallows whole does not occur that day; a time a fall-back repeats is a
    /// boundary at each occurrence, and `shouldAct` keeps the window from acting twice.
    public func nextBoundary(after date: Date, calendar: Calendar) -> Boundary? {
        boundaries(ofWindowsStartingWithin: -1...Self.searchDays, daysFrom: date, calendar: calendar)
            .filter { $0.date > date }
            .min { $0.date < $1.date }
    }

    /// The last boundary at or before `date`, or `nil` when no window starts within the past
    /// 8 days.
    ///
    /// DST gaps and repeated times resolve as in `nextBoundary(after:calendar:)`.
    public func latestBoundary(atOrBefore date: Date, calendar: Calendar) -> Boundary? {
        boundaries(ofWindowsStartingWithin: -Self.searchDays...0, daysFrom: date, calendar: calendar)
            .filter { $0.date <= date }
            .max { $0.date < $1.date }
    }

    /// The occurrence `date` falls in, including its start and excluding its end, or `nil`
    /// outside every occurrence.
    public func window(containing date: Date, calendar: Calendar) -> DateInterval? {
        (-1...0)
            .compactMap { occurrence(startingOn: day(offset: $0, from: date, calendar: calendar), calendar: calendar) }
            .first { $0.start <= date && date < $0.end }
    }

    /// Whether `boundary` should act, given the last boundary acted on.
    ///
    /// Only when it is later than `lastActed` (not after the clock moves back) and either belongs
    /// to another window or is the end of the window whose start `lastActed` was. So each window
    /// acts at most once at its start and once at its end, even when a fall-back repeats both.
    public static func shouldAct(on boundary: Boundary, lastActed: Boundary?) -> Bool {
        guard let lastActed else { return true }
        guard boundary.date > lastActed.date else { return false }
        guard boundary.window == lastActed.window else { return true }
        return lastActed.kind == .start && boundary.kind == .end
    }

    private func boundaries(
        ofWindowsStartingWithin offsets: ClosedRange<Int>,
        daysFrom date: Date,
        calendar: Calendar
    ) -> [Boundary] {
        offsets.flatMap { offset in
            boundaries(ofWindowStartingOn: day(offset: offset, from: date, calendar: calendar), calendar: calendar)
        }
    }

    private func boundaries(ofWindowStartingOn day: Date, calendar: Calendar) -> [Boundary] {
        guard let window = occurrence(startingOn: day, calendar: calendar) else { return [] }
        let starts = instants(of: start, on: day, calendar: calendar)
            .map { Boundary(kind: .start, date: $0, window: window) }
        let ends = instants(of: end, on: endDay(forStartDay: day, calendar: calendar), calendar: calendar)
            .map { Boundary(kind: .end, date: $0, window: window) }
        return starts + ends
    }

    private func occurrence(startingOn day: Date, calendar: Calendar) -> DateInterval? {
        guard start != end,
              weekdays.contains(calendar.component(.weekday, from: day)),
              let startDate = instants(of: start, on: day, calendar: calendar).first,
              let endDate = instants(of: end, on: endDay(forStartDay: day, calendar: calendar), calendar: calendar).first,
              startDate < endDate
        else { return nil }
        return DateInterval(start: startDate, end: endDate)
    }

    private func endDay(forStartDay day: Date, calendar: Calendar) -> Date {
        let endsNextDay = (end.hour, end.minute) <= (start.hour, start.minute)
        return endsNextDay ? self.day(offset: 1, from: day, calendar: calendar) : day
    }

    private func day(offset: Int, from date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))!
    }

    /// Every instant `time` names on `day`: two when a fall-back repeats it, otherwise one.
    private func instants(of time: TimeOfDay, on day: Date, calendar: Calendar) -> [Date] {
        guard let first = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day, repeatedTimePolicy: .first),
              let last = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day, repeatedTimePolicy: .last)
        else { return [] }
        return first == last ? [first] : [first, last]
    }
}
