import XCTest
@testable import PrinceSleeplessCore

final class ControllerSchedulingTests: XCTestCase {
    private let charger = PowerSnapshot(charge: 80, onBattery: false, minutesToEmpty: nil)
    private let bootA = UUID()
    private let bootB = UUID()

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }

    private let workdays = ScheduleWindow(
        start: TimeOfDay(hour: 8, minute: 0),
        end: TimeOfDay(hour: 18, minute: 0),
        weekdays: [2, 3, 4, 5, 6],
        mode: .automatic)

    /// 2026-11-23 is a Monday.
    private func monday(_ time: String) -> Date {
        ISO8601DateFormatter().date(from: "2026-11-23T\(time):00+01:00")!
    }

    private func tuesday(_ time: String) -> Date {
        ISO8601DateFormatter().date(from: "2026-11-24T\(time):00+01:00")!
    }

    private func readings(_ power: PowerSnapshot? = nil, lowPowerMode: Bool = false) -> Readings {
        Readings(power: power ?? charger, lowPowerMode: lowPowerMode)
    }

    private func controller(
        state: ControllerState = ControllerState(),
        helper: HelperStatus = .enabled,
        schedule: ScheduleWindow? = nil,
        stayOnAfterRestart: Bool = false
    ) -> Controller {
        Controller(
            state: state,
            preferences: Preferences(stayOnAfterRestart: stayOnAfterRestart, schedule: schedule),
            helper: helper)
    }

    private func boundary(_ kind: Boundary.Kind, at date: Date) -> Boundary {
        workdays.nextBoundary(after: date.addingTimeInterval(-1), calendar: calendar)!
            .checked(kind: kind, date: date)
    }

    private func launch(
        flagOn: Bool = false,
        buildChanged: Bool = false,
        bootSession: UUID? = nil,
        lastBootSession: UUID? = nil,
        cleanQuit: Bool = true
    ) -> Event {
        let bootSession = bootSession ?? bootA
        return .launched(LaunchInfo(
            flagOn: flagOn,
            buildChanged: buildChanged,
            bootSession: bootSession,
            lastBootSession: lastBootSession ?? bootSession,
            cleanQuit: cleanQuit,
            readings: readings()))
    }

    private func send(_ event: Event, to controller: inout Controller, at date: Date) -> [Command] {
        controller.handle(event, now: date, calendar: calendar)
    }

    private func armedBoundaries(in commands: [Command]) -> [Boundary?] {
        commands.compactMap { if case .armBoundary(let boundary) = $0 { boundary } else { nil } }
    }

    // MARK: Timer

    func testPickWhileOffSwitchesOnAndArmsTimer() {
        var controller = controller()
        let now = monday("10:00")

        let commands = send(.picked(.minutes(30), readings()), to: &controller, at: now)

        XCTAssertTrue(commands.contains(.keepAwake))
        XCTAssertTrue(commands.contains(.armTimer(now.addingTimeInterval(1800))))
        XCTAssertEqual(controller.state.origin, .manualWithTimer)
    }

    func testTimerFiredTurnsOff() {
        var controller = controller()
        _ = send(.picked(.minutes(30), readings()), to: &controller, at: monday("10:00"))

        let commands = send(.timerFired, to: &controller, at: monday("10:30"))

        XCTAssertTrue(commands.contains(.allowSleep))
        XCTAssertFalse(commands.contains { if case .notify = $0 { true } else { false } })
        XCTAssertEqual(controller.state.lastOffReason, .timer)
        XCTAssertFalse(controller.isOn)
    }

    func testTimerFiredBeforeItsEndRearms() {
        var controller = controller()
        _ = send(.picked(.minutes(30), readings()), to: &controller, at: monday("10:00"))

        let commands = send(.timerFired, to: &controller, at: monday("10:29"))

        XCTAssertEqual(commands, [.armTimer(monday("10:30"))])
        XCTAssertTrue(controller.isOn)
    }

    func testPickWhileOnReplacesTheEnd() {
        var controller = controller()
        _ = send(.tapped(readings()), to: &controller, at: monday("10:00"))

        XCTAssertEqual(send(.picked(.minutes(30), readings()), to: &controller, at: monday("10:00")).first, .armTimer(monday("10:30")))
        XCTAssertEqual(controller.state.origin, .manualWithTimer)

        XCTAssertEqual(send(.picked(.indefinitely, readings()), to: &controller, at: monday("10:05")).first, .armTimer(nil))
        XCTAssertEqual(controller.state.origin, .manual)
        XCTAssertNil(controller.state.timerEnd)
    }

    func testSwitchingOffATimedRunCancelsItsTimer() {
        var controller = controller()
        _ = send(.picked(.minutes(30), readings()), to: &controller, at: monday("10:00"))

        let commands = send(.tapped(readings()), to: &controller, at: monday("10:10"))

        XCTAssertTrue(commands.contains(.allowSleep))
        XCTAssertTrue(commands.contains(.armTimer(nil)))
    }

    func testFailedTimedSwitchOnCancelsItsTimer() {
        var controller = controller()
        _ = send(.picked(.minutes(30), readings()), to: &controller, at: monday("10:00"))

        let commands = send(.helperReplied(ok: false), to: &controller, at: monday("10:00"))

        XCTAssertTrue(commands.contains(.armTimer(nil)))
        XCTAssertFalse(controller.isOn)
    }

    // MARK: Schedule

    func testTimerAndScheduleEarliestWins() {
        var controller = controller(schedule: workdays)
        _ = send(.boundary(boundary(.start, at: monday("08:00")), readings()), to: &controller, at: monday("08:00"))
        XCTAssertEqual(controller.state.origin, .schedule)
        XCTAssertTrue(send(.picked(.until(TimeOfDay(hour: 19, minute: 0)), readings()), to: &controller, at: monday("10:00"))
            .contains(.armTimer(monday("19:00"))))
        XCTAssertEqual(controller.state.origin, .schedule)

        let commands = send(.boundary(boundary(.end, at: monday("18:00")), readings()), to: &controller, at: monday("18:00"))

        XCTAssertTrue(commands.contains(.allowSleep))
        XCTAssertTrue(commands.contains(.armTimer(nil)))
        XCTAssertEqual(controller.state.lastOffReason, .schedule)
    }

    func testEndLeavesAnIndefiniteManualRunOn() {
        var controller = controller(schedule: workdays)
        _ = send(.tapped(readings()), to: &controller, at: monday("10:00"))

        let commands = send(.boundary(boundary(.end, at: monday("18:00")), readings()), to: &controller, at: monday("18:00"))

        XCTAssertFalse(commands.contains(.allowSleep))
        XCTAssertTrue(controller.isOn)
    }

    func testEndLeavesATimerRunStartedBeforeTheWindowOn() {
        var controller = controller(schedule: workdays)
        _ = send(.picked(.until(TimeOfDay(hour: 20, minute: 0)), readings()), to: &controller, at: monday("07:45"))
        _ = send(.boundary(boundary(.start, at: monday("08:00")), readings()), to: &controller, at: monday("08:00"))

        let commands = send(.boundary(boundary(.end, at: monday("18:00")), readings()), to: &controller, at: monday("18:00"))

        XCTAssertFalse(commands.contains(.allowSleep))
        XCTAssertTrue(controller.isOn)
        XCTAssertEqual(controller.state.timerEnd, monday("20:00"))
    }

    func testEndSwitchesOffATimerRunStartedInsideTheWindow() {
        var controller = controller(schedule: workdays)
        _ = send(.picked(.until(TimeOfDay(hour: 20, minute: 0)), readings()), to: &controller, at: monday("10:00"))

        let commands = send(.boundary(boundary(.end, at: monday("18:00")), readings()), to: &controller, at: monday("18:00"))

        XCTAssertTrue(commands.contains(.allowSleep))
        XCTAssertTrue(commands.contains(.armTimer(nil)))
    }

    func testAutomaticStartSwitchesOn() {
        var controller = controller(schedule: workdays)

        let commands = send(.boundary(boundary(.start, at: monday("08:00")), readings()), to: &controller, at: monday("08:00"))

        XCTAssertTrue(commands.contains(.keepAwake))
        XCTAssertEqual(controller.state.origin, .schedule)
        XCTAssertEqual(armedBoundaries(in: commands), [boundary(.end, at: monday("18:00"))])
        XCTAssertEqual(commands.last, .save)
        XCTAssertEqual(controller.state.lastActedBoundary, boundary(.start, at: monday("08:00")))
    }

    func testNotifyStartOnlyNotifies() {
        var schedule = workdays
        schedule.mode = .notify
        var controller = controller(schedule: schedule)

        let commands = send(.boundary(boundary(.start, at: monday("08:00")), readings()), to: &controller, at: monday("08:00"))

        XCTAssertTrue(commands.contains(.notify(.scheduleReminder(.start))))
        XCTAssertFalse(commands.contains(.keepAwake))
    }

    func testStartWhileLowPowerModeStaysOff() {
        var controller = controller(schedule: workdays)
        let onBattery = readings(PowerSnapshot(charge: 80, onBattery: true, minutesToEmpty: nil), lowPowerMode: true)

        let commands = send(.boundary(boundary(.start, at: monday("08:00")), onBattery), to: &controller, at: monday("08:00"))

        XCTAssertFalse(commands.contains(.keepAwake))
        XCTAssertEqual(controller.state.lastOffReason, .lowPowerMode)
    }

    func testSameBoundaryTwiceActsOnce() {
        var controller = controller(schedule: workdays)
        let start = boundary(.start, at: monday("08:00"))
        _ = send(.boundary(start, readings()), to: &controller, at: monday("08:00"))
        _ = send(.flagRead(false), to: &controller, at: monday("08:00"))

        let again = send(.boundary(start, readings()), to: &controller, at: monday("08:00"))
        let earlier = send(.boundary(boundary(.end, at: monday("18:00").addingTimeInterval(-3 * 86_400)), readings()), to: &controller, at: monday("08:01"))

        XCTAssertFalse(again.contains(.keepAwake))
        XCTAssertEqual(armedBoundaries(in: again), [boundary(.end, at: monday("18:00"))])
        XCTAssertEqual(armedBoundaries(in: earlier), [boundary(.end, at: monday("18:00"))])
        XCTAssertEqual(controller.state.lastActedBoundary, start)
    }

    func testManualOffInsideWindowHoldsAcrossRelaunch() {
        var first = controller(schedule: workdays)
        _ = send(.tapped(readings()), to: &first, at: monday("09:00"))
        _ = send(.tapped(readings()), to: &first, at: monday("10:00"))
        XCTAssertEqual(first.state.holdOffUntil, tuesday("08:00"))

        var relaunched = controller(state: first.state, schedule: workdays)
        let launched = send(launch(), to: &relaunched, at: monday("11:00"))
        let tuesdayStart = send(.boundary(boundary(.start, at: tuesday("08:00")), readings()), to: &relaunched, at: tuesday("08:00"))

        XCTAssertFalse(launched.contains(.keepAwake))
        XCTAssertTrue(tuesdayStart.contains(.keepAwake))
        XCTAssertNil(relaunched.state.holdOffUntil)
    }

    func testTimerEndInsideWindowHoldsAcrossRelaunch() {
        var first = controller(schedule: workdays)
        _ = send(.picked(.minutes(30), readings()), to: &first, at: monday("09:00"))
        _ = send(.timerFired, to: &first, at: monday("09:30"))

        var relaunched = controller(state: first.state, schedule: workdays)

        XCTAssertFalse(send(launch(), to: &relaunched, at: monday("10:00")).contains(.keepAwake))
    }

    func testWakeAfterWindowEndedSkipsStart() {
        var controller = controller(schedule: workdays)
        _ = send(launch(), to: &controller, at: monday("07:00"))

        let commands = send(.woke(readings()), to: &controller, at: monday("19:00"))

        XCTAssertFalse(commands.contains(.keepAwake))
        XCTAssertEqual(armedBoundaries(in: commands), [boundary(.start, at: tuesday("08:00"))])
    }

    func testLateStartBoundaryAfterWindowEndedSkipsStart() {
        var controller = controller(schedule: workdays)
        _ = send(launch(), to: &controller, at: monday("07:00"))

        let commands = send(.boundary(boundary(.start, at: monday("08:00")), readings()), to: &controller, at: monday("19:00"))

        XCTAssertFalse(commands.contains(.keepAwake))
        XCTAssertEqual(armedBoundaries(in: commands), [boundary(.start, at: tuesday("08:00"))])
    }

    func testTimerEndedBeforeTheWindowDoesNotHoldIt() {
        var controller = controller(schedule: workdays)
        _ = send(.picked(.minutes(30), readings()), to: &controller, at: monday("07:00"))

        let commands = send(.clockChanged(readings()), to: &controller, at: monday("09:00"))

        XCTAssertTrue(commands.contains(.keepAwake))
        XCTAssertEqual(controller.state.origin, .schedule)
        XCTAssertNil(controller.state.holdOffUntil)
    }

    func testRestoreWhoseTimerEndedBeforeTheWindowSwitchesOnWithIt() {
        var before = controller(schedule: workdays, stayOnAfterRestart: true)
        _ = send(.picked(.minutes(30), readings()), to: &before, at: monday("07:00"))
        _ = send(.willPowerOff(bootSession: bootA), to: &before, at: monday("07:10"))

        var restored = controller(state: before.state, schedule: workdays, stayOnAfterRestart: true)
        let commands = send(launch(bootSession: bootB, lastBootSession: bootA), to: &restored, at: monday("09:00"))

        XCTAssertTrue(commands.contains(.keepAwake))
        XCTAssertEqual(restored.state.origin, .schedule)
        XCTAssertEqual(restored.state.lastOffReason, nil)
    }

    func testLaunchInsideAutomaticWindowSwitchesOn() {
        var controller = controller(schedule: workdays)

        let commands = send(launch(), to: &controller, at: monday("10:00"))

        XCTAssertTrue(commands.contains(.keepAwake))
        XCTAssertEqual(controller.state.origin, .schedule)
        XCTAssertEqual(armedBoundaries(in: commands), [boundary(.end, at: monday("18:00"))])
    }

    func testLaunchSwitchedOnByTheScheduleDefersReregistration() {
        var controller = controller(schedule: workdays)

        let commands = send(launch(buildChanged: true), to: &controller, at: monday("10:00"))

        XCTAssertTrue(commands.contains(.keepAwake))
        XCTAssertFalse(commands.contains(.reregisterHelper))
        XCTAssertTrue(controller.state.reregisterPending)
    }

    func testAutomaticStartWithHelperUnapprovedAsksForApproval() {
        var controller = controller(helper: .requiresApproval, schedule: workdays)

        let commands = send(.boundary(boundary(.start, at: monday("08:00")), readings()), to: &controller, at: monday("08:00"))

        XCTAssertTrue(commands.contains(.notify(.approveHelper)))
        XCTAssertFalse(commands.contains(.keepAwake))
        XCTAssertFalse(commands.contains(.openLoginItems))
    }

    func testNoScheduleWhileOffArmsNothing() {
        var controller = controller()

        let commands = send(launch(), to: &controller, at: monday("10:00"))

        XCTAssertTrue(commands.contains(.armBoundary(nil)))
        XCTAssertTrue(commands.contains(.armTimer(nil)))
        XCTAssertEqual(armedBoundaries(in: commands), [nil])
    }

    func testSettingAScheduleArmsItAndClearsTheHold() {
        var controller = controller(state: ControllerState(holdOffUntil: tuesday("08:00")))

        let commands = send(.preferencesChanged(Preferences(schedule: workdays)), to: &controller, at: monday("19:00"))

        XCTAssertEqual(armedBoundaries(in: commands), [boundary(.start, at: tuesday("08:00"))])
        XCTAssertTrue(commands.contains(.requestNotificationAuthorization))
        XCTAssertNil(controller.state.holdOffUntil)
    }

    func testClockChangedRearmsBoundaryAndTimer() {
        var controller = controller(schedule: workdays)
        _ = send(.tapped(readings()), to: &controller, at: monday("07:00"))
        _ = send(.picked(.minutes(30), readings()), to: &controller, at: monday("07:00"))

        let rearmed = send(.clockChanged(readings()), to: &controller, at: monday("07:10"))
        XCTAssertTrue(rearmed.contains(.armTimer(monday("07:30"))))
        XCTAssertEqual(armedBoundaries(in: rearmed), [boundary(.start, at: monday("08:00"))])

        let passed = send(.clockChanged(readings()), to: &controller, at: monday("07:40"))
        XCTAssertTrue(passed.contains(.allowSleep))
        XCTAssertEqual(controller.state.lastOffReason, .timer)
    }

    // MARK: Restarts and launch

    func testRestartRestoresWithStayOn() {
        var before = controller(stayOnAfterRestart: true)
        _ = send(.picked(.until(TimeOfDay(hour: 15, minute: 0)), readings()), to: &before, at: monday("10:00"))
        _ = send(.willPowerOff(bootSession: bootA), to: &before, at: monday("11:00"))
        XCTAssertEqual(before.state.powerOff, PowerOffRecord(bootSession: bootA, timerEnd: monday("15:00")))

        var restored = controller(state: before.state, stayOnAfterRestart: true)
        let commands = send(launch(bootSession: bootB, lastBootSession: bootA), to: &restored, at: monday("12:00"))

        XCTAssertTrue(commands.contains(.keepAwake))
        XCTAssertTrue(commands.contains(.armTimer(monday("15:00"))))
        XCTAssertEqual(restored.state.origin, .restored)
        XCTAssertNil(restored.state.powerOff)

        var late = controller(state: before.state, stayOnAfterRestart: true)
        let lateCommands = send(launch(bootSession: bootB, lastBootSession: bootA), to: &late, at: monday("16:00"))

        XCTAssertFalse(lateCommands.contains(.keepAwake))
        XCTAssertFalse(late.isOn)
        XCTAssertEqual(late.state.lastOffReason, .timer)
        XCTAssertNil(late.state.powerOff)
    }

    func testRestoredFlagStillOnPastItsTimerAllowsSleep() {
        var before = controller(stayOnAfterRestart: true)
        _ = send(.picked(.until(TimeOfDay(hour: 15, minute: 0)), readings()), to: &before, at: monday("10:00"))
        _ = send(.willPowerOff(bootSession: bootA), to: &before, at: monday("11:00"))

        var late = controller(state: before.state, stayOnAfterRestart: true)
        let commands = send(launch(flagOn: true, bootSession: bootB, lastBootSession: bootA), to: &late, at: monday("16:00"))

        XCTAssertTrue(commands.contains(.allowSleep))
        XCTAssertEqual(late.state.lastOffReason, .timer)
    }

    func testRestoredScheduleRunEndsWithItsWindow() {
        var before = controller(schedule: workdays, stayOnAfterRestart: true)
        _ = send(.boundary(boundary(.start, at: monday("08:00")), readings()), to: &before, at: monday("08:00"))
        _ = send(.willPowerOff(bootSession: bootA), to: &before, at: monday("12:00"))

        var restored = controller(state: before.state, schedule: workdays, stayOnAfterRestart: true)
        XCTAssertTrue(send(launch(bootSession: bootB, lastBootSession: bootA), to: &restored, at: monday("12:05")).contains(.keepAwake))
        XCTAssertEqual(restored.state.origin, .schedule)
        XCTAssertTrue(send(.boundary(boundary(.end, at: monday("18:00")), readings()), to: &restored, at: monday("18:00")).contains(.allowSleep))

        var bootedLate = controller(state: before.state, schedule: workdays, stayOnAfterRestart: true)
        _ = send(launch(bootSession: bootB, lastBootSession: bootA), to: &bootedLate, at: monday("19:00"))
        XCTAssertFalse(bootedLate.isOn)
        XCTAssertEqual(bootedLate.state.lastOffReason, .schedule)
    }

    func testPickAfterACancelledPowerOffIsWhatRestores() {
        var cancelled = controller(stayOnAfterRestart: true)
        _ = send(.picked(.until(TimeOfDay(hour: 15, minute: 0)), readings()), to: &cancelled, at: monday("10:00"))
        _ = send(.willPowerOff(bootSession: bootA), to: &cancelled, at: monday("11:00"))

        var newEnd = cancelled
        _ = send(.picked(.minutes(30), readings()), to: &newEnd, at: monday("11:05"))
        var restoredNewEnd = controller(state: newEnd.state, stayOnAfterRestart: true)
        let newEndCommands = send(launch(bootSession: bootB, lastBootSession: bootA), to: &restoredNewEnd, at: monday("11:20"))

        XCTAssertTrue(newEndCommands.contains(.keepAwake))
        XCTAssertTrue(newEndCommands.contains(.armTimer(monday("11:35"))))

        var cleared = cancelled
        _ = send(.picked(.indefinitely, readings()), to: &cleared, at: monday("11:05"))
        var restoredCleared = controller(state: cleared.state, stayOnAfterRestart: true)
        let clearedCommands = send(launch(bootSession: bootB, lastBootSession: bootA), to: &restoredCleared, at: monday("16:00"))

        XCTAssertTrue(clearedCommands.contains(.keepAwake))
        XCTAssertTrue(clearedCommands.contains(.armTimer(nil)))
        XCTAssertNil(restoredCleared.state.timerEnd)
    }

    func testRestartWithoutStayOnStaysOff() {
        var before = controller()
        _ = send(.picked(.until(TimeOfDay(hour: 15, minute: 0)), readings()), to: &before, at: monday("10:00"))
        _ = send(.willPowerOff(bootSession: bootA), to: &before, at: monday("11:00"))

        var relaunched = controller(state: before.state)
        let commands = send(launch(bootSession: bootB, lastBootSession: bootA), to: &relaunched, at: monday("12:00"))

        XCTAssertFalse(commands.contains(.keepAwake))
        XCTAssertFalse(relaunched.isOn)
        XCTAssertNil(relaunched.state.powerOff)
    }

    func testLogoutDoesNotRestore() {
        var before = controller(stayOnAfterRestart: true)
        _ = send(.tapped(readings()), to: &before, at: monday("10:00"))
        _ = send(.willPowerOff(bootSession: bootA), to: &before, at: monday("11:00"))

        var relaunched = controller(state: before.state, stayOnAfterRestart: true)
        let commands = send(launch(bootSession: bootA, lastBootSession: bootA), to: &relaunched, at: monday("11:05"))

        XCTAssertFalse(commands.contains(.keepAwake))
        XCTAssertNil(relaunched.state.powerOff)
    }

    func testSwitchOffClearsPowerOffRecord() {
        var controller = controller(stayOnAfterRestart: true)
        _ = send(.tapped(readings()), to: &controller, at: monday("10:00"))
        _ = send(.willPowerOff(bootSession: bootA), to: &controller, at: monday("11:00"))
        XCTAssertNotNil(controller.state.powerOff)

        _ = send(.tapped(readings()), to: &controller, at: monday("11:01"))

        XCTAssertNil(controller.state.powerOff)
    }

    func testCrashShowsHelperRestored() {
        let saved = ControllerState(flagOn: true, guarded: true, origin: .manual)

        var crashed = controller(state: saved)
        let crashedCommands = send(launch(cleanQuit: false), to: &crashed, at: monday("10:00"))
        XCTAssertTrue(crashedCommands.contains(.notify(.turnedOff(.helperRestored))))
        XCTAssertEqual(crashed.state.lastOffReason, .helperRestored)
        XCTAssertFalse(crashed.isOn)

        var quit = controller(state: saved)
        let quitCommands = send(launch(cleanQuit: true), to: &quit, at: monday("10:00"))
        XCTAssertFalse(quitCommands.contains(.notify(.turnedOff(.helperRestored))))
    }

    func testWillTerminateSavesForTheCleanQuitMarker() {
        var controller = controller()

        XCTAssertEqual(send(.willTerminate, to: &controller, at: monday("10:00")), [.save])
    }
}

private extension Boundary {
    /// Fails the test unless this boundary is the one the test means.
    func checked(kind: Kind, date: Date) -> Boundary {
        XCTAssertEqual(self.kind, kind)
        XCTAssertEqual(self.date, date)
        return self
    }
}
