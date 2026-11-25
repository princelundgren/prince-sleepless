import XCTest
@testable import PrinceSleeplessCore

final class ControllerSwitchingTests: XCTestCase {
    private let charger = PowerSnapshot(charge: 80, onBattery: false, minutesToEmpty: nil)
    private let bootA = UUID()
    private let bootB = UUID()

    private func battery(_ charge: Int, minutesToEmpty: Int? = nil) -> PowerSnapshot {
        PowerSnapshot(charge: charge, onBattery: true, minutesToEmpty: minutesToEmpty)
    }

    private func readings(_ power: PowerSnapshot?, lowPowerMode: Bool = false) -> Readings {
        Readings(power: power, lowPowerMode: lowPowerMode)
    }

    private func controller(helper: HelperStatus = .enabled, preferences: Preferences = Preferences()) -> Controller {
        Controller(state: ControllerState(), preferences: preferences, helper: helper)
    }

    private func switchedOn(_ power: PowerSnapshot? = nil, preferences: Preferences = Preferences()) -> Controller {
        var controller = controller(preferences: preferences)
        _ = controller.send(.tapped(readings(power ?? charger)))
        _ = controller.send(.helperReplied(ok: true))
        XCTAssertTrue(controller.isProtected)
        return controller
    }

    private func launch(
        flagOn: Bool,
        buildChanged: Bool = false,
        lastBootSession: UUID?,
        readings: Readings? = nil
    ) -> Event {
        .launched(LaunchInfo(
            flagOn: flagOn,
            buildChanged: buildChanged,
            bootSession: bootA,
            lastBootSession: lastBootSession,
            cleanQuit: true,
            readings: readings ?? self.readings(charger)))
    }

    private func count(_ notice: Notice, in commands: [Command]) -> Int {
        commands.filter { $0 == .notify(notice) }.count
    }

    func testTapWithHelperNotRegisteredRegistersFirst() {
        var controller = controller(helper: .notRegistered)

        let first = controller.send(.tapped(readings(charger)))

        XCTAssertTrue(first.contains(.registerHelper))
        XCTAssertFalse(first.contains(.keepAwake))
        XCTAssertFalse(controller.isOn)

        _ = controller.send(.helper(.enabled))
        let second = controller.send(.tapped(readings(charger)))

        XCTAssertTrue(second.contains(.keepAwake))
        XCTAssertTrue(second.contains(.observePower(true)))
        XCTAssertTrue(second.contains(.holdActivity(true)))
    }

    func testTapWithHelperAwaitingApprovalOpensLoginItems() {
        var controller = controller(helper: .requiresApproval)

        let commands = controller.send(.tapped(readings(charger)))

        XCTAssertEqual(commands, [.openLoginItems])
    }

    func testAdoptedFlagBeforeApprovalShowsUnprotected() {
        var controller = controller(helper: .notRegistered)

        let launched = controller.send(launch(flagOn: true, lastBootSession: bootA))

        XCTAssertTrue(controller.isOn)
        XCTAssertFalse(controller.isProtected)
        XCTAssertFalse(launched.contains(.registerHelper))
        XCTAssertFalse(launched.contains(.keepAwake))
        XCTAssertTrue(controller.send(.tapped(readings(charger))).contains(.registerHelper))
    }

    func testSavedGuardIsDroppedWhenAdoptedWithoutApproval() {
        let saved = ControllerState(flagOn: true, guarded: true, origin: .manual, lastPower: charger)
        var controller = Controller(state: saved, preferences: Preferences(), helper: .requiresApproval)

        _ = controller.send(launch(flagOn: true, lastBootSession: bootA))

        XCTAssertTrue(controller.isOn)
        XCTAssertFalse(controller.isProtected)
    }

    func testInitClampsPreferences() {
        let controller = Controller(state: ControllerState(), preferences: Preferences(floor: 0), helper: .enabled)

        XCTAssertEqual(controller.preferences.floor, 5)
    }

    func testApprovalWhileFlagIsOnGuardsIt() {
        var controller = controller(helper: .requiresApproval)
        _ = controller.send(launch(flagOn: true, lastBootSession: bootA))

        let commands = controller.send(.helper(.enabled))

        XCTAssertTrue(commands.contains(.keepAwake))
        XCTAssertTrue(commands.contains(.observePower(true)))
        XCTAssertTrue(controller.isProtected)
    }

