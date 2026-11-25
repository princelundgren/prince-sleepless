import Foundation
import IOKit
import os

/// Reads the system's sleep-disabled flag, `SleepDisabled` on the IORegistry's `IOPMrootDomain`,
/// which `pmset disablesleep` sets. Needs no privileges and starts no process.
public enum SleepFlagReader {
    private static let log = Logger(subsystem: "com.princelundgren.princesleepless", category: "sleep-flag")

    /// The flag as it reads now: `false` while the kernel hasn't published the key, `nil` when
    /// `IOPMrootDomain` can't be found (logged as an error) or its value isn't a boolean.
    public static func read() -> Bool? {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else {
            log.error("IOPMrootDomain not found; the sleep flag can't be read")
            return nil
        }
        defer { IOObjectRelease(rootDomain) }
        // The kernel publishes the key only once a client has set it, so absent means 0.
        guard let value = IORegistryEntryCreateCFProperty(rootDomain, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        else { return false }
        return value as? Bool
    }
}
