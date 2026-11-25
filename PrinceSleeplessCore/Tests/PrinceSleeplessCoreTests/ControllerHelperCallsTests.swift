import XCTest
import PrinceSleeplessCore

final class ControllerHelperCallsTests: XCTestCase {
    private let charger = Readings(
        power: PowerSnapshot(charge: 80, onBattery: false, minutesToEmpty: nil),
        lowPowerMode: false)

    private func switchedOn() -> Controller {
        var controller = Controller(state: ControllerState(), preferences: Preferences(), helper: .enabled)
        _ = controller.send(.tapped(charger))
        _ = controller.send(.helperReplied(ok: true))
        XCTAssertTrue(controller.isProtected)
        return controller
    }

    // MARK: Flag reads while a call is outstanding

    func testFlagReadBetweenSwitchOnAndSwitchOffRepliesIsIgnored() {
        var controller = Controller(state: ControllerState(), preferences: Preferences(), helper: .enabled)
        XCTAssertTrue(controller.send(.tapped(charger)).contains(.keepAwake))
        XCTAssertTrue(controller.send(.tapped(charger)).contains(.allowSleep))
        _ = controller.send(.helperReplied(ok: true))

        XCTAssertEqual(controller.send(.flagRead(true)), [])
        XCTAssertFalse(controller.isOn)
    }

    func testFlagReadAfterTheLastReplyCounts() {
        var controller = Controller(state: ControllerState(), preferences: Preferences(), helper: .enabled)
        _ = controller.send(.tapped(charger))
        XCTAssertEqual(controller.send(.flagRead(false)), [])
        XCTAssertTrue(controller.isOn)

        _ = controller.send(.helperReplied(ok: true))
        _ = controller.send(.flagRead(false))

        XCTAssertFalse(controller.isOn)
    }

    // MARK: Interruption

    func testInterruptionWhileProtectedReguards() {
        var controller = switchedOn()

        XCTAssertEqual(controller.send(.helperInterrupted), [.reguard])
    }

    func testInterruptionWhileUnguardedDoesNothing() {
        var off = Controller(state: ControllerState(), preferences: Preferences(), helper: .enabled)
        XCTAssertEqual(off.send(.helperInterrupted), [])

        var unapproved = Controller(state: ControllerState(), preferences: Preferences(), helper: .requiresApproval)
        _ = unapproved.send(.flagRead(true))
        XCTAssertTrue(unapproved.isOn)
        XCTAssertEqual(unapproved.send(.helperInterrupted), [])
    }

    func testInterruptionAfterAFailedSwitchOnDoesNotReguard() {
        var controller = Controller(state: ControllerState(), preferences: Preferences(), helper: .enabled)
        _ = controller.send(.tapped(charger))
        _ = controller.send(.helperReplied(ok: false))

        XCTAssertEqual(controller.send(.helperInterrupted), [])
        XCTAssertFalse(controller.isOn)
    }

    func testInterruptionAfterAFailedAdoptionDoesNotReguard() {
        var controller = Controller(state: ControllerState(), preferences: Preferences(), helper: .enabled)
        _ = controller.send(.flagRead(true))
        _ = controller.send(.helperReplied(ok: false))

        XCTAssertEqual(controller.send(.helperInterrupted), [])
        XCTAssertTrue(controller.isOn)
        XCTAssertFalse(controller.isProtected)
    }

    func testFlagReadDuringAReguardIsIgnored() {
        var controller = switchedOn()
        _ = controller.send(.helperInterrupted)

        XCTAssertEqual(controller.send(.flagRead(false)), [])
        XCTAssertTrue(controller.isProtected)

        _ = controller.send(.helperReplied(ok: true))
        _ = controller.send(.flagRead(false))
        XCTAssertFalse(controller.isOn)
    }

    // MARK: A lost guard

