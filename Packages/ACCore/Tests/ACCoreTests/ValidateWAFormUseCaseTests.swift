@testable import ACCore
import XCTest

final class ValidateWAFormUseCaseTests: XCTestCase {
    private static func makeValidSetup() -> Setup {
        Setup(
            title: "A Swiss Story",
            producer: [.person(UUID())],
            directorOrPrincipal: [.person(UUID())],
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: MediaDuration(seconds: 600),
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: [.documentaryFilm],
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0)
        )
    }

    /// Exact, 2-decimal-scale shares that sum to precisely `100.00` for any
    /// `count` — naive `Decimal(100) / Decimal(count)` division (e.g. for
    /// `count: 3`) repeats and truncates at `Decimal`'s own precision limit,
    /// producing a total like `99.999999999999999999999999999999999999`,
    /// not exactly `100` — which `ValidateCueRightHolderSharesUseCase`'s
    /// real, zero-tolerance exact-equality check (SPEC.md §4.6) correctly
    /// flags as a share-sum issue. Distributing whole hundredths-of-a-percent
    /// (`10000` units = `100.00%`) and handing any remainder to the first
    /// `count % 10000`-many holders keeps every test's `Cue` genuinely valid
    /// on every other axis, isolating the one issue each test actually means
    /// to exercise.
    private static func evenShares(_ count: Int) -> [Decimal] {
        let totalUnits = 10000
        let base = totalUnits / count
        let remainder = totalUnits % count
        return (0 ..< count).map { index in
            let units = base + (index < remainder ? 1 : 0)
            return Decimal(units) / Decimal(100)
        }
    }

    private static func makeValidCue(rightHolderCount: Int = 1) -> Cue {
        let shares = Self.evenShares(rightHolderCount)
        let rightHolders = shares.map { share in
            CueRightHolder(
                party: .person(UUID()),
                role: .composer,
                performanceBroadcastShare: share,
                mechanicalRightsShare: share
            )
        }
        return Cue(title: "Theme", duration: MediaDuration(seconds: 60), rightHolders: rightHolders, source: .manual)
    }

    private static func makeProject(cues: [Cue]) -> Project {
        Project(name: "Reel One", createdAt: Date(), updatedAt: Date(), setup: makeValidSetup(), cues: cues)
    }

    // MARK: - Generic cue-sheet issues are reused, not re-derived

    func test_fullyValidProject_reportsNoIssues() {
        let project = Self.makeProject(cues: [Self.makeValidCue()])
        XCTAssertEqual(
            ValidateWAFormUseCase.validate(project, continuationPagesAvailable: 5),
            []
        )
    }

    func test_genericCueSheetIssue_wrappedInCueSheetIssueCase() {
        let project = Self.makeProject(cues: [])
        let projectMissingDeclarant = Project(
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            setup: Setup(
                title: project.setup.title,
                producer: project.setup.producer,
                directorOrPrincipal: project.setup.directorOrPrincipal,
                productionRuntime: project.setup.productionRuntime,
                totalMusicRuntime: project.setup.totalMusicRuntime,
                productionYear: project.setup.productionYear,
                containsAdditionalUndeclaredWorks: project.setup.containsAdditionalUndeclaredWorks,
                productionTypes: project.setup.productionTypes,
                declarant: nil,
                declarationDate: project.setup.declarationDate
            ),
            cues: []
        )

        XCTAssertEqual(
            ValidateWAFormUseCase.validate(projectMissingDeclarant, continuationPagesAvailable: 5),
            [.cueSheetIssue(.missingSetupField(.declarant))]
        )
    }

    // MARK: - Right-holder capacity (3 non-.performer rows per work)

    func test_cueWithThreeRightHolders_atCapacity_reportsNoIssue() {
        let cue = Self.makeValidCue(rightHolderCount: 3)
        let project = Self.makeProject(cues: [cue])
        XCTAssertEqual(ValidateWAFormUseCase.validate(project, continuationPagesAvailable: 5), [])
    }

    func test_cueWithFourRightHolders_exceedingCapacity_reportsCueExceedsRightHolderCapacity() {
        let cue = Self.makeValidCue(rightHolderCount: 4)
        let project = Self.makeProject(cues: [cue])

        XCTAssertEqual(
            ValidateWAFormUseCase.validate(project, continuationPagesAvailable: 5),
            [.cueExceedsRightHolderCapacity(cueID: cue.id, rightHolderCount: 4)]
        )
    }

    /// `.performer` rows are excluded from the 3-row count entirely (SPEC.md
    /// §2.2/§4.4 — the WA Film form has no slot for performers at all), in
    /// both directions: three composers plus two performers (5 rows total,
    /// only 3 non-performer) must report no issue, and the reported
    /// `rightHolderCount` for an over-capacity cue must count only
    /// non-performer rows, never the raw array length.
    func test_performerRightHolders_excludedFromCapacityCount_bothDirections() {
        func makeComposers(_ count: Int) -> [CueRightHolder] {
            Self.evenShares(count).map { share in
                CueRightHolder(
                    party: .person(UUID()),
                    role: .composer,
                    performanceBroadcastShare: share,
                    mechanicalRightsShare: share
                )
            }
        }
        func makePerformers(_ count: Int) -> [CueRightHolder] {
            (0 ..< count).map { _ in
                CueRightHolder(
                    party: .person(UUID()),
                    role: .performer,
                    performanceBroadcastShare: 0,
                    mechanicalRightsShare: 0
                )
            }
        }

        let withinCapacityCue = Cue(
            title: "Three Composers, Two Performers",
            duration: MediaDuration(seconds: 60),
            rightHolders: makeComposers(3) + makePerformers(2),
            source: .manual
        )
        XCTAssertEqual(
            ValidateWAFormUseCase.validate(Self.makeProject(cues: [withinCapacityCue]), continuationPagesAvailable: 5),
            []
        )

        let overCapacityCue = Cue(
            title: "Four Composers, Two Performers",
            duration: MediaDuration(seconds: 60),
            rightHolders: makeComposers(4) + makePerformers(2),
            source: .manual
        )
        XCTAssertEqual(
            ValidateWAFormUseCase.validate(Self.makeProject(cues: [overCapacityCue]), continuationPagesAvailable: 5),
            [.cueExceedsRightHolderCapacity(cueID: overCapacityCue.id, rightHolderCount: 4)]
        )
    }

    // MARK: - Form capacity (main form's 5 works + 4 per continuation page)

    func test_fiveCues_withNoContinuationPages_atMainFormCapacity_reportsNoIssue() {
        let cues = (0 ..< 5).map { _ in Self.makeValidCue() }
        let project = Self.makeProject(cues: cues)
        XCTAssertEqual(ValidateWAFormUseCase.validate(project, continuationPagesAvailable: 0), [])
    }

    func test_sixCues_withNoContinuationPages_exceedsCapacity_reportsCueCountExceedsFormCapacity() {
        let cues = (0 ..< 6).map { _ in Self.makeValidCue() }
        let project = Self.makeProject(cues: cues)

        XCTAssertEqual(
            ValidateWAFormUseCase.validate(project, continuationPagesAvailable: 0),
            [.cueCountExceedsFormCapacity(cueCount: 6, availableCapacity: 5)]
        )
    }

    func test_nineCues_withOneContinuationPage_atCapacity_reportsNoIssue() {
        let cues = (0 ..< 9).map { _ in Self.makeValidCue() }
        let project = Self.makeProject(cues: cues)
        XCTAssertEqual(ValidateWAFormUseCase.validate(project, continuationPagesAvailable: 1), [])
    }

    func test_tenCues_withOneContinuationPage_exceedsCapacity_reportsCueCountExceedsFormCapacity() {
        let cues = (0 ..< 10).map { _ in Self.makeValidCue() }
        let project = Self.makeProject(cues: cues)

        XCTAssertEqual(
            ValidateWAFormUseCase.validate(project, continuationPagesAvailable: 1),
            [.cueCountExceedsFormCapacity(cueCount: 10, availableCapacity: 9)]
        )
    }

    /// **`continuationPagesAvailable: nil` — "no continuation template
    /// imported/known" — is explicitly scoped to the main form's 5-work
    /// capacity alone, per an explicit project-owner decision, not silently
    /// treated the same as `0` (though the two happen to produce the same
    /// numeric ceiling today — this test locks the *documented* behavior,
    /// not an accidentally-matching implementation detail).**
    func test_nilContinuationPagesAvailable_capsAtMainFormCapacityAlone() {
        let sixCues = (0 ..< 6).map { _ in Self.makeValidCue() }
        let project = Self.makeProject(cues: sixCues)

        XCTAssertEqual(
            ValidateWAFormUseCase.validate(project, continuationPagesAvailable: nil),
            [.cueCountExceedsFormCapacity(cueCount: 6, availableCapacity: 5)]
        )

        let fiveCues = (0 ..< 5).map { _ in Self.makeValidCue() }
        let validProject = Self.makeProject(cues: fiveCues)
        XCTAssertEqual(ValidateWAFormUseCase.validate(validProject, continuationPagesAvailable: nil), [])
    }

    // MARK: - isExportAllowed (mirrors ExportCueSheetUseCase.isExportAllowed)

    func test_isExportAllowed_noIssues_trueRegardlessOfStrictness() {
        XCTAssertTrue(ValidateWAFormUseCase.isExportAllowed(issues: [], strictness: .blockExport))
        XCTAssertTrue(ValidateWAFormUseCase.isExportAllowed(issues: [], strictness: .warnOnly))
    }

    func test_isExportAllowed_withIssues_blockExport_false() {
        let issues: [WAFormValidationIssue] = [.cueCountExceedsFormCapacity(cueCount: 6, availableCapacity: 5)]
        XCTAssertFalse(ValidateWAFormUseCase.isExportAllowed(issues: issues, strictness: .blockExport))
    }

    func test_isExportAllowed_withIssues_warnOnly_true() {
        let issues: [WAFormValidationIssue] = [.cueCountExceedsFormCapacity(cueCount: 6, availableCapacity: 5)]
        XCTAssertTrue(ValidateWAFormUseCase.isExportAllowed(issues: issues, strictness: .warnOnly))
    }
}
