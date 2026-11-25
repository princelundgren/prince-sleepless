import XCTest
@testable import PrinceSleeplessCore

final class ListenerRequirementTests: XCTestCase {
    func testDeveloperIDRequirement() {
        XCTAssertEqual(
            ListenerRequirement.string(team: "ABCDE12345", developerID: true),
            #"identifier "com.princelundgren.princesleepless" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "ABCDE12345""#
        )
    }

    func testDevelopmentRequirementDropsOnlyTheDeveloperIDFields() {
        XCTAssertEqual(
            ListenerRequirement.string(team: "ABCDE12345", developerID: false),
            #"identifier "com.princelundgren.princesleepless" and anchor apple generic and certificate leaf[subject.OU] = "ABCDE12345""#
        )
    }
}
