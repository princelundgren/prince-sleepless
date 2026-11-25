import Foundation
import IOKit.ps
import notify
import PrinceSleeplessCore

@MainActor
final class PowerMonitor {
    private var sourceToken: Int32?
    private var lowPowerModeObservation: NotificationCenter.ObservationToken?

    /// The internal battery; `nil` on a Mac without one, and, logged as an error, when the power
    /// sources can't be read.
    nonisolated static func power() -> PowerSnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            appLog.error("Couldn't read the power sources")
            return nil
        }
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return PowerSnapshot.internalBattery(in: descriptions)
    }

    nonisolated static func readings() -> Readings {
        Readings(power: power(), lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    /// Calls `onSourceChange` each time the Mac moves between charger and battery, and
    /// `onLowPowerModeChange` each time Low Power Mode changes, until `stop()`. Does nothing
    /// while already started.
    func start(onSourceChange: @escaping @MainActor () -> Void, onLowPowerModeChange: @escaping @MainActor (Bool) -> Void) {
        if sourceToken == nil {
            var token: Int32 = 0
            let status = notify_register_dispatch(kIOPSNotifyPowerSource, &token, .main) { @Sendable _ in
                MainActor.assumeIsolated { onSourceChange() }
            }
            if status == NOTIFY_STATUS_OK {
                sourceToken = token
            } else {
                appLog.error("Couldn't watch the power source: notify status \(status)")
            }
        }
        if lowPowerModeObservation == nil {
            lowPowerModeObservation = NotificationCenter.default.addObserver(
                of: ProcessInfo.processInfo,
                for: .powerStateDidChange
            ) { @Sendable _ in
                await MainActor.run { onLowPowerModeChange(ProcessInfo.processInfo.isLowPowerModeEnabled) }
            }
        }
    }

    func stop() {
        if let sourceToken {
            notify_cancel(sourceToken)
            self.sourceToken = nil
        }
        if let lowPowerModeObservation {
            NotificationCenter.default.removeObserver(lowPowerModeObservation)
            self.lowPowerModeObservation = nil
        }
    }
}
