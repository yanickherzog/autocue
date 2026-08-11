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
            producer: [.person(UUID())],
            directorOrPrincipal: [.person(UUID())],
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

    /// Regression, matching the exact call `SetupView`'s `Title` field
    /// binding makes (`ROADMAP.md` D7, later round): `beitrag` now mirrors
    /// `Title` via one combined `updating(title:beitrag:)` call instead of
    /// its own independent field. This is the same class of bug as the
    /// earlier confirmed Declarant-clear data-loss issue — a multi-field
    /// write silently dropping unrelated state — so every other field is
    /// checked individually here, not just spot-checked, including ones a
    /// narrower test could plausibly miss (`producer`/`directorOrPrincipal`/
    /// `declarant`, all `Party?`, since those were exactly the fields
    /// involved in that earlier bug).
    func test_updating_titleAndBeitragTogether_matchingSetupViewsBinding_preservesEveryOtherField() {
        let setup = Setup(
            title: "Old Title",
            subtitle: "Part Two",
            producer: [.person(UUID())],
            directorOrPrincipal: [.person(UUID())],
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: MediaDuration(seconds: 120),
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .yes,
            productionTypes: [.documentaryFilm, .series],
            otherProductionTypeDescription: "Docuseries",
            isanNumber: "1881-66C7-3420-0000-7-0000-0000-Y",
            seriesTitle: "Alpine Stories",
            productionCountry: "CH",
            language: "de",
            timecodeFrameRate: .fps30,
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0),
            attachmentTypes: [.score],
            beitrag: "Old Title",
            exploitationTypes: [.cinema]
        )

        // Exactly the call SetupView+ProductionSection.swift's Title field
        // binding makes.
        let updated = setup.updating(title: "New Title", beitrag: .some("New Title"))

        XCTAssertEqual(updated.title, "New Title")
        XCTAssertEqual(updated.beitrag, "New Title")
        // Every other field, individually — not a partial spot-check.
        XCTAssertEqual(updated.subtitle, setup.subtitle)
        XCTAssertEqual(updated.producer, setup.producer)
        XCTAssertEqual(updated.directorOrPrincipal, setup.directorOrPrincipal)
        XCTAssertEqual(updated.productionRuntime, setup.productionRuntime)
        XCTAssertEqual(updated.totalMusicRuntime, setup.totalMusicRuntime)
        XCTAssertEqual(updated.productionYear, setup.productionYear)
        XCTAssertEqual(updated.containsAdditionalUndeclaredWorks, setup.containsAdditionalUndeclaredWorks)
        XCTAssertEqual(updated.productionTypes, setup.productionTypes)
        XCTAssertEqual(updated.otherProductionTypeDescription, setup.otherProductionTypeDescription)
        XCTAssertEqual(updated.isanNumber, setup.isanNumber)
        XCTAssertEqual(updated.seriesTitle, setup.seriesTitle)
        XCTAssertEqual(updated.productionCountry, setup.productionCountry)
        XCTAssertEqual(updated.language, setup.language)
        XCTAssertEqual(updated.timecodeFrameRate, setup.timecodeFrameRate)
        XCTAssertEqual(updated.declarant, setup.declarant)
        XCTAssertEqual(updated.declarationDate, setup.declarationDate)
        XCTAssertEqual(updated.attachmentTypes, setup.attachmentTypes)
        XCTAssertEqual(updated.exploitationTypes, setup.exploitationTypes)
    }
}

final class SetupMissingRequiredFieldsTests: XCTestCase {
    private static func makeFullyValidSetup() -> Setup {
        Setup(
            title: "A Swiss Story",
            producer: [.person(UUID())],
            directorOrPrincipal: [.person(UUID())],
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
            producer: [.person(UUID())],
            directorOrPrincipal: [.person(UUID())],
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
            producer: [.person(UUID())],
            directorOrPrincipal: [.person(UUID())],
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
            producer: [.person(UUID())],
            directorOrPrincipal: [.person(UUID())],
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
            producer: [.person(UUID())],
            directorOrPrincipal: [.person(UUID())],
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
