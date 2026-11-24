import Foundation

/// A wall-clock time without a date.
public struct TimeOfDay: Equatable, Sendable, Codable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }
}

/// How long keep-awake runs once switched on.
public enum KeepAwakeDuration: Equatable, Sendable, Codable {
    case indefinitely
    case minutes(Int)
    case until(TimeOfDay)

    /// When keep-awake should end, or `nil` for `indefinitely`.
    ///
    /// `until` is the next occurrence strictly after `now` in `calendar`'s time zone; a time the
    /// zone skips (a DST gap) resolves to the next instant that exists.
    public func endDate(from now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .indefinitely:
            return nil
        case .minutes(let minutes):
            return now.addingTimeInterval(TimeInterval(minutes) * 60)
        case .until(let time):
            return calendar.nextDate(
                after: now,
                matching: DateComponents(hour: time.hour, minute: time.minute, second: 0),
                matchingPolicy: .nextTime)
        }
    }
}
