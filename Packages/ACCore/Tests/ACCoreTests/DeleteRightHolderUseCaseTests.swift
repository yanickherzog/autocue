@testable import ACCore
import XCTest

/// Covers `DeleteRightHolderUseCase.referenceLocations` — the pure guard-scan
/// half, exercised for all five reference sites per `ROADMAP.md` T3.3's
/// acceptance criteria. This is deliberately the only half tested at the
/// `ACCore` level: the repository-touching orchestration half
/// (`deletePerson`/`deleteLabel`) needs a `ProjectRepository` conformance to
/// call, and `CONTRIBUTING.md` §5 is explicit that `ACCore` tests should need
/// no mocks — that path is exercised instead in `ACTestSupportTests` against
/// the real `InMemoryProjectRepository` fake (`ROADMAP.md` T3.4), which is
/// exactly the point of that fake existing.
final class DeleteRightHolderUseCaseTests: XCTestCase {
    private static func makeProject(
        producer: Party,
        directorOrPrincipal: Party,
        declarant: Party,
        cues: [Cue] = []
    ) -> Project {
        Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            setup: Setup(
                title: "A Swiss Story",
                producer: [producer],
                directorOrPrincipal: [directorOrPrincipal],
                productionRuntime: MediaDuration(seconds: 5400),
                totalMusicRuntime: MediaDuration(seconds: 600),
                productionYear: 2026,
                containsAdditionalUndeclaredWorks: .no,
                productionTypes: [.documentaryFilm],
                declarant: declarant,
                declarationDate: Date(timeIntervalSince1970: 0)
            ),
            cues: cues
        )
    }

    private static func makeUnreferencedProject() -> Project {
        makeProject(producer: .person(UUID()), directorOrPrincipal: .person(UUID()), declarant: .person(UUID()))
    }

    func test_noReferencesAnywhere_returnsEmptyLocations() {
        let party = Party.person(UUID())
        let locations = DeleteRightHolderUseCase.referenceLocations(
            for: party,
            in: Self.makeUnreferencedProject(),
            settings: Settings()
        )
        XCTAssertTrue(locations.isEmpty)
    }

    func test_referencedAsSetupProducer_isReported() {
        let party = Party.person(UUID())
        let project = Self.makeProject(
            producer: party,
            directorOrPrincipal: .person(UUID()),
            declarant: .person(UUID())
        )

        let locations = DeleteRightHolderUseCase.referenceLocations(for: party, in: project, settings: Settings())

        XCTAssertEqual(locations, [.setupProducer])
    }

    func test_referencedAsSetupDirectorOrPrincipal_isReported() {
        let party = Party.person(UUID())
        let project = Self.makeProject(
            producer: .person(UUID()),
            directorOrPrincipal: party,
            declarant: .person(UUID())
        )

        let locations = DeleteRightHolderUseCase.referenceLocations(for: party, in: project, settings: Settings())

        XCTAssertEqual(locations, [.setupDirectorOrPrincipal])
    }

    func test_referencedAsSetupDeclarant_isReported() {
        let party = Party.person(UUID())
        let project = Self.makeProject(
            producer: .person(UUID()),
            directorOrPrincipal: .person(UUID()),
            declarant: party
        )

        let locations = DeleteRightHolderUseCase.referenceLocations(for: party, in: project, settings: Settings())

        XCTAssertEqual(locations, [.setupDeclarant])
    }

    func test_referencedAsSettingsDefaultDeclarant_isReported() {
        let party = Party.person(UUID())
        let settings = Settings(defaultDeclarant: party)

        let locations = DeleteRightHolderUseCase.referenceLocations(
            for: party,
            in: Self.makeUnreferencedProject(),
            settings: settings
        )

        XCTAssertEqual(locations, [.settingsDefaultDeclarant])
    }

    func test_referencedAsACueRightHolder_isReportedWithTheOwningCueID() {
        let party = Party.person(UUID())
        let rightHolder = CueRightHolder(
            party: party,
            role: .composer,
            performanceBroadcastShare: 100,
            mechanicalRightsShare: 100
        )
        let cue = Cue(
            title: "Alpine Theme",
            duration: MediaDuration(seconds: 120),
            rightHolders: [rightHolder],
            source: .manual
        )
        let project = Self.makeProject(
            producer: .person(UUID()),
            directorOrPrincipal: .person(UUID()),
            declarant: .person(UUID()),
            cues: [cue]
        )

        let locations = DeleteRightHolderUseCase.referenceLocations(for: party, in: project, settings: Settings())

        XCTAssertEqual(locations, [.cueRightHolder(cueID: cue.id)])
    }

    func test_referencedInMultipleLocationsAtOnce_reportsAllOfThem() {
        let party = Party.person(UUID())
        let rightHolder = CueRightHolder(
            party: party,
            role: .composer,
            performanceBroadcastShare: 100,
            mechanicalRightsShare: 100
        )
        let cue = Cue(
            title: "Alpine Theme",
            duration: MediaDuration(seconds: 120),
            rightHolders: [rightHolder],
            source: .manual
        )
        let project = Self.makeProject(
            producer: party,
            directorOrPrincipal: .person(UUID()),
            declarant: party,
            cues: [cue]
        )
        let settings = Settings(defaultDeclarant: party)

        let locations = DeleteRightHolderUseCase.referenceLocations(for: party, in: project, settings: settings)

        // PartyReferenceLocation is intentionally not Hashable (no real
        // Set/Dict use — CLAUDE.md's conformance policy), so order-independent
        // comparison here goes through `contains`, not `Set`.
        XCTAssertEqual(locations.count, 4)
        XCTAssertTrue(locations.contains(.setupProducer))
        XCTAssertTrue(locations.contains(.setupDeclarant))
        XCTAssertTrue(locations.contains(.settingsDefaultDeclarant))
        XCTAssertTrue(locations.contains(.cueRightHolder(cueID: cue.id)))
    }

    func test_labelPartyDoesNotFalselyMatchAPersonReferenceWithTheSameUnderlyingID() {
        // Party.person(id) and Party.label(id) with the same UUID must never
        // be treated as the same reference.
        let id = UUID()
        let project = Self.makeProject(
            producer: .person(id),
            directorOrPrincipal: .person(UUID()),
            declarant: .person(UUID())
        )

        let locations = DeleteRightHolderUseCase.referenceLocations(for: .label(id), in: project, settings: Settings())

        XCTAssertTrue(locations.isEmpty)
    }
}
