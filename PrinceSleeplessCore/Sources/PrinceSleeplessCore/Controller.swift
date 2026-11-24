import Foundation

/// The app's decisions: turns each event into the commands the app performs. Pure: callers pass
/// the time, the calendar and fresh readings, and perform the commands in the order returned.
public struct Controller: Sendable {
    public var state: ControllerState
    public var preferences: Preferences
    /// The helper's registration as last read; not saved, since the system holds it.
    public var helper: HelperStatus

    /// Stores `preferences` clamped, as `Preferences.clamped()` holds them.
    public init(state: ControllerState, preferences: Preferences, helper: HelperStatus) {
        self.state = state
        self.preferences = preferences.clamped()
        self.helper = helper
    }

    /// Sleep is disabled, whether or not the helper guards it.
    public var isOn: Bool { state.flagOn }

    /// Sleep is disabled and the helper guards it, so it ends if the app goes away.
    public var isProtected: Bool { state.flagOn && state.guarded }

    /// Applies `event` and returns the commands to perform, in order; the last is `.save`
    /// whenever `state` or `preferences` changed, and only then.
    public mutating func handle(_ event: Event, now: Date, calendar: Calendar) -> [Command] {
        let stateBefore = state
        let preferencesBefore = preferences
        var commands: [Command]
        switch event {
        case .launched(let info):
            commands = launched(info)
        case .flagRead(let flagOn):
            commands = flagRead(flagOn)
        case .helper(let status):
            commands = helperChanged(to: status)
        case .helperReplied(let ok):
            commands = ok ? [] : helperFailed()
        case .tapped(let readings):
            commands = toggle(readings)
        case .picked(let duration, let readings):
            commands = picked(duration, readings, now: now, calendar: calendar)
        case .notificationAction(let turnOn, let readings):
            commands = turnOn == isOn ? [] : toggle(readings)
        case .power(let power), .batteryCheckDue(let power):
            commands = powerRead(power)
        case .lowPowerMode(let on):
            commands = lowPowerModeChanged(on)
        case .preferencesChanged(let preferences):
            commands = preferencesChanged(to: preferences)
        case .updateReady:
            commands = updateReady()
        case .timerFired, .boundary, .woke, .clockChanged, .willPowerOff, .willTerminate:
            commands = []
        }
        if state != stateBefore || preferences != preferencesBefore {
            commands.append(.save)
        }
        return commands
    }

    private mutating func launched(_ info: LaunchInfo) -> [Command] {
        state.updateWaiting = false
        var commands: [Command]
        if info.flagOn {
            let newBootSession = info.lastBootSession.map { $0 != info.bootSession } ?? false
            commands = newBootSession && helper == .enabled
                ? switchOff(.staleAfterBoot)
                : adopt(info.readings.power)
        } else {
            commands = state.flagOn ? markOff() : []
        }
        if info.buildChanged && helper != .notRegistered {
            state.reregisterPending = true
        }
        if state.reregisterPending && !state.flagOn {
            state.reregisterPending = false
            commands.append(.reregisterHelper)
        }
        return commands
    }

    private mutating func flagRead(_ flagOn: Bool) -> [Command] {
        switch (flagOn, state.flagOn) {
        case (true, false): adopt(nil)
        case (false, true): markOff()
        default: []
        }
    }

    private mutating func helperChanged(to status: HelperStatus) -> [Command] {
        helper = status
        guard status == .enabled, state.flagOn, !state.guarded else { return [] }
        return adopt(nil)
    }

    /// A failed `keepAwake` leaves the flag as it was before: off after a switch-on, still on
    /// but unguarded after an adoption. After a failed `allowSleep` the controller already shows
    /// off; the app's next flag read adopts the flag that is still on.
    private mutating func helperFailed() -> [Command] {
        var commands: [Command] = []
        if state.flagOn {
            commands = state.origin == .adopted ? release() : markOff()
        }
        return commands + [.notify(.couldNotChange)]
    }

    private mutating func toggle(_ readings: Readings) -> [Command] {
        if let helperRequest { return helperRequest }
        return isOn ? switchOff(.user) : switchOn(readings, timerEnd: nil)
    }

    private mutating func picked(_ duration: KeepAwakeDuration, _ readings: Readings, now: Date, calendar: Calendar) -> [Command] {
        guard duration.isValid, !isOn else { return [] }
        if let helperRequest { return helperRequest }
        return switchOn(readings, timerEnd: duration.endDate(from: now, calendar: calendar))
    }

    private mutating func powerRead(_ power: PowerSnapshot) -> [Command] {
        guard isProtected else { return [] }
        state.lastPower = power
        if let reasonToStop { return autoOff(reasonToStop) }
        return [.armBatteryCheck(nextBatteryCheck(after: power))]
    }

