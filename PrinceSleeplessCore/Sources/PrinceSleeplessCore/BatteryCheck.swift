import Foundation

/// Spacing of the battery checks while keep-awake runs on battery.
public enum BatteryCheck {
    /// Seconds until the next check, or `nil` on the charger, where none is needed.
    ///
    /// Half the estimated time to reach `floor`, at least 60 s; 180 s without an estimate;
    /// 60 s at or under the floor.
    public static func nextCheck(after power: PowerSnapshot, floor: Int) -> TimeInterval? {
        guard power.onBattery else { return nil }
        guard power.charge > floor else { return 60 }
        guard let minutesToEmpty = power.minutesToEmpty else { return 180 }
        let secondsToFloor = Double(minutesToEmpty) * 60 * Double(power.charge - floor) / Double(power.charge)
        return max(60, secondsToFloor / 2)
    }
}