    func testFlagReadOnWhileOffAdoptsAndGuards() {
        var controller = controller()

        let commands = controller.send(.flagRead(true))

        XCTAssertTrue(commands.contains(.keepAwake))
        XCTAssertTrue(commands.contains(.observePower(true)))
        XCTAssertEqual(controller.state.origin, .adopted)
        XCTAssertNil(controller.state.timerEnd)
        XCTAssertTrue(controller.isProtected)
    }

    func testFlagReadAdoptionChecksBatteryAtOnce() {
        var controller = controller()

        XCTAssertTrue(controller.send(.flagRead(true)).contains(.armBatteryCheck(0)))
        XCTAssertTrue(controller.send(.batteryCheckDue(battery(15))).contains(.allowSleep))
    }

    func testApprovalAdoptionChecksBatteryAtOnce() {
        var controller = controller(helper: .requiresApproval)
        _ = controller.send(launch(flagOn: true, lastBootSession: bootA))

        XCTAssertTrue(controller.send(.helper(.enabled)).contains(.armBatteryCheck(0)))
        XCTAssertTrue(controller.send(.batteryCheckDue(battery(15))).contains(.allowSleep))
    }

    func testAdoptedFlagUnderFloorTurnsOff() {
        var controller = controller()

        let commands = controller.send(launch(flagOn: true, lastBootSession: bootA, readings: readings(battery(15))))

        XCTAssertTrue(commands.contains(.allowSleep))
        XCTAssertEqual(count(.turnedOff(.battery(charge: 15)), in: commands), 1)
        XCTAssertFalse(controller.isOn)
    }

    func testFlagFoundOnInNewBootSessionIsCleared() {
        var controller = controller()

        let commands = controller.send(launch(flagOn: true, lastBootSession: bootB))

        XCTAssertTrue(commands.contains(.allowSleep))
        XCTAssertFalse(commands.contains(.keepAwake))
        XCTAssertEqual(controller.state.lastOffReason, .staleAfterBoot)
        XCTAssertFalse(controller.isOn)
    }

    func testFlagFoundOnAtFirstLaunchIsAdopted() {
        var controller = controller()

        let commands = controller.send(launch(flagOn: true, lastBootSession: nil))

        XCTAssertTrue(commands.contains(.keepAwake))
        XCTAssertFalse(commands.contains(.allowSleep))
    }

    func testStaleFlagWithHelperNotApprovedIsNotSentToTheHelper() {
        var controller = controller(helper: .notRegistered)

        let commands = controller.send(launch(flagOn: true, lastBootSession: bootB))

        XCTAssertFalse(commands.contains(.allowSleep))
        XCTAssertTrue(controller.isOn)
        XCTAssertFalse(controller.isProtected)
    }

    func testFlagReadOffWhileOnShowsOff() {
        var controller = switchedOn()

        let commands = controller.send(.flagRead(false))

        XCTAssertFalse(controller.isOn)
        XCTAssertTrue(commands.contains(.observePower(false)))
        XCTAssertTrue(commands.contains(.holdActivity(false)))
        XCTAssertFalse(commands.contains(.allowSleep))
    }

    func testTapWhileOnAllowsSleepAndRecordsUser() {
        var controller = switchedOn()
        controller.state.powerOff = PowerOffRecord(bootSession: bootA, timerEnd: nil)

        let commands = controller.send(.tapped(readings(charger)))

        XCTAssertTrue(commands.contains(.allowSleep))
        XCTAssertEqual(controller.state.lastOffReason, .user)
        XCTAssertNil(controller.state.powerOff)
        XCTAssertFalse(controller.isOn)
    }

    func testSwitchOnRefusedUnderFloor() {
        var controller = controller()

        let commands = controller.send(.tapped(readings(battery(15))))

        XCTAssertFalse(commands.contains(.keepAwake))
        XCTAssertEqual(controller.state.lastOffReason, .battery(charge: 15))
        XCTAssertFalse(controller.isOn)
    }