    func testGuardLostKeepsTheRunOnUnguarded() {
        var controller = Controller(state: ControllerState(), preferences: Preferences(), helper: .enabled)
        _ = controller.send(.picked(.minutes(30), charger))
        _ = controller.send(.helperReplied(ok: true))
        let timerEnd = controller.state.timerEnd
        _ = controller.send(.helperInterrupted)

        let commands = controller.send(.guardLost)

        XCTAssertEqual(commands, [
            .observePower(false), .holdActivity(false), .armBatteryCheck(nil), .notify(.couldNotChange), .save,
        ])
        XCTAssertTrue(controller.isOn)
        XCTAssertFalse(controller.isProtected)
        XCTAssertEqual(controller.state.origin, .manualWithTimer)
        XCTAssertNotNil(timerEnd)
        XCTAssertEqual(controller.state.timerEnd, timerEnd)
    }

    func testGuardLostEndsTheReguardsCall() {
        var controller = switchedOn()
        _ = controller.send(.helperInterrupted)
        _ = controller.send(.guardLost)

        _ = controller.send(.flagRead(false))

        XCTAssertFalse(controller.isOn)
    }

    func testGuardLostAfterASwitchOffChangesNothing() {
        var controller = switchedOn()
        _ = controller.send(.helperInterrupted)
        _ = controller.send(.tapped(charger))

        XCTAssertEqual(controller.send(.guardLost), [])
        XCTAssertFalse(controller.isOn)
    }

    func testHelperEnabledAfterALostGuardReguardsKeepingTheRun() {
        var controller = Controller(state: ControllerState(), preferences: Preferences(), helper: .enabled)
        _ = controller.send(.picked(.minutes(30), charger))
        _ = controller.send(.helperReplied(ok: true))
        let timerEnd = controller.state.timerEnd
        _ = controller.send(.helperInterrupted)
        _ = controller.send(.guardLost)

        let commands = controller.send(.helper(.enabled))

        XCTAssertTrue(commands.contains(.reguard))
        XCTAssertFalse(commands.contains(.keepAwake))
        XCTAssertFalse(commands.contains(.armTimer(nil)))
        XCTAssertTrue(commands.contains(.observePower(true)))
        XCTAssertTrue(controller.isProtected)
        XCTAssertEqual(controller.state.origin, .manualWithTimer)
        XCTAssertNotNil(timerEnd)
        XCTAssertEqual(controller.state.timerEnd, timerEnd)
    }

    func testHelperEnabledOnAFlagFoundOnStillAdopts() {
        var controller = Controller(state: ControllerState(), preferences: Preferences(), helper: .requiresApproval)
        _ = controller.send(.flagRead(true))

        let commands = controller.send(.helper(.enabled))

        XCTAssertTrue(commands.contains(.keepAwake))
        XCTAssertFalse(commands.contains(.reguard))
        XCTAssertTrue(controller.isProtected)
        XCTAssertEqual(controller.state.origin, .adopted)
        XCTAssertNil(controller.state.timerEnd)
    }

    // MARK: An outdated helper

    func testOutdatedHelperWhileOffReregistersAtOnce() {
        var controller = Controller(state: ControllerState(), preferences: Preferences(), helper: .enabled)

        XCTAssertEqual(controller.send(.helperOutdated), [.reregisterHelper])
    }

    func testOutdatedHelperWhileOnReregistersAtSwitchOff() {
        var controller = switchedOn()
        _ = controller.send(.helperInterrupted)

        XCTAssertFalse(controller.send(.helperOutdated).contains(.reregisterHelper))
        XCTAssertFalse(controller.send(.guardLost).contains(.reregisterHelper))
        XCTAssertTrue(controller.send(.tapped(charger)).contains(.reregisterHelper))
    }

    func testOutdatedHelperOnASwitchOnReregistersOnceItFails() {
        var controller = Controller(state: ControllerState(), preferences: Preferences(), helper: .enabled)
        _ = controller.send(.tapped(charger))
        XCTAssertFalse(controller.send(.helperOutdated).contains(.reregisterHelper))

        let commands = controller.send(.helperReplied(ok: false))

        XCTAssertTrue(commands.contains(.reregisterHelper))
        XCTAssertTrue(commands.contains(.notify(.couldNotChange)))
        XCTAssertFalse(controller.isOn)
    }
}

private extension Controller {
    mutating func send(_ event: Event) -> [Command] {
        handle(event, now: Date(timeIntervalSince1970: 1_800_000_000), calendar: Calendar(identifier: .gregorian))
    }
}
