import Foundation
import Observation
import os
import PrinceSleeplessCore

/// The controller, wired to the system: each event goes to the controller and each command it
/// returns is performed, in order. An event raised while commands are being performed waits
/// until they are done.
@MainActor
@Observable
final class AppModel {
    private(set) var controller: Controller

    @ObservationIgnored private let store = Store()
    @ObservationIgnored private let helper = HelperClient()
    @ObservationIgnored private let power = PowerMonitor()
    @ObservationIgnored private let timers = Timers()
    @ObservationIgnored private let systemEvents = SystemEvents()
    @ObservationIgnored private var pendingEvents: [Event] = []
    @ObservationIgnored private var isHandling = false
    /// `nil` when `kern.bootsessionuuid` couldn't be read at launch.
    @ObservationIgnored private let bootSession = BootSession.current()

    init() {
        controller = Controller(state: store.state, preferences: store.preferences, helper: helper.status)
        helper.onReply = { [weak self] call, ok in self?.helperReplied(call, ok: ok) }
        helper.onInterruption = { [weak self] in self?.send(.helperInterrupted) }
        helper.onVersionMismatch = { [weak self] in self?.send(.helperOutdated) }
        helper.onStatusChange = { [weak self] status in self?.send(.helper(status)) }
        timers.onBatteryCheck = { [weak self] in self?.batteryCheckDue() }
        timers.onKeepAwakeEnd = { [weak self] in self?.keepAwakeEndDue() }
        timers.onBoundary = { [weak self] boundary in self?.boundaryDue(boundary) }
    }

    func send(_ event: Event) {
        pendingEvents.append(event)
        guard !isHandling else { return }
        isHandling = true
        defer { isHandling = false }
        while !pendingEvents.isEmpty {
            let event = pendingEvents.removeFirst()
            for command in controller.handle(event, now: .now, calendar: .autoupdatingCurrent) {
                perform(command)
            }
        }
    }

    func launch() {
        systemEvents.start(
            onWake: { [weak self] in self?.woke() },
            onClockChange: { [weak self] in self?.send(.clockChanged(PowerMonitor.readings())) },
            onWillPowerOff: { [weak self] in self?.willPowerOff() })
        let flag = SleepFlagReader.read()
        if flag == nil {
            appLog.fault("Couldn't read the sleep flag at launch; taking it as off")
        }
        let lastBootSession = store.lastBootSession
        if bootSession == nil {
            appLog.fault("Couldn't read kern.bootsessionuuid; taking this launch as the last one's boot")
        }
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String
        let info = LaunchInfo(
            flagOn: flag ?? false,
            buildChanged: build != store.lastBuild,
            bootSession: bootSession ?? lastBootSession ?? UUID(),
            lastBootSession: lastBootSession,
            cleanQuit: store.cleanQuit,
            readings: PowerMonitor.readings())
        store.cleanQuit = false
        store.lastBuild = build
        if let bootSession {
            store.lastBootSession = bootSession
        }
        send(.launched(info))
    }

    /// Reads the helper's status and the flag again, since approval has no callback.
    func panelOpened() {
        send(.helper(helper.status))
        readFlag()
    }

    func terminate() {
        send(.willTerminate)
        store.cleanQuit = true
    }

    private func perform(_ command: Command) {
        switch command {
        case .registerHelper:
            helper.register()
        case .reregisterHelper:
            helper.reregister()
        case .openLoginItems:
            helper.openLoginItems()
        case .keepAwake:
            helper.send(.keepAwake)
        case .allowSleep:
            helper.send(.allowSleep)
        case .reguard:
            helper.send(.reguard)
        case .observePower(true):
            power.start(
                onSourceChange: { [weak self] in self?.powerSourceChanged() },
                onLowPowerModeChange: { [weak self] on in self?.send(.lowPowerMode(on)) })
            sendPower { .power($0) }
        case .observePower(false):
            power.stop()
        case .holdActivity(let hold):
            timers.holdActivity(hold)
        case .armBatteryCheck(let seconds):
            timers.armBatteryCheck(in: seconds)
        case .armTimer(let end):
            timers.armKeepAwakeEnd(at: end)
        case .armBoundary(let boundary):
            timers.armBoundary(boundary)
        case .save:
            store.save(controller.state, controller.preferences)
        case .notify, .requestNotificationAuthorization, .setLaunchAtLogin, .installUpdate:
            break
        }
    }

    private func readFlag() {
        guard let flag = SleepFlagReader.read() else {
            appLog.error("Couldn't read the sleep flag")
            return
        }
        send(.flagRead(flag))
    }

    private func sendPower(_ event: (PowerSnapshot) -> Event) {
        guard let power = PowerMonitor.power() else { return }
        send(event(power))
    }

    private func helperReplied(_ call: HelperCall, ok: Bool) {
        if call == .reguard && !ok {
            appLog.error("Couldn't guard the flag again after the helper was interrupted")
            send(.guardLost)
        } else {
            send(.helperReplied(ok: ok))
        }
        readFlag()
    }

    private func powerSourceChanged() {
        readFlag()
        sendPower { .power($0) }
    }

    private func batteryCheckDue() {
        readFlag()
        sendPower { .batteryCheckDue($0) }
    }

    private func keepAwakeEndDue() {
        readFlag()
        send(.timerFired)
    }

    private func boundaryDue(_ boundary: Boundary) {
        readFlag()
        send(.boundary(boundary, PowerMonitor.readings()))
    }

    private func woke() {
        readFlag()
        send(.woke(PowerMonitor.readings()))
    }

    private func willPowerOff() {
        guard let bootSession else {
            appLog.error("No boot session to record at power-off")
            return
        }
        send(.willPowerOff(bootSession: bootSession))
    }
}
