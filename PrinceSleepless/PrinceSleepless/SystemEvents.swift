import AppKit

@MainActor
final class SystemEvents {
    private var observations: [NotificationCenter.ObservationToken] = []
    private var powerOffObserver: (any NSObjectProtocol)?

    /// Calls each callback on its system event for the app's lifetime. Does nothing while
    /// already started.
    func start(
        onWake: @escaping @MainActor () -> Void,
        onClockChange: @escaping @MainActor () -> Void,
        onWillPowerOff: @escaping @MainActor () -> Void
    ) {
        guard powerOffObserver == nil else { return }
        let workspace = NSWorkspace.shared
        observations = [
            workspace.notificationCenter.addObserver(of: workspace, for: .didWake) { _ in onWake() },
            NotificationCenter.default.addObserver(of: Date.self, for: .systemClockDidChange) { _ in onClockChange() },
            NotificationCenter.default.addObserver(of: TimeZone.self, for: .systemTimeZoneDidChange) { _ in onClockChange() },
        ]
        powerOffObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: workspace,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { onWillPowerOff() }
        }
    }
}
