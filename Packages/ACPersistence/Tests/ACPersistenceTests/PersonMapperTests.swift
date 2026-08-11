@testable import ACCore
@testable import ACPersistence
import XCTest

/// Direct coverage for `PersonMapper`'s `intendedRoles` round-trip —
/// `PersonIntendedRole.allCases` (individually and as a multi-role set) plus
/// the empty-set case, same "every case round-trips" convention
/// `SetupMapperTests`/`CueRightHolderMapperTests` already establish.
final class PersonMapperTests: XCTestCase {
    private func makePerson(intendedRoles: Set<PersonIntendedRole>) -> Person {
        Person(firstName: "Ada", lastName: "Lovelace", intendedRoles: intendedRoles)
    }

    func test_everyIntendedRoleCaseRoundTripsThroughPerson() throws {
        for role in PersonIntendedRole.allCases {
            let entity = PersonMapper.toEntity(makePerson(intendedRoles: [role]), order: 0)
            let roundTripped = try PersonMapper.toDomain(entity)
            XCTAssertEqual(roundTripped.intendedRoles, [role])
        }
    }

    func test_multipleSimultaneousRoles_roundTripExactly() throws {
        let roles: Set<PersonIntendedRole> = [.composer, .performer]
        let entity = PersonMapper.toEntity(makePerson(intendedRoles: roles), order: 0)
        let roundTripped = try PersonMapper.toDomain(entity)
        XCTAssertEqual(roundTripped.intendedRoles, roles)
    }

    func test_emptyIntendedRoles_roundTripsToEmptyNotAThrownError() throws {
        let entity = PersonMapper.toEntity(makePerson(intendedRoles: []), order: 0)
        XCTAssertEqual(entity.intendedRolesRawValues, [])
        XCTAssertEqual(try PersonMapper.toDomain(entity).intendedRoles, [])
    }

    func test_unknownIntendedRoleRawValue_throwsRatherThanCrashing() {
        let entity = PersonMapper.toEntity(makePerson(intendedRoles: []), order: 0)
        entity.intendedRolesRawValues = ["narrator"]
        XCTAssertThrowsError(try PersonMapper.toDomain(entity))
    }
}