    func testManualSwitchOnWorksDuringLowPowerMode() {
        var controller = controller()

        let commands = controller.send(.tapped(readings(battery(80), lowPowerMode: true)))

        XCTAssertTrue(commands.contains(.keepAwake))
        XCTAssertTrue(controller.isOn)
    }

    func testFloorTurnsOffAndStaysOffOnCharger() {
        var controller = switchedOn(battery(50))

        let check = controller.send(.batteryCheckDue(battery(20)))

        XCTAssertTrue(check.contains(.allowSleep))
        XCTAssertTrue(check.contains(.notify(.turnedOff(.battery(charge: 20)))))
        XCTAssertFalse(controller.send(.power(charger)).contains(.keepAwake))
        XCTAssertFalse(controller.isOn)
    }

    func testUnplugWithLowPowerModeNotifiesOnceInEitherOrder() {
        var powerFirst = switchedOn()
        let powerFirstCommands = powerFirst.send(.power(battery(80))) + powerFirst.send(.lowPowerMode(true))

        var lowPowerModeFirst = switchedOn()
        let lowPowerModeFirstCommands = lowPowerModeFirst.send(.lowPowerMode(true)) + lowPowerModeFirst.send(.power(battery(80)))

        XCTAssertEqual(count(.turnedOff(.lowPowerMode), in: powerFirstCommands), 1)
        XCTAssertEqual(count(.turnedOff(.lowPowerMode), in: lowPowerModeFirstCommands), 1)
        XCTAssertFalse(powerFirst.isOn)
        XCTAssertFalse(lowPowerModeFirst.isOn)
    }

    func testOnBatteryArmsSpacedCheck() {
        var controller = switchedOn()

        XCTAssertTrue(controller.send(.power(battery(80, minutesToEmpty: 240))).contains(.armBatteryCheck(5400)))
        XCTAssertTrue(controller.send(.power(charger)).contains(.armBatteryCheck(nil)))
    }

    func testRaisingFloorWhileOnBatteryTurnsOff() {
        var controller = switchedOn(battery(30))

        let commands = controller.send(.preferencesChanged(Preferences(floor: 30)))

        XCTAssertTrue(commands.contains(.allowSleep))
        XCTAssertEqual(count(.turnedOff(.battery(charge: 30)), in: commands), 1)
    }

    func testHelperFailureShowsCouldNotChange() {
        var controller = controller()
        _ = controller.send(.tapped(readings(charger)))

        let commands = controller.send(.helperReplied(ok: false))

        XCTAssertTrue(commands.contains(.notify(.couldNotChange)))
        XCTAssertFalse(controller.isOn)
    }

    func testHelperFailureOnAdoptedFlagLeavesItOnUnprotected() {
        var controller = controller()
        _ = controller.send(.flagRead(true))

        let commands = controller.send(.helperReplied(ok: false))

        XCTAssertTrue(commands.contains(.notify(.couldNotChange)))
        XCTAssertTrue(controller.isOn)
        XCTAssertFalse(controller.isProtected)
        XCTAssertEqual(controller.send(.flagRead(true)), [])
    }

    func testFailedSwitchOffIsAdoptedAtTheNextFlagRead() {
        var controller = switchedOn()
        XCTAssertTrue(controller.send(.tapped(readings(charger))).contains(.allowSleep))

        XCTAssertTrue(controller.send(.helperReplied(ok: false)).contains(.notify(.couldNotChange)))
        let read = controller.send(.flagRead(true))

        XCTAssertTrue(read.contains(.keepAwake))
        XCTAssertTrue(controller.isProtected)
        XCTAssertEqual(controller.state.origin, .adopted)
    }

    func testBuildChangedReregistersOnlyWhileOff() {
        var off = controller()
        XCTAssertTrue(off.send(launch(flagOn: false, buildChanged: true, lastBootSession: bootA)).contains(.reregisterHelper))

        var on = controller()
        let launched = on.send(launch(flagOn: true, buildChanged: true, lastBootSession: bootA))
        XCTAssertFalse(launched.contains(.reregisterHelper))
        XCTAssertTrue(on.state.reregisterPending)

        XCTAssertTrue(on.send(.tapped(readings(charger))).contains(.reregisterHelper))
        XCTAssertFalse(on.state.reregisterPending)
    }

