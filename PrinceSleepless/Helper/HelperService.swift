import Foundation
import PrinceSleeplessCore

/// The helper's state: which connections guard the sleep flag, and the pending idle exit.
///
/// Every piece of state is touched only on `queue`, a serial queue, which is why the type is
/// `@unchecked Sendable`; its methods hop onto it, so calls run in the order they arrive.
final class HelperService: @unchecked Sendable {
    private static let idleExitDelay: DispatchTimeInterval = .seconds(5)

    private let queue = DispatchQueue(label: "com.princelundgren.princesleepless.helper")
    private var book = GuardBook()
    private var lastConnectionID = 0
    private var pendingIdleExit: DispatchWorkItem?

    /// Clears the flag when `bootFile` holds another boot session than `current` (or one that
    /// won't decode), then stores `current` unless that clear failed, so the next launch retries
    /// it; arms the idle exit, so a launch nobody calls ends. Blocks until done.
    func runBootCheck(bootFile: BootFile, current: UUID) {
        queue.sync {
            defer { armIdleExit() }
            if BootCheck.isNewBoot(stored: bootFile.read(), current: current) {
                helperLog.notice("New boot session; clearing the sleep flag")
                guard restoreSleep() else {
                    helperLog.fault("Couldn't clear the sleep flag at boot; the next launch retries")
                    return
                }
            }
            do {
                try bootFile.store(current)
            } catch {
                helperLog.fault("Couldn't store the boot session in \(bootFile.file.path, privacy: .public): \(error, privacy: .public)")
            }
        }
    }

    /// A new id for an accepted connection, unique for this process's life. Blocks until done.
    func makeConnectionID() -> Int {
        queue.sync {
            lastConnectionID += 1
            return lastConnectionID
        }
    }

    func protocolVersion(reply: @escaping @Sendable (Int) -> Void) {
        queue.async { [self] in
            cancelIdleExit()
            reply(sleeplessHelperProtocolVersion)
            armIdleExit()
        }
    }

    /// `SleeplessHelperProtocol.keepAwake` for connection `id`.
    func keepAwake(connection id: Int, reply: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            cancelIdleExit()
            let flagBefore = SleepFlag.read()
            let flagSet = flagBefore == true || SleepFlag.set(disableSleep: true)
            let awake = flagSet && SleepFlag.read() == true
            if awake {
                book.guardConnection(id)
            } else {
                helperLog.error("Couldn't disable sleep for connection \(id)")
                // pmset may have set the flag unguarded; an unreadable one may be another connection's 1.
                if flagBefore == false { restoreSleep() }
            }
            reply(awake)
            armIdleExit()
        }
    }

    /// `SleeplessHelperProtocol.allowSleep` for connection `id`.
    func allowSleep(connection id: Int, reply: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            cancelIdleExit()
            let sleepAllowed = SleepFlag.set(disableSleep: false) && SleepFlag.read() == false
            if !sleepAllowed {
                helperLog.error("Couldn't allow sleep for connection \(id)")
            }
            _ = book.release(id)
            reply(sleepAllowed)
            armIdleExit()
        }
    }

    /// Connection `id` was interrupted or invalidated: when it was the last guard, sleep is
    /// restored.
    func connectionEnded(_ id: Int) {
        queue.async { [self] in
            if book.release(id) {
                helperLog.notice("The last guarding connection ended; restoring sleep")
                restoreSleep()
            }
            armIdleExit()
        }
    }

    /// Restores sleep if any connection guards the flag, then exits. For SIGTERM.
    func terminate() {
        queue.async { [self] in
            if !book.isEmpty {
                helperLog.notice("Terminated while guarding; restoring sleep")
                restoreSleep()
            }
            exit(EXIT_SUCCESS)
        }
    }

    /// Sets the flag to 0 unless it already reads 0. Returns `true` when it reads 0 afterwards.
    @discardableResult
    private func restoreSleep() -> Bool {
        guard SleepFlag.read() != false else { return true }
        let restored = SleepFlag.set(disableSleep: false) && SleepFlag.read() == false
        if !restored {
            helperLog.error("Couldn't restore sleep")
        }
        return restored
    }

    /// Exits after `idleExitDelay` if by then no connection guards and the flag reads 0;
    /// launchd starts the helper again on the next request.
    private func armIdleExit() {
        pendingIdleExit?.cancel()
        let idleExit = DispatchWorkItem { [self] in
            guard book.isEmpty, SleepFlag.read() == false else { return }
            helperLog.info("Idle; exiting")
            exit(EXIT_SUCCESS)
        }
        pendingIdleExit = idleExit
        queue.asyncAfter(deadline: .now() + Self.idleExitDelay, execute: idleExit)
    }

    private func cancelIdleExit() {
        pendingIdleExit?.cancel()
        pendingIdleExit = nil
    }
}

/// The object one connection calls: forwards each call to the service with the connection's id.
final class HelperConnection: NSObject, SleeplessHelperProtocol {
    private let id: Int
    private let service: HelperService

    init(id: Int, service: HelperService) {
        self.id = id
        self.service = service
    }

    func protocolVersion(reply: @escaping @Sendable (Int) -> Void) {
        service.protocolVersion(reply: reply)
    }

    func keepAwake(reply: @escaping @Sendable (Bool) -> Void) {
        service.keepAwake(connection: id, reply: reply)
    }

    func allowSleep(reply: @escaping @Sendable (Bool) -> Void) {
        service.allowSleep(connection: id, reply: reply)
    }
}

/// Accepts each connection the listener's code-signing requirement already let through, and
/// tells the service when it ends.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: HelperService

    init(service: HelperService) {
        self.service = service
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let id = service.makeConnectionID()
        let service = service
        connection.exportedInterface = NSXPCInterface(with: SleeplessHelperProtocol.self)
        connection.exportedObject = HelperConnection(id: id, service: service)
        connection.interruptionHandler = { service.connectionEnded(id) }
        connection.invalidationHandler = { service.connectionEnded(id) }
        connection.resume()
        return true
    }
}
