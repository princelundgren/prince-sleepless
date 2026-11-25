import Darwin
import Foundation

/// The kernel's id for the current boot.
public enum BootSession {
    /// `kern.bootsessionuuid`, which changes at every boot, or `nil` when it can't be read.
    public static func current() -> UUID? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return nil }
        return UUID(uuidString: String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self))
    }
}
