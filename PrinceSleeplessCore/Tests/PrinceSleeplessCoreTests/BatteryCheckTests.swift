import XCTest
@testable import PrinceSleeplessCore

final class BatteryCheckTests: XCTestCase {
    private func snapshot(_ charge: Int, minutesToEmpty: Int?, onBattery: Bool = true) -> PowerSnapshot {
        PowerSnapshot(charge: charge, onBattery: onBattery, minutesToEmpty: minutesToEmpty)
    }

    func testNextCheckIsHalfTheTimeToFloor() {
        XCTAssertEqual(BatteryCheck.nextCheck(after: snapshot(80, minutesToEmpty: 240), floor: 20), 5_400)
    }

    func testNextCheckIsAtLeastAMinute() {
        XCTAssertEqual(BatteryCheck.nextCheck(after: snapshot(21, minutesToEmpty: 33), floor: 20), 60)
    }

    func testNextCheckWithUnknownEstimateIsThreeMinutes() {
        XCTAssertEqual(BatteryCheck.nextCheck(after: snapshot(80, minutesToEmpty: nil), floor: 20), 180)
    }

    func testAtOrUnderFloorChecksInAMinute() {
        XCTAssertEqual(BatteryCheck.nextCheck(after: snapshot(0, minutesToEmpty: 100), floor: 20), 60)
        XCTAssertEqual(BatteryCheck.nextCheck(after: snapshot(20, minutesToEmpty: nil), floor: 20), 60)
    }

    func testNoCheckOnCharger() {
        XCTAssertNil(BatteryCheck.nextCheck(after: snapshot(80, minutesToEmpty: 240, onBattery: false), floor: 20))
    }
}