    func testBuildChangedWithHelperNotRegisteredRegistersNothing() {
        var controller = controller(helper: .notRegistered)

        let commands = controller.send(launch(flagOn: false, buildChanged: true, lastBootSession: bootA))

        XCTAssertFalse(commands.contains(.reregisterHelper))
        XCTAssertFalse(commands.contains(.registerHelper))
    }

    func testUpdateWaitsWhileOn() {
        var on = switchedOn()
        XCTAssertFalse(on.send(.updateReady).contains(.installUpdate))
        XCTAssertTrue(on.send(.tapped(readings(charger))).contains(.installUpdate))
        XCTAssertFalse(on.state.updateWaiting)

        var off = controller()
        XCTAssertTrue(off.send(.updateReady).contains(.installUpdate))
    }

    func testLaunchForgetsAnUpdateTheLastRunWaitedFor() {
        var controller = Controller(state: ControllerState(updateWaiting: true), preferences: Preferences(), helper: .enabled)

        let commands = controller.send(launch(flagOn: false, lastBootSession: bootA))

        XCTAssertFalse(commands.contains(.installUpdate))
        XCTAssertFalse(controller.state.updateWaiting)
    }

    func testNotificationActionIsExplicit() {
        var controller = switchedOn()

        let commands = controller.send(.notificationAction(turnOn: true, readings(charger)))

        XCTAssertFalse(commands.contains(.allowSleep))
        XCTAssertTrue(controller.isOn)
    }

    func testPreferencesAreClamped() {
        var controller = controller()

        _ = controller.send(.preferencesChanged(Preferences(floor: 0)))
        XCTAssertEqual(controller.preferences.floor, 5)

        let commands = controller.send(.preferencesChanged(Preferences(stayOnAfterRestart: true)))
        XCTAssertTrue(commands.contains(.setLaunchAtLogin(true)))
    }

    func testClampingKeepsFloorStepsAndScheduleTimesInRange() {
        XCTAssertEqual(Preferences(floor: 23).clamped().floor, 25)
        XCTAssertEqual(Preferences(floor: 22).clamped().floor, 20)
        XCTAssertEqual(Preferences(floor: 90).clamped().floor, 50)
        XCTAssertEqual(Preferences(floor: 5).clamped().floor, 5)
        XCTAssertEqual(Preferences(floor: 50).clamped().floor, 50)
        XCTAssertEqual(Preferences(floor: .max).clamped().floor, 50)
        XCTAssertEqual(Preferences(floor: .min).clamped().floor, 5)
        XCTAssertEqual(TimeOfDay(hour: .max, minute: .min).clamped(), TimeOfDay(hour: 23, minute: 0))

        let schedule = ScheduleWindow(
            start: TimeOfDay(hour: 25, minute: 70),
            end: TimeOfDay(hour: -1, minute: -5),
            weekdays: [2],
            mode: .automatic)
        let clamped = Preferences(schedule: schedule).clamped().schedule

        XCTAssertEqual(clamped?.start, TimeOfDay(hour: 23, minute: 59))
        XCTAssertEqual(clamped?.end, TimeOfDay(hour: 0, minute: 0))
    }

    func testPickedDurationOutOfRangeIsRefused() {
        for duration in [KeepAwakeDuration.minutes(0), .minutes(-5), .until(TimeOfDay(hour: 24, minute: 0)), .until(TimeOfDay(hour: 8, minute: 60))] {
            var controller = controller()

            XCTAssertEqual(controller.send(.picked(duration, readings(charger))), [], "\(duration)")
            XCTAssertEqual(controller.state, ControllerState(), "\(duration)")
        }

        var controller = controller()
        XCTAssertTrue(controller.send(.picked(.minutes(1), readings(charger))).contains(.keepAwake))
    }

    func testStateChangesEndWithSave() {
        var controller = controller()

        XCTAssertEqual(controller.send(.tapped(readings(charger))).last, .save)
        XCTAssertEqual(controller.send(.helperReplied(ok: true)), [])
    }
}

private extension Controller {
    mutating func send(_ event: Event) -> [Command] {
        handle(event, now: Date(timeIntervalSince1970: 1_800_000_000), calendar: Calendar(identifier: .gregorian))
    }
}
