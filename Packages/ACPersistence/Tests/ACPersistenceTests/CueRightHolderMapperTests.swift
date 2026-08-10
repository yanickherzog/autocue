@testable import ACCore
@testable import ACPersistence
import XCTest

/// Direct coverage for `CueRightHolderMapper`'s `role`/`rawValue` round-trip
/// — specifically that every `CueRightHolderRole` case (including
/// `.performer`, added per `docs/DECISIONS.md`) survives, since the reverse
/// direction (`role(from:)`) is a `String`-match `switch` with
/// `default: throw`, not compiler-exhaustive the way a `switch` directly over
/// the enum is. `ProjectRoundTripTests` already exercises composer/publisher/
/// arranger/performer once each via the fixture; this test is what actually
/// proves every case works, matching `SetupMapperTests`'s own stated purpose
/// for its raw-value tables.
final class CueRightHolderMapperTests: XCTestCase {
    func test_everyRoleCaseRoundTripsThroughCueRightHolder() throws {
        for role in CueRightHolderRole.allCases {
            let rightHolder = CueRightHolder(
                party: .person(UUID()), role: role, performanceBroadcastShare: 0, mechanicalRightsShare: 0
            )
            let entity = CueRightHolderMapper.toEntity(rightHolder, order: 0)
            let roundTripped = try CueRightHolderMapper.toDomain(entity)
            XCTAssertEqual(roundTripped.role, role)
        }
    }

    func test_unknownRoleRawValue_throwsRatherThanCrashing() {
        let entity = CueRightHolderMapper.toEntity(
            CueRightHolder(
                party: .person(UUID()),
                role: .composer,
                performanceBroadcastShare: 0,
                mechanicalRightsShare: 0
            ),
            order: 0
        )
        entity.role = "narrator"
        XCTAssertThrowsError(try CueRightHolderMapper.toDomain(entity))
    }
}
