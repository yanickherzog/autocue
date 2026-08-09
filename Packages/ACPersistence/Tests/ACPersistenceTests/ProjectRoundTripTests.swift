@testable import ACCore
@testable import ACPersistence
import SwiftData
import XCTest

/// D4's core acceptance criterion: build a domain `Project` fixture, map to
/// entities, insert into a real in-memory `ModelContainer`, fetch back, map
/// to domain, assert `Equatable` equality — never asserting against a mock
/// of SwiftData (`ROADMAP.md` D4 Acceptance Criteria, `CONTRIBUTING.md` §5).
final class ProjectRoundTripTests: XCTestCase {
    func test_fullyPopulatedProjectRoundTripsExactly() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let original = ProjectFixture.make()

        context.insert(ProjectMapper.toEntity(original))
        try context.save()

        let fetchedEntities = try context.fetch(FetchDescriptor<ProjectEntity>())
        XCTAssertEqual(fetchedEntities.count, 1)

        let roundTripped = try ProjectMapper.toDomain(XCTUnwrap(fetchedEntities.first))
        XCTAssertEqual(roundTripped, original)
    }

    func test_minimalProjectRoundTripsExactly() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let original = ProjectFixture.makeMinimal()

        context.insert(ProjectMapper.toEntity(original))
        try context.save()

        let fetchedEntities = try context.fetch(FetchDescriptor<ProjectEntity>())
        let roundTripped = try ProjectMapper.toDomain(XCTUnwrap(fetchedEntities.first))
        XCTAssertEqual(roundTripped, original)
    }

    /// Guards specifically against silent `Decimal` precision loss on an
    /// uneven, exact-100%-summing split (SPEC.md §4.6) — the fixture's
    /// second cue already covers this, this test isolates it directly so a
    /// future regression here fails with an obviously-relevant name.
    func test_unevenDecimalSharesRoundTripExactly() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let original = ProjectFixture.make()

        context.insert(ProjectMapper.toEntity(original))
        try context.save()

        let fetchedEntities = try context.fetch(FetchDescriptor<ProjectEntity>())
        let roundTripped = try ProjectMapper.toDomain(XCTUnwrap(fetchedEntities.first))

        let originalShares = original.cues[1].rightHolders.map(\.performanceBroadcastShare)
        let roundTrippedShares = roundTripped.cues[1].rightHolders.map(\.performanceBroadcastShare)
        XCTAssertEqual(roundTrippedShares, originalShares)
        XCTAssertEqual(roundTrippedShares.reduce(0, +), Decimal(string: "100.00"))
    }

    /// `Project.cues`/`CueRightHolder`/`EmbeddedMarker` are domain-ordered
    /// arrays with no stored order field (SPEC.md §4.1) — SwiftData gives no
    /// to-many fetch-order guarantee, so this specifically proves the
    /// persistence-only `order` columns actually restore array order, not
    /// just that the same elements are present.
    func test_arrayOrderSurvivesRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let original = ProjectFixture.make()

        context.insert(ProjectMapper.toEntity(original))
        try context.save()

        let fetchedEntities = try context.fetch(FetchDescriptor<ProjectEntity>())
        let roundTripped = try ProjectMapper.toDomain(XCTUnwrap(fetchedEntities.first))

        XCTAssertEqual(roundTripped.cues.map(\.title), original.cues.map(\.title))
        XCTAssertEqual(
            roundTripped.audioAsset?.embeddedMarkers.map(\.label),
            original.audioAsset?.embeddedMarkers.map(\.label)
        )
    }
}
