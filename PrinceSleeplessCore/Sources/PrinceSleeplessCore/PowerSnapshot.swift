import Foundation

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
