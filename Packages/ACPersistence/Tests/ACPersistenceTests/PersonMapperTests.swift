@testable import ACCore
@testable import ACPersistence
import XCTest

/// Direct coverage for `PersonMapper`'s `intendedRole` round-trip —
/// `PersonIntendedRole.allCases` plus the `nil` case, same "every case
/// round-trips" convention `SetupMapperTests`/`CueRightHolderMapperTests`
/// already establish.
final class PersonMapperTests: XCTestCase {
    private func makePerson(intendedRole: PersonIntendedRole?) -> Person {
        Person(firstName: "Ada", lastName: "Lovelace", intendedRole: intendedRole)
    }

    func test_everyIntendedRoleCaseRoundTripsThroughPerson() throws {
        for role in PersonIntendedRole.allCases {
            let entity = PersonMapper.toEntity(makePerson(intendedRole: role), order: 0)
            let roundTripped = try PersonMapper.toDomain(entity)
            XCTAssertEqual(roundTripped.intendedRole, role)
        }
    }

    func test_nilIntendedRole_roundTripsToNilNotAThrownError() throws {
        let entity = PersonMapper.toEntity(makePerson(intendedRole: nil), order: 0)
        XCTAssertNil(entity.intendedRoleRawValue)
        XCTAssertNil(try PersonMapper.toDomain(entity).intendedRole)
    }

    func test_unknownIntendedRoleRawValue_throwsRatherThanCrashing() {
        let entity = PersonMapper.toEntity(makePerson(intendedRole: nil), order: 0)
        entity.intendedRoleRawValue = "narrator"
        XCTAssertThrowsError(try PersonMapper.toDomain(entity))
    }
}
