import IOKit.ps
import XCTest
@testable import PrinceSleeplessCore

final class PowerSnapshotTests: XCTestCase {
    func testRoundTripsThroughCodable() throws {
        for minutes in [nil, 90] as [Int?] {
            let snapshot = PowerSnapshot(charge: 80, onBattery: true, minutesToEmpty: minutes)
            let data = try JSONEncoder().encode(snapshot)
            XCTAssertEqual(try JSONDecoder().decode(PowerSnapshot.self, from: data), snapshot, "minutesToEmpty: \(String(describing: minutes))")
        }
    }

    private func battery(
        current: Int = 80,
        max: Int = 100,
        state: String = kIOPSBatteryPowerValue,
        timeToEmpty: Int? = 240,
        type: String = kIOPSInternalBatteryType,
        present: Bool = true
    ) -> [String: Any] {
        var description: [String: Any] = [
            kIOPSTypeKey: type,
            kIOPSIsPresentKey: present,
            kIOPSCurrentCapacityKey: current,
            kIOPSMaxCapacityKey: max,
            kIOPSPowerSourceStateKey: state,
        ]
        description[kIOPSTimeToEmptyKey] = timeToEmpty
        return description
    }

    func testReadsTheInternalBatteryOnBattery() {
        XCTAssertEqual(
            PowerSnapshot.internalBattery(in: [battery()]),
            PowerSnapshot(charge: 80, onBattery: true, minutesToEmpty: 240))
    }

    func testOnTheChargerIsNotOnBattery() {
        XCTAssertEqual(PowerSnapshot.internalBattery(in: [battery(state: kIOPSACPowerValue)])?.onBattery, false)
    }

    func testChargeIsCurrentOverMaxRounded() {
        XCTAssertEqual(PowerSnapshot.internalBattery(in: [battery(current: 4_150, max: 5_000)])?.charge, 83)
        XCTAssertEqual(PowerSnapshot.internalBattery(in: [battery(current: 2, max: 3)])?.charge, 67)
    }

    func testStillEstimatingHasNoTimeToEmpty() {
        XCTAssertNil(PowerSnapshot.internalBattery(in: [battery(timeToEmpty: -1)])?.minutesToEmpty)
        XCTAssertNil(PowerSnapshot.internalBattery(in: [battery(timeToEmpty: nil)])?.minutesToEmpty)
        XCTAssertEqual(PowerSnapshot.internalBattery(in: [battery(timeToEmpty: 0)])?.minutesToEmpty, 0)
    }

    func testSkipsAUPSAndAnAbsentBattery() {
        let ups = battery(current: 10, type: kIOPSUPSType)
        let absent = battery(current: 20, present: false)

        XCTAssertNil(PowerSnapshot.internalBattery(in: [ups, absent]))
        XCTAssertEqual(PowerSnapshot.internalBattery(in: [ups, absent, battery(current: 55)])?.charge, 55)
    }

    func testNoBatteryOrNoCapacityIsNil() {
        XCTAssertNil(PowerSnapshot.internalBattery(in: []))
        XCTAssertNil(PowerSnapshot.internalBattery(in: [battery(max: 0)]))
    }
}
