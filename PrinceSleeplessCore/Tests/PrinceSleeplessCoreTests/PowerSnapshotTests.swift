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
}
