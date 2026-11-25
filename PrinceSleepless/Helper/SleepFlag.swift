import Foundation
import IOKit
import PrinceSleeplessCore

/// The system's sleep-disabled flag: `SleepDisabled` on the IORegistry's `IOPMrootDomain`, set
/// through `pmset`.
enum SleepFlag {
    private static let pmsetTimeout: DispatchTimeInterval = .seconds(10)

    /// The flag as it reads now, or `nil` when `IOPMrootDomain` or its value can't be read.
    static func read() -> Bool? {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else {
            helperLog.error("IOPMrootDomain not found; the sleep flag can't be read")
            return nil
        }
        defer { IOObjectRelease(rootDomain) }
        // The kernel publishes the key only once a client has set it, so absent means 0.
        guard let value = IORegistryEntryCreateCFProperty(rootDomain, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        else { return false }
        return value as? Bool
    }

    /// Runs `pmset` to set the flag, waiting at most `pmsetTimeout` for it to exit. Returns `true`
    /// when it exited 0; logs the failure otherwise. Doesn't read the flag back.
    static func set(disableSleep: Bool) -> Bool {
        run(URL(fileURLWithPath: PmsetCommand.executable), arguments: PmsetCommand.arguments(disableSleep: disableSleep), timeout: pmsetTimeout)
    }

    /// Runs `executable` and waits up to `timeout`; on overrun terminates it. Returns `true` only
    /// for an exit with status 0.
    private static func run(_ executable: URL, arguments: [String], timeout: DispatchTimeInterval) -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            helperLog.error("Couldn't launch \(executable.path, privacy: .public) \(arguments, privacy: .public): \(error, privacy: .public)")
            return false
        }
        guard exited.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            helperLog.error("\(executable.path, privacy: .public) \(arguments, privacy: .public) didn't exit in time; terminated it")
            return false
        }
        switch process.terminationReason {
        case .exit where process.terminationStatus == 0:
            return true
        case .exit:
            helperLog.error("\(executable.path, privacy: .public) \(arguments, privacy: .public) exited with status \(process.terminationStatus)")
        case .uncaughtSignal:
            helperLog.error("\(executable.path, privacy: .public) \(arguments, privacy: .public) was killed by a signal")
        @unknown default:
            helperLog.error("\(executable.path, privacy: .public) \(arguments, privacy: .public) ended for an unknown reason")
        }
        return false
    }
}
