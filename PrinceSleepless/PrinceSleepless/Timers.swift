import Foundation
import PrinceSleeplessCore

@MainActor
final class Timers {
    private static let endTolerance: TimeInterval = 30
    private static let batteryCheckTolerance = 0.1

    var onBatteryCheck: @MainActor () -> Void = {}
    var onKeepAwakeEnd: @MainActor () -> Void = {}
    var onBoundary: @MainActor (Boundary) -> Void = { _ in }

    private var batteryCheck: Timer?
    private var keepAwakeEnd: Timer?
    private var boundary: Timer?
    private var activity: (any NSObjectProtocol)?

    func armBatteryCheck(in seconds: TimeInterval?) {
        batteryCheck?.invalidate()
        batteryCheck = seconds.map { seconds in
            schedule(at: .now + seconds, tolerance: seconds * Self.batteryCheckTolerance) { [weak self] in
                self?.onBatteryCheck()
            }
        }
    }

    func armKeepAwakeEnd(at date: Date?) {
        keepAwakeEnd?.invalidate()
        keepAwakeEnd = date.map { date in
            schedule(at: date, tolerance: Self.endTolerance) { [weak self] in self?.onKeepAwakeEnd() }
        }
    }

    func armBoundary(_ next: Boundary?) {
        boundary?.invalidate()
        boundary = next.map { next in
            schedule(at: next.date, tolerance: Self.endTolerance) { [weak self] in self?.onBoundary(next) }
        }
    }

    func holdActivity(_ hold: Bool) {
        switch (hold, activity) {
        case (true, nil):
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Keep-awake is on; its timers must fire on time")
        case (false, let held?):
            ProcessInfo.processInfo.endActivity(held)
            activity = nil
        default:
            break
        }
    }

    private func schedule(at date: Date, tolerance: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { fire() }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
