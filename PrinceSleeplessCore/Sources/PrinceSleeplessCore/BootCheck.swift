import Foundation

/// The boot session the helper last stored.
public enum StoredBoot: Equatable, Sendable {
    /// No file: the helper has never run since it was registered.
    case missing
    /// A file that won't decode.
    case unreadable
    case session(UUID)
}

/// Whether the helper's launch is the first of a new boot, so it must clear the flag.
public enum BootCheck {
    /// `true` for a stored session other than `current`, or a stored value that won't decode;
    /// `false` when nothing is stored, since that launch is a registration and a flag the user is
    /// about to adopt stays.
    public static func isNewBoot(stored: StoredBoot, current: UUID) -> Bool {
        switch stored {
        case .missing: false
        case .unreadable: true
        case .session(let session): session != current
        }
    }
}
