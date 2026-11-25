import Foundation

/// The app's decisions: turns each event into the commands the app performs. Pure: callers pass
/// the time, the calendar and fresh readings, and perform the commands in the order returned.
public struct Controller: Sendable {
    public var state: ControllerState
    public var preferences: Preferences
    /// The helper's registration as last read; not saved, since the system holds it.
    public var helper: HelperStatus
    /// The helper commands returned and not yet replied to. A flag read while any is outstanding
    /// is ignored, since the flag may still change; the read after the last reply counts. Not
    /// saved: no call outlives the app.
    private var outstandingHelperCalls = 0

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
    /// whenever `state` or `preferences` changed, and at `.willTerminate`, and only then.
    public mutating func handle(_ event: Event, now: Date, calendar: Calendar) -> [Command] {
        let stateBefore = state
        let preferencesBefore = preferences
        var commands: [Command]
        switch event {
        case .launched(let info):
            commands = launched(info, now: now, calendar: calendar)
        case .flagRead(let flagOn):
            commands = outstandingHelperCalls > 0 ? [] : flagRead(flagOn, now: now, calendar: calendar)
        case .helper(let status):
            commands = helperChanged(to: status, now: now, calendar: calendar)
        case .helperReplied(let ok):
            outstandingHelperCalls -= 1
            commands = ok ? [] : helperFailed()
        case .helperInterrupted:
            commands = isProtected ? [.reguard] : []
        case .guardLost:
            outstandingHelperCalls -= 1
            commands = guardLost()
        case .helperOutdated:
            commands = helperOutdated()
        case .tapped(let readings):
            commands = toggle(readings, now: now, calendar: calendar)
        case .picked(let duration, let readings):
            commands = picked(duration, readings, now: now, calendar: calendar)
        case .notificationAction(let turnOn, let readings):
            commands = turnOn == isOn ? [] : toggle(readings, now: now, calendar: calendar)
        case .power(let power), .batteryCheckDue(let power):
            commands = powerRead(power, now: now, calendar: calendar)
        case .lowPowerMode(let on):
            commands = lowPowerModeChanged(on, now: now, calendar: calendar)
        case .preferencesChanged(let preferences):
            commands = preferencesChanged(to: preferences, now: now, calendar: calendar)
        case .updateReady:
            commands = updateReady()
        case .timerFired:
            commands = timerFired(now: now, calendar: calendar)
        case .boundary(_, let readings):
            commands = boundaryFired(readings, now: now, calendar: calendar)
        case .woke(let readings), .clockChanged(let readings):
            commands = timeMoved(readings, now: now, calendar: calendar)
        case .willPowerOff(let bootSession):
            commands = willPowerOff(bootSession)
        case .willTerminate:
            commands = [.save]
        }
        outstandingHelperCalls += commands.count { [.keepAwake, .allowSleep, .reguard].contains($0) }
        if state != stateBefore || preferences != preferencesBefore {
            commands.append(.save)
        }
        return commands
    }

    private mutating func launched(_ info: LaunchInfo, now: Date, calendar: Calendar) -> [Command] {
        state.updateWaiting = false
        // A timer doesn't outlive the process that armed it; only a restore resumes one.
        state.timerEnd = nil
        let restore = restoreDue(info)
        state.powerOff = nil
        var commands: [Command]
        if let restore {
            commands = resume(restore, info, now: now, calendar: calendar)
        } else if info.flagOn {
            let newBootSession = info.lastBootSession.map { $0 != info.bootSession } ?? false
            commands = newBootSession && helper == .enabled
                ? switchOff(.staleAfterBoot, endedAt: now, calendar: calendar)
                : adopt(info.readings.power, now: now, calendar: calendar)
        } else {
            commands = flagFoundOff(info)
        }
        commands += catchUp(info.readings, now: now, calendar: calendar)
        if info.buildChanged && helper != .notRegistered {
            state.reregisterPending = true
        }
        if state.reregisterPending && !state.flagOn {
            state.reregisterPending = false
            commands.append(.reregisterHelper)
        }
        return commands + [.armTimer(state.timerEnd), .armBoundary(nextBoundary(after: now, calendar: calendar))]
    }

    private func restoreDue(_ info: LaunchInfo) -> PowerOffRecord? {
        guard preferences.stayOnAfterRestart,
              helper == .enabled,
              let record = state.powerOff,
              record.bootSession != info.bootSession
        else { return nil }
        return record
    }

