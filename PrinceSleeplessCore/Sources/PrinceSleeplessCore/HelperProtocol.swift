import Foundation

/// The version of `SleeplessHelperProtocol` this build speaks; the app refuses a helper that
/// reports another.
public let sleeplessHelperProtocolVersion = 1

/// The helper's launchd Mach service, which is also its `Label` and executable name.
public let sleeplessHelperMachService = "com.princelundgren.princesleepless.helper"

/// The root helper's XPC interface. The helper handles every call in the order it arrives, on
/// one serial queue, and calls each reply at most once: a call still queued when the helper exits
/// gets the connection's error instead, so callers use `remoteObjectProxyWithErrorHandler(_:)`.
@objc public protocol SleeplessHelperProtocol {
    /// Replies with the helper's `sleeplessHelperProtocolVersion`.
    func protocolVersion(reply: @escaping @Sendable (Int) -> Void)

    /// Sets the system's sleep-disabled flag to 1 unless it already reads 1, then guards this
    /// connection: when the last guarding connection goes away, the helper sets the flag to 0.
    /// Replies `true` only when the flag reads 1 afterwards.
    func keepAwake(reply: @escaping @Sendable (Bool) -> Void)

    /// Sets the sleep-disabled flag to 0, whatever other connections guard, and stops guarding
    /// this connection. Replies `true` only when the flag reads 0 afterwards.
    func allowSleep(reply: @escaping @Sendable (Bool) -> Void)
}
