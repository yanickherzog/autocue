@testable import ACCore
import XCTest

/// Covers `Setup.updating(...)` and `Setup.missingRequiredFields` — split
/// out of `SetupTests.swift` once it exceeded `CONTRIBUTING.md` §8's
/// `SwiftLint` file-length threshold (`ROADMAP.md` D7).
final class SetupUpdatingTests: XCTestCase {
    private static func makeSetup() -> Setup {
        Setup(
            title: "A Swiss Story",
            subtitle: "Part Two",
            producer: .person(UUID()),
            directorOrPrincipal: .person(UUID()),
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .notKnown,
            productionTypes: [.documentaryFilm],
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0)
        )
    }

    func test_updating_withNoArguments_returnsAnUnchangedEqualCopy() {
        let setup = Self.makeSetup()
        XCTAssertEqual(setup.updating(), setup)
    }

    func test_updating_overridesOnlyTheGivenField_leavesEverythingElseUnchanged() {
        let setup = Self.makeSetup()
        let updated = setup.updating(title: "New Title")

        XCTAssertEqual(updated.title, "New Title")
        XCTAssertEqual(updated.subtitle, setup.subtitle)
        XCTAssertEqual(updated.producer, setup.producer)
        XCTAssertEqual(updated.productionYear, setup.productionYear)
    }

    func test_updating_doesNotMutateTheOriginal() {
        let setup = Self.makeSetup()
        _ = setup.updating(title: "New Title")
        XCTAssertEqual(setup.title, "A Swiss Story")
    }

    func test_updating_doubleOptionalField_omittingLeavesItUnchanged() {
        let setup = Self.makeSetup()
        let updated = setup.updating(title: "New Title")
        XCTAssertEqual(updated.subtitle, "Part Two")
    }

    func test_updating_doubleOptionalField_explicitSomeNil_clearsIt() {
        let setup = Self.makeSetup()
        let updated = setup.updating(subtitle: .some(nil))
        XCTAssertNil(updated.subtitle)
    }

    func test_updating_doubleOptionalField_explicitSomeValue_setsIt() {
        let setup = Self.makeSetup()
        let updated = setup.updating(subtitle: .some("New Subtitle"))
        XCTAssertEqual(updated.subtitle, "New Subtitle")
    }

    func test_updating_canChainMultipleFieldsAtOnce() {
        let setup = Self.makeSetup()
        let updated = setup.updating(title: "New Title", productionYear: 2027, exploitationTypes: [.cinema, .tv])

        XCTAssertEqual(updated.title, "New Title")
        XCTAssertEqual(updated.productionYear, 2027)
        XCTAssertEqual(updated.exploitationTypes, [.cinema, .tv])
        XCTAssertEqual(updated.subtitle, setup.subtitle)
    }
}

final class SetupMissingRequiredFieldsTests: XCTestCase {
    private static func makeFullyValidSetup() -> Setup {
        Setup(
            title: "A Swiss Story",
            producer: .person(UUID()),
            directorOrPrincipal: .person(UUID()),
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .notKnown,
            productionTypes: [.documentaryFilm],
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0)
        )
    }

    func test_fullyValidSetup_hasNoMissingFields() {
        XCTAssertTrue(Self.makeFullyValidSetup().missingRequiredFields.isEmpty)
    }

    func test_blankTitle_isFlagged() {
        let setup = Setup(
            title: "   ",
            producer: .person(UUID()),
            directorOrPrincipal: .person(UUID()),
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .notKnown,
            productionTypes: [.documentaryFilm],
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(setup.missingRequiredFields.contains(.title))
    }

    func test_nilProducerDirectorDeclarant_areAllFlagged() {
        let setup = Setup(
            title: "A Swiss Story",
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .notKnown,
            productionTypes: [.documentaryFilm],
            declarationDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(Set(setup.missingRequiredFields), [.producer, .directorOrPrincipal, .declarant])
    }

    func test_zeroProductionRuntime_isFlagged() {
        let setup = Setup(
            title: "A Swiss Story",
            producer: .person(UUID()),
            directorOrPrincipal: .person(UUID()),
            productionRuntime: .zero,
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .notKnown,
            productionTypes: [.documentaryFilm],
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(setup.missingRequiredFields.contains(.productionRuntime))
    }

    func test_zeroProductionYear_isFlagged() {
        let setup = Setup(
            title: "A Swiss Story",
            producer: .person(UUID()),
            directorOrPrincipal: .person(UUID()),
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: .zero,
            productionYear: 0,
            containsAdditionalUndeclaredWorks: .notKnown,
            productionTypes: [.documentaryFilm],
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(setup.missingRequiredFields.contains(.productionYear))
    }

    func test_emptyProductionTypes_isFlagged() {
        let setup = Setup(
            title: "A Swiss Story",
            producer: .person(UUID()),
            directorOrPrincipal: .person(UUID()),
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .notKnown,
            productionTypes: [],
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(setup.missingRequiredFields.contains(.productionTypes))
    }

    // MARK: - Fields deliberately NOT checked (see Setup.missingRequiredFields's doc comment)

    func test_zeroTotalMusicRuntimeAndNotKnownDeclaration_areNotFlagged_bothAreHonestNotPlaceholderValues() {
        // .zero is the honestly-correct totalMusicRuntime for a Project with
        // no Cues yet (true for every Setup until D9/D10 land), and
        // .notKnown is a real, SUISA-sanctioned containsAdditionalUndeclared-
        // Works answer (docs/DECISIONS.md) — neither is a placeholder
        // standing in for missing data, so a fully-valid Setup with both
        // still reports zero missing fields. `SetupRequiredField` has no
        // `.totalMusicRuntime`/`.containsAdditionalUndeclaredWorks` case at
        // all, so there's nothing these two values could even be flagged as.
        let setup = Self.makeFullyValidSetup()
        XCTAssertEqual(setup.totalMusicRuntime, .zero)
        XCTAssertEqual(setup.containsAdditionalUndeclaredWorks, .notKnown)
        XCTAssertTrue(setup.missingRequiredFields.isEmpty)
    }
}
