@testable import ACCore
import XCTest

final class CueRightHolderTests: XCTestCase {
    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_differingParty_makesRightHoldersUnequal() {
        let first = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let second = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        XCTAssertNotEqual(first, second)
    }

    func test_attachmentFlags_defaultToFalseWhenOmitted() {
        let rightHolder = CueRightHolder(
            party: .label(UUID()), role: .publisher, performanceBroadcastShare: 50, mechanicalRightsShare: 50
        )

        XCTAssertFalse(rightHolder.publishingContractAttached)
        XCTAssertFalse(rightHolder.arrangementAuthorizationAttached)
    }

    func test_fieldsArePreservedExactlyAsInitialized() throws {
        let party = Party.label(UUID())
        // Decimal(string:), not a float literal — a Decimal float literal is
        // converted via Double internally and isn't exact for values like
        // 33.33 (SPEC.md §4.6's whole rationale for choosing Decimal over
        // Double depends on constructing it this way).
        let performanceBroadcastShare = try XCTUnwrap(Decimal(string: "33.33"))
        let mechanicalRightsShare = try XCTUnwrap(Decimal(string: "66.67"))
        let rightHolder = CueRightHolder(
            party: party,
            role: .arranger,
            performanceBroadcastShare: performanceBroadcastShare,
            mechanicalRightsShare: mechanicalRightsShare,
            publishingContractAttached: true,
            arrangementAuthorizationAttached: true
        )

        XCTAssertEqual(rightHolder.party, party)
        XCTAssertEqual(rightHolder.role, .arranger)
        XCTAssertEqual(rightHolder.performanceBroadcastShare, performanceBroadcastShare)
        XCTAssertEqual(rightHolder.mechanicalRightsShare, mechanicalRightsShare)
        XCTAssertTrue(rightHolder.publishingContractAttached)
        XCTAssertTrue(rightHolder.arrangementAuthorizationAttached)
    }
}

final class CueRightHolderRoleTests: XCTestCase {
    func test_allFiveRolesAreDistinct() {
        let cases: [CueRightHolderRole] = [.composer, .author, .arranger, .publisher, .performer]
        for (leftIndex, left) in cases.enumerated() {
            for right in cases[(leftIndex + 1)...] {
                XCTAssertNotEqual(left, right)
            }
        }
    }

    func test_allCasesIncludesAllFiveRoles() {
        XCTAssertEqual(CueRightHolderRole.allCases.count, 5)
    }
}
