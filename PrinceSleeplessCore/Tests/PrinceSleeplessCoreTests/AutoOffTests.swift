import XCTest
@testable import PrinceSleeplessCore

final class AutoOffTests: XCTestCase {
    private func power(_ charge: Int, onBattery: Bool = true) -> PowerSnapshot {
        PowerSnapshot(charge: charge, onBattery: onBattery, minutesToEmpty: nil)
    }

    func testFloorStopsOnBattery() {
        func reason(_ snapshot: PowerSnapshot) -> OffReason? {
            AutoOff.reasonToStop(power: snapshot, lowPowerModeCameOn: false, floor: 20, lowPowerModeRule: true)
        }
        XCTAssertEqual(reason(power(20)), .battery(charge: 20))
        XCTAssertNil(reason(power(21)))
        XCTAssertNil(reason(power(5, onBattery: false)))
    }

    func testFloorWinsOverLowPowerModeWhenStopping() {
        XCTAssertEqual(
            AutoOff.reasonToStop(power: power(20), lowPowerModeCameOn: true, floor: 20, lowPowerModeRule: true),
            .battery(charge: 20))
    }

    func testLowPowerModeComingOnStops() {
        XCTAssertEqual(
            AutoOff.reasonToStop(power: power(80), lowPowerModeCameOn: true, floor: 20, lowPowerModeRule: true),
            .lowPowerMode)
        XCTAssertNil(
            AutoOff.reasonToStop(power: power(80), lowPowerModeCameOn: true, floor: 20, lowPowerModeRule: false))
        XCTAssertNil(
            AutoOff.reasonToStop(power: power(80, onBattery: false), lowPowerModeCameOn: true, floor: 20, lowPowerModeRule: true))
    }

    func testNoReadingYetDecidesNothing() {
        XCTAssertNil(AutoOff.reasonToStop(power: nil, lowPowerModeCameOn: true, floor: 20, lowPowerModeRule: true))
        XCTAssertNil(AutoOff.reasonToRefuse(power: nil, lowPowerMode: true, source: .schedule, floor: 20, lowPowerModeRule: true))
    }

    func testManualSwitchOnWinsOverLowPowerModeButNotFloor() {
        func refusal(_ source: SwitchOnSource, charge: Int) -> OffReason? {
            AutoOff.reasonToRefuse(power: power(charge), lowPowerMode: true, source: source, floor: 20, lowPowerModeRule: true)
        }
        XCTAssertNil(refusal(.manual, charge: 80))
        XCTAssertEqual(refusal(.schedule, charge: 80), .lowPowerMode)
        XCTAssertEqual(refusal(.restore, charge: 80), .lowPowerMode)
        XCTAssertEqual(refusal(.manual, charge: 15), .battery(charge: 15))
    }

    func testNothingIsRefusedOnTheCharger() {
        XCTAssertNil(
            AutoOff.reasonToRefuse(power: power(5, onBattery: false), lowPowerMode: true, source: .schedule, floor: 20, lowPowerModeRule: true))
    }

    func testLowPowerModeIsIgnoredWhenItsRuleIsOff() {
        XCTAssertNil(
            AutoOff.reasonToRefuse(power: power(80), lowPowerMode: true, source: .schedule, floor: 20, lowPowerModeRule: false))
    }
}
