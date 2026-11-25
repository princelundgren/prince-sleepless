import Foundation
import IOKit.ps

/// The battery state the stop conditions read.
public struct PowerSnapshot: Equatable, Sendable, Codable {
    /// Charge in percent, 0 to 100.
    public var charge: Int
    public var onBattery: Bool
    /// `nil` while the system has no estimate.
    public var minutesToEmpty: Int?

    public init(charge: Int, onBattery: Bool, minutesToEmpty: Int?) {
        self.charge = charge
        self.onBattery = onBattery
        self.minutesToEmpty = minutesToEmpty
    }
}

extension PowerSnapshot {
    /// The first present internal battery among `descriptions`, each a power source's
    /// `IOPSGetPowerSourceDescription`, or `nil` when there is none with a capacity.
    ///
    /// The charge is Current Capacity over Max Capacity in percent, rounded; `minutesToEmpty` is
    /// Time to Empty where it is 0 or more, since -1 means the system is still estimating.
    public static func internalBattery(in descriptions: [[String: Any]]) -> PowerSnapshot? {
        descriptions.lazy.compactMap(internalBattery(from:)).first
    }

    private static func internalBattery(from description: [String: Any]) -> PowerSnapshot? {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              description[kIOPSIsPresentKey] as? Bool == true,
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
        else { return nil }
        let minutesToEmpty = (description[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 >= 0 ? $0 : nil }
        return PowerSnapshot(
            charge: (current * 100 + max / 2) / max,
            onBattery: description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
            minutesToEmpty: minutesToEmpty)
    }
}
