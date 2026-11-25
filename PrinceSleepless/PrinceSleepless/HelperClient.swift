import Foundation
import PrinceSleeplessCore
import ServiceManagement

enum HelperCall: Sendable {
    case keepAwake
    case allowSleep
    /// `keepAwake` again for a run already on, after the helper was interrupted.
    case reguard
}

/// Calls run one at a time, in the order sent, each on a connection whose helper reported this
/// build's protocol version. Every call ends in exactly one `onReply`.
@MainActor
final class HelperClient {
    private typealias Ticket = SerialCallQueue<HelperCall>.Ticket

    var onReply: @MainActor (HelperCall, _ ok: Bool) -> Void = { _, _ in }
    /// The helper process exited, or its connection was invalidated; the next call relaunches
    /// the helper, through a new connection after an invalidation.
    var onInterruption: @MainActor () -> Void = {}
    /// The helper reports another protocol version. Its call fails; re-registering is the
    /// caller's decision.
    var onVersionMismatch: @MainActor () -> Void = {}
    var onStatusChange: @MainActor (HelperStatus) -> Void = { _ in }

    private let service = SMAppService.daemon(plistName: "com.princelundgren.princesleepless.helper.plist")
    private var calls = SerialCallQueue<HelperCall>()
    private var connection: NSXPCConnection?
    /// Tells the current connection's handlers from those of one already replaced.
    private var connectionNumber = 0
    private var versionConfirmed = false
    private var isReregistering = false

    var status: HelperStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .notRegistered
        @unknown default: .notRegistered
        }
    }

    func send(_ call: HelperCall) {
        if let ticket = calls.enqueue(call) {
            start(ticket)
        }
    }

    func register() {
        do {
            try service.register()
        } catch {
            appLog.error("Couldn't register the helper: \(error, privacy: .public)")
        }
        onStatusChange(status)
    }

    /// Unregisters the helper, which ends a running one, then registers it again. Does nothing
    /// while a re-registration is under way.
    func reregister() {
        guard !isReregistering else { return }
        isReregistering = true
        service.unregister { [weak self] error in
            Task { @MainActor in self?.unregistered(error) }
        }
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func unregistered(_ error: (any Error)?) {
        if let error {
            appLog.error("Couldn't unregister the helper: \(error, privacy: .public)")
        }
        isReregistering = false
        register()
    }

    /// Runs `body` on the main actor in the order XPC called its handlers (the interruption after
    /// every reply): the main queue is serial and FIFO, where a `Task` each has no start order.
    private nonisolated static func onMain(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }

    private func start(_ ticket: Ticket) {
        let connection = connection ?? makeConnection()
        if versionConfirmed {
            perform(ticket, on: connection)
        } else {
            confirmVersion(on: connection, before: ticket)
        }
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: sleeplessHelperMachService, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: SleeplessHelperProtocol.self)
        connectionNumber += 1
        let number = connectionNumber
        connection.interruptionHandler = { @Sendable [weak self] in
            Self.onMain { self?.interrupted(connection: number) }
        }
        connection.invalidationHandler = { @Sendable [weak self] in
            Self.onMain { self?.invalidated(connection: number) }
        }
        connection.activate()
        self.connection = connection
        versionConfirmed = false
        return connection
    }

    private func confirmVersion(on connection: NSXPCConnection, before ticket: Ticket) {
        let number = connectionNumber
        proxy(on: connection, for: ticket)?.protocolVersion { [weak self] version in
            Self.onMain { self?.versionReplied(version, connection: number, before: ticket) }
        }
    }

    private func versionReplied(_ version: Int, connection number: Int, before ticket: Ticket) {
        guard let connection, number == connectionNumber else {
            finish(ticket, ok: false)
            return
        }
        guard version == sleeplessHelperProtocolVersion else {
            appLog.error("The helper speaks protocol \(version), this app \(sleeplessHelperProtocolVersion)")
            connection.invalidate()
            self.connection = nil
            onVersionMismatch()
            finish(ticket, ok: false)
            return
        }
        versionConfirmed = true
        perform(ticket, on: connection)
    }

    private func perform(_ ticket: Ticket, on connection: NSXPCConnection) {
        guard let helper = proxy(on: connection, for: ticket) else { return }
        let reply: @Sendable (Bool) -> Void = { [weak self] ok in
            Self.onMain { self?.finish(ticket, ok: ok) }
        }
        switch ticket.call {
        case .keepAwake, .reguard: helper.keepAwake(reply: reply)
        case .allowSleep: helper.allowSleep(reply: reply)
        }
    }

    private func proxy(on connection: NSXPCConnection, for ticket: Ticket) -> SleeplessHelperProtocol? {
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            appLog.error("The helper didn't reply: \(error, privacy: .public)")
            Self.onMain { self?.finish(ticket, ok: false) }
        }
        guard let helper = proxy as? SleeplessHelperProtocol else {
            appLog.fault("The helper's proxy doesn't conform to SleeplessHelperProtocol")
            finish(ticket, ok: false)
            return nil
        }
        return helper
    }

    /// Ends `ticket` once, whichever of its reply and its error handler comes first, then starts
    /// the next call.
    private func finish(_ ticket: Ticket, ok: Bool) {
        guard calls.complete(ticket) else { return }
        let next = calls.running
        onReply(ticket.call, ok)
        if let next {
            start(next)
        }
    }

    private func interrupted(connection number: Int) {
        guard connection != nil, number == connectionNumber else { return }
        appLog.notice("The helper was interrupted")
        versionConfirmed = false
        onInterruption()
    }

    private func invalidated(connection number: Int) {
        guard connection != nil, number == connectionNumber else { return }
        appLog.notice("The helper connection was invalidated; the next call opens a new one")
        self.connection = nil
        versionConfirmed = false
        onInterruption()
    }
}