    /// Reads the saved origin, so it runs before anything at launch clears it.
    private mutating func resume(_ record: PowerOffRecord, _ info: LaunchInfo, now: Date, calendar: Calendar) -> [Command] {
        let origin: RunOrigin = state.origin == .schedule ? .schedule : .restored
        if let end = record.timerEnd, end <= now {
            return endAtLaunch(.timer, flagOn: info.flagOn, endedAt: end, calendar: calendar)
        }
        if let reason = refusal(info.readings, source: .restore) {
            return endAtLaunch(reason, flagOn: info.flagOn, endedAt: now, calendar: calendar)
        }
        markOn(origin: origin, timerEnd: record.timerEnd, now: now)
        return guardRun(info.readings.power)
    }

    private mutating func endAtLaunch(_ reason: OffReason, flagOn: Bool, endedAt: Date, calendar: Calendar) -> [Command] {
        if flagOn { return switchOff(reason, endedAt: endedAt, calendar: calendar) }
        recordOff(reason, endedAt: endedAt, calendar: calendar)
        return state.flagOn ? markOff() : []
    }

    private mutating func flagFoundOff(_ info: LaunchInfo) -> [Command] {
        guard state.flagOn else { return [] }
        let crashed = state.guarded && !info.cleanQuit && info.lastBootSession == info.bootSession
        guard crashed else { return markOff() }
        state.lastOffReason = .helperRestored
        return markOff() + [.notify(.turnedOff(.helperRestored))]
    }

    private mutating func flagRead(_ flagOn: Bool, now: Date, calendar: Calendar) -> [Command] {
        switch (flagOn, state.flagOn) {
        case (true, false): adopt(nil, now: now, calendar: calendar)
        case (false, true): markOff()
        default: []
        }
    }