    private mutating func lowPowerModeChanged(_ on: Bool) -> [Command] {
        guard isProtected else { return [] }
        state.lowPowerModeCameOn = on
        if let reasonToStop { return autoOff(reasonToStop) }
        return []
    }

    private mutating func preferencesChanged(to newPreferences: Preferences) -> [Command] {
        let old = preferences
        preferences = newPreferences.clamped()
        var commands: [Command] = []
        if preferences.stayOnAfterRestart && !old.stayOnAfterRestart {
            commands.append(.setLaunchAtLogin(true))
        }
        guard isProtected else { return commands }
        if let reasonToStop { return commands + autoOff(reasonToStop) }
        if preferences.floor != old.floor {
            commands.append(.armBatteryCheck(batteryCheck(for: state.lastPower)))
        }
        return commands
    }

    private mutating func updateReady() -> [Command] {
        guard isOn else { return [.installUpdate] }
        state.updateWaiting = true
        return []
    }

    /// What a user's switch needs first when the helper can't run it yet, else `nil`.
    private var helperRequest: [Command]? {
        switch helper {
        case .notRegistered: [.registerHelper]
        case .requiresApproval: [.openLoginItems]
        case .enabled: nil
        }
    }

    private var reasonToStop: OffReason? {
        AutoOff.reasonToStop(
            power: state.lastPower,
            lowPowerModeCameOn: state.lowPowerModeCameOn,
            floor: preferences.floor,
            lowPowerModeRule: preferences.lowPowerModeRule)
    }

    private func nextBatteryCheck(after power: PowerSnapshot) -> TimeInterval? {
        BatteryCheck.nextCheck(after: power, floor: preferences.floor)
    }

    /// With no reading yet, a check at once, whose `.batteryCheckDue` brings one.
    private func batteryCheck(for power: PowerSnapshot?) -> TimeInterval? {
        guard let power else { return 0 }
        return nextBatteryCheck(after: power)
    }

    private mutating func switchOn(_ readings: Readings, timerEnd: Date?) -> [Command] {
        if let reason = AutoOff.reasonToRefuse(
            power: readings.power,
            lowPowerMode: readings.lowPowerMode,
            source: .manual,
            floor: preferences.floor,
            lowPowerModeRule: preferences.lowPowerModeRule
        ) {
            state.lastOffReason = reason
            return []
        }
        markOn(origin: timerEnd == nil ? .manual : .manualWithTimer, timerEnd: timerEnd)
        return guardRun(readings.power) + (timerEnd.map { [.armTimer($0)] } ?? [])
    }

    /// Takes over a flag found on: guarded with the rules armed when the helper can run it,
    /// otherwise shown on but unguarded.
    private mutating func adopt(_ power: PowerSnapshot?) -> [Command] {
        markOn(origin: .adopted, timerEnd: nil)
        guard helper == .enabled else { return release() }
        if let reason = AutoOff.reasonToStop(
            power: power,
            lowPowerModeCameOn: false,
            floor: preferences.floor,
            lowPowerModeRule: preferences.lowPowerModeRule
        ) {
            return autoOff(reason)
        }
        return guardRun(power)
    }

    private mutating func markOn(origin: RunOrigin, timerEnd: Date?) {
        state.flagOn = true
        state.origin = origin
        state.timerEnd = timerEnd
        state.lastOffReason = nil
    }

    private mutating func guardRun(_ power: PowerSnapshot?) -> [Command] {
        state.guarded = true
        state.lastPower = power
        state.lowPowerModeCameOn = false
        return [
            .keepAwake,
            .observePower(true),
            .holdActivity(true),
            .armBatteryCheck(batteryCheck(for: power)),
            .requestNotificationAuthorization,
        ]
    }

    private mutating func autoOff(_ reason: OffReason) -> [Command] {
        switchOff(reason) + [.notify(.turnedOff(reason))]
    }

    private mutating func switchOff(_ reason: OffReason) -> [Command] {
        state.lastOffReason = reason
        return [.allowSleep] + markOff()
    }

    /// Records the flag as off and runs what waited for it to be off.
    private mutating func markOff() -> [Command] {
        state.flagOn = false
        state.origin = nil
        state.timerEnd = nil
        state.powerOff = nil
        var commands = release()
        if state.reregisterPending {
            state.reregisterPending = false
            commands.append(.reregisterHelper)
        }
        if state.updateWaiting {
            state.updateWaiting = false
            commands.append(.installUpdate)
        }
        return commands
    }

    /// Stops guarding the run and the rules that watch it.
    private mutating func release() -> [Command] {
        state.guarded = false
        state.lastPower = nil
        state.lowPowerModeCameOn = false
        return [.observePower(false), .holdActivity(false), .armBatteryCheck(nil)]
    }
}
