import Foundation

/// Why keep-awake ended or was refused.
public enum OffReason: Equatable, Sendable, Codable {
    case user
    case battery(charge: Int)
    case lowPowerMode
    case timer
    case schedule
    case helperRestored
    case staleAfterBoot
}

/// What asked for keep-awake to be switched on.
public enum SwitchOnSource: Sendable {
    case manual
    case schedule
    case restore
}

/// The rules that end keep-awake on their own, or refuse to start it. Pure: callers pass the readings.
public enum AutoOff {
    /// The reason to stop while keep-awake is on, or `nil` to keep going.
    ///
    /// Both rules apply only on battery, so `nil` is returned without a power reading.
    /// The charge floor wins over Low Power Mode.
    public static func reasonToStop(
        power: PowerSnapshot?,
        lowPowerModeCameOn: Bool,
        floor: Int,
        lowPowerModeRule: Bool
    ) -> OffReason? {
        guard let power, power.onBattery else { return nil }
        if power.charge <= floor { return .battery(charge: power.charge) }
        if lowPowerModeRule && lowPowerModeCameOn { return .lowPowerMode }
        return nil
    }

    /// The reason not to switch keep-awake on, or `nil` to allow it.
    ///
    /// Both rules apply only on battery, so `nil` is returned without a power reading.
    /// A manual switch-on overrides Low Power Mode but never the charge floor.
    public static func reasonToRefuse(
        power: PowerSnapshot?,
        lowPowerMode: Bool,
        source: SwitchOnSource,
        floor: Int,
        lowPowerModeRule: Bool
    ) -> OffReason? {
        guard let power, power.onBattery else { return nil }
        if power.charge <= floor { return .battery(charge: power.charge) }
        if lowPowerModeRule && lowPowerMode && source != .manual { return .lowPowerMode }
        return nil
    }
}