    /// Guards a run that is on but unguarded once the helper is enabled. Only a lost guard leaves
    /// a run of the app's own unguarded, so any origin but `.adopted` gets a re-guard that keeps
    /// the run's origin, timer and schedule.
    private mutating func helperChanged(to status: HelperStatus, now: Date, calendar: Calendar) -> [Command] {
        helper = status
        guard status == .enabled, state.flagOn, !state.guarded else { return [] }
        guard state.origin == .adopted else { return guardRun(nil, sending: .reguard) }
        return adopt(nil, now: now, calendar: calendar)
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

    /// Keeps the run on, with its origin and timer, since the flag still reads 1; only the guard
    /// and the rules that need it end.
    private mutating func guardLost() -> [Command] {
        guard isProtected else { return [] }
        return release() + [.notify(.couldNotChange)]
    }

    /// Unregistering ends the helper, so a run that is on waits for its switch-off.
    private mutating func helperOutdated() -> [Command] {
        guard !state.flagOn else {
            state.reregisterPending = true
            return []
        }
        return [.reregisterHelper]
    }

    private mutating func toggle(_ readings: Readings, now: Date, calendar: Calendar) -> [Command] {
        if let helperRequest { return helperRequest }
        return isOn
            ? switchOff(.user, endedAt: now, calendar: calendar)
            : switchOn(readings, origin: .manual, timerEnd: nil, now: now)
    }

    private mutating func picked(_ duration: KeepAwakeDuration, _ readings: Readings, now: Date, calendar: Calendar) -> [Command] {
        guard duration.isValid else { return [] }
        if let helperRequest { return helperRequest }
        let end = duration.endDate(from: now, calendar: calendar)
        let manualOrigin: RunOrigin = end == nil ? .manual : .manualWithTimer
        guard isOn else { return switchOn(readings, origin: manualOrigin, timerEnd: end, now: now) }
        state.timerEnd = end
        state.powerOff?.timerEnd = end
        if state.origin == .manual || state.origin == .manualWithTimer {
            state.origin = manualOrigin
        }
        return [.armTimer(end)]
    }

    private mutating func powerRead(_ power: PowerSnapshot, now: Date, calendar: Calendar) -> [Command] {
        guard isProtected else { return [] }
        state.lastPower = power
        if let reasonToStop { return autoOff(reasonToStop, now: now, calendar: calendar) }
        return [.armBatteryCheck(nextBatteryCheck(after: power))]
    }

    private mutating func lowPowerModeChanged(_ on: Bool, now: Date, calendar: Calendar) -> [Command] {
        guard isProtected else { return [] }
        state.lowPowerModeCameOn = on
        if let reasonToStop { return autoOff(reasonToStop, now: now, calendar: calendar) }
        return []
    }

    private mutating func preferencesChanged(to newPreferences: Preferences, now: Date, calendar: Calendar) -> [Command] {
        let old = preferences
        preferences = newPreferences.clamped()
        var commands: [Command] = []
        if preferences.stayOnAfterRestart && !old.stayOnAfterRestart {
            commands.append(.setLaunchAtLogin(true))
        }
        if preferences.schedule != old.schedule {
            state.holdOffUntil = nil
            commands.append(.armBoundary(nextBoundary(after: now, calendar: calendar)))
            if preferences.schedule != nil {
                commands.append(.requestNotificationAuthorization)
            }
        }
        guard isProtected else { return commands }
        if let reasonToStop { return commands + autoOff(reasonToStop, now: now, calendar: calendar) }
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

    /// A fire before the end (a replaced timer, or a clock that moved) arms the end again.
    private mutating func timerFired(now: Date, calendar: Calendar) -> [Command] {
        guard let end = state.timerEnd else { return [] }
        guard now >= end else { return [.armTimer(end)] }
        return switchOff(.timer, endedAt: end, calendar: calendar)
    }

    /// Decides by the time, not the boundary that fired, so a fire delayed past a window's end
    /// acts on that end and an early fire arms the same boundary again.
    private mutating func boundaryFired(_ readings: Readings, now: Date, calendar: Calendar) -> [Command] {
        catchUp(readings, now: now, calendar: calendar) + [.armBoundary(nextBoundary(after: now, calendar: calendar))]
    }

    private mutating func timeMoved(_ readings: Readings, now: Date, calendar: Calendar) -> [Command] {
        var commands: [Command] = []
        if let end = state.timerEnd {
            commands = end <= now ? switchOff(.timer, endedAt: end, calendar: calendar) : [.armTimer(end)]
        }
        return commands
            + catchUp(readings, now: now, calendar: calendar)
            + [.armBoundary(nextBoundary(after: now, calendar: calendar))]
    }

    private mutating func willPowerOff(_ bootSession: UUID) -> [Command] {
        guard isOn else { return [] }
        state.powerOff = PowerOffRecord(bootSession: bootSession, timerEnd: state.timerEnd)
        return []
    }

    /// Acts on the latest boundary at or before `now` only, so a start whose window has ended
    /// gives way to that window's end.
    private mutating func catchUp(_ readings: Readings, now: Date, calendar: Calendar) -> [Command] {
        guard let schedule = preferences.schedule,
              let latest = schedule.latestBoundary(atOrBefore: now, calendar: calendar),
              ScheduleWindow.shouldAct(on: latest, lastActed: state.lastActedBoundary)
        else { return [] }
        return act(on: latest, mode: schedule.mode, readings, now: now, calendar: calendar)
    }

    private mutating func act(on boundary: Boundary, mode: ScheduleMode, _ readings: Readings, now: Date, calendar: Calendar) -> [Command] {
        state.lastActedBoundary = boundary
        switch boundary.kind {
        case .start:
            if let holdOffUntil = state.holdOffUntil, boundary.date < holdOffUntil { return [] }
            state.holdOffUntil = nil
            return mode == .automatic ? scheduleStart(readings, now: now) : [.notify(.scheduleReminder(.start))]
        case .end:
            return mode == .automatic
                ? scheduleEnd(of: boundary.window, now: now, calendar: calendar)
                : [.notify(.scheduleReminder(.end))]
        }
    }

    private mutating func scheduleStart(_ readings: Readings, now: Date) -> [Command] {
        guard !isOn else { return [] }
        guard helper == .enabled else { return [.notify(.approveHelper)] }
        return switchOn(readings, origin: .schedule, timerEnd: nil, now: now)
    }

    private mutating func scheduleEnd(of window: DateInterval, now: Date, calendar: Calendar) -> [Command] {
        guard endsWithWindow(window) else { return [] }
        return switchOff(.schedule, endedAt: now, calendar: calendar)
    }

    private func endsWithWindow(_ window: DateInterval) -> Bool {
        switch state.origin {
        case .schedule:
            true
        case .manualWithTimer:
            state.runStartedAt.map { window.start <= $0 && $0 < window.end } ?? false
        case .manual, .adopted, .restored, nil:
            false
        }
    }

    private func nextBoundary(after date: Date, calendar: Calendar) -> Boundary? {
        preferences.schedule?.nextBoundary(after: date, calendar: calendar)
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

    private func refusal(_ readings: Readings, source: SwitchOnSource) -> OffReason? {
        AutoOff.reasonToRefuse(
            power: readings.power,
            lowPowerMode: readings.lowPowerMode,
            source: source,
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

    private mutating func switchOn(_ readings: Readings, origin: RunOrigin, timerEnd: Date?, now: Date) -> [Command] {
        if let reason = refusal(readings, source: origin == .schedule ? .schedule : .manual) {
            state.lastOffReason = reason
            return []
        }
        markOn(origin: origin, timerEnd: timerEnd, now: now)
        return guardRun(readings.power) + (timerEnd.map { [.armTimer($0)] } ?? [])
    }

    /// Takes over a flag found on: guarded with the rules armed when the helper can run it,
    /// otherwise shown on but unguarded.
    private mutating func adopt(_ power: PowerSnapshot?, now: Date, calendar: Calendar) -> [Command] {
        markOn(origin: .adopted, timerEnd: nil, now: now)
        guard helper == .enabled else { return release() }
        if let reason = AutoOff.reasonToStop(
            power: power,
            lowPowerModeCameOn: false,
            floor: preferences.floor,
            lowPowerModeRule: preferences.lowPowerModeRule
        ) {
            return autoOff(reason, now: now, calendar: calendar)
        }
        return guardRun(power)
    }

    private mutating func markOn(origin: RunOrigin, timerEnd: Date?, now: Date) {
        state.flagOn = true
        state.origin = origin
        state.runStartedAt = now
        state.timerEnd = timerEnd
        state.lastOffReason = nil
    }

    private mutating func guardRun(_ power: PowerSnapshot?, sending call: Command = .keepAwake) -> [Command] {
        state.guarded = true
        state.lastPower = power
        state.lowPowerModeCameOn = false
        return [
            call,
            .observePower(true),
            .holdActivity(true),
            .armBatteryCheck(batteryCheck(for: power)),
            .requestNotificationAuthorization,
        ]
    }

    private mutating func autoOff(_ reason: OffReason, now: Date, calendar: Calendar) -> [Command] {
        switchOff(reason, endedAt: now, calendar: calendar) + [.notify(.turnedOff(reason))]
    }

    private mutating func switchOff(_ reason: OffReason, endedAt: Date, calendar: Calendar) -> [Command] {
        recordOff(reason, endedAt: endedAt, calendar: calendar)
        return [.allowSleep] + markOff()
    }

    /// `endedAt` is when the run ended, which for a timer noticed late is the timer's end.
    private mutating func recordOff(_ reason: OffReason, endedAt: Date, calendar: Calendar) {
        state.lastOffReason = reason
        guard reason.holdsTheSchedule,
              let schedule = preferences.schedule,
              let window = schedule.window(containing: endedAt, calendar: calendar)
        else { return }
        state.holdOffUntil = nextStart(of: schedule, after: window.end, calendar: calendar)
    }

    private func nextStart(of schedule: ScheduleWindow, after date: Date, calendar: Calendar) -> Date? {
        var boundary = schedule.nextBoundary(after: date, calendar: calendar)
        while let found = boundary, found.kind != .start {
            boundary = schedule.nextBoundary(after: found.date, calendar: calendar)
        }
        return boundary?.date
    }

    /// Records the flag as off, cancels the run's timer and runs what waited for it to be off.
    private mutating func markOff() -> [Command] {
        let hadTimer = state.timerEnd != nil
        state.flagOn = false
        state.origin = nil
        state.runStartedAt = nil
        state.timerEnd = nil
        state.powerOff = nil
        var commands = release()
        if hadTimer {
            commands.append(.armTimer(nil))
        }
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

private extension OffReason {
    var holdsTheSchedule: Bool {
        switch self {
        case .user, .battery, .lowPowerMode, .timer: true
        case .schedule, .helperRestored, .staleAfterBoot: false
        }
    }
}
