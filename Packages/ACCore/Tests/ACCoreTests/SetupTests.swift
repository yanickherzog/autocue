@testable import ACCore
import XCTest

final class SetupTests: XCTestCase {
    private static func makeSetup(
        title: String = "A Swiss Story",
        productionTypes: Set<ProductionType> = [.documentaryFilm],
        timecodeFrameRate: TimecodeFrameRate = .fps25,
        attachmentTypes: Set<AttachmentType> = []
    ) -> Setup {
        Setup(
            title: title,
            producer: .person(UUID()),
            directorOrPrincipal: .person(UUID()),
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: MediaDuration(seconds: 600),
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: productionTypes,
            timecodeFrameRate: timecodeFrameRate,
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0),
            attachmentTypes: attachmentTypes
        )
    }

    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = Self.makeSetup()
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_differingTitle_makesSetupsUnequal() {
        XCTAssertNotEqual(Self.makeSetup(title: "A"), Self.makeSetup(title: "B"))
    }

    func test_timecodeFrameRate_defaultsToFps25WhenOmittedAtTheInitializer() {
        // Omits timecodeFrameRate entirely, exercising Setup's own default
        // parameter — not the test helper's.
        let setup = Setup(
            title: "A Swiss Story",
            producer: .person(UUID()),
            directorOrPrincipal: .person(UUID()),
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: MediaDuration(seconds: 600),
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: [.documentaryFilm],
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(setup.timecodeFrameRate, .fps25)
    }

    func test_timecodeFrameRate_isOverridableExplicitly() {
        XCTAssertEqual(Self.makeSetup(timecodeFrameRate: .fps30).timecodeFrameRate, .fps30)
    }

    func test_attachmentTypes_defaultsToEmptySetWhenOmittedAtTheInitializer() {
        let setup = Setup(
            title: "A Swiss Story",
            producer: .person(UUID()),
            directorOrPrincipal: .person(UUID()),
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: MediaDuration(seconds: 600),
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: [.documentaryFilm],
            declarant: .person(UUID()),
            declarationDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(setup.attachmentTypes.isEmpty)
    }

    func test_optionalFields_defaultToNilWhenOmitted() {
        let setup = Self.makeSetup()

        XCTAssertNil(setup.subtitle)
        XCTAssertNil(setup.knownOrFutureBroadcasts)
        XCTAssertNil(setup.otherProductionTypeDescription)
        XCTAssertNil(setup.isanNumber)
        XCTAssertNil(setup.suisaRegistrationNumber)
        XCTAssertNil(setup.seriesTitle)
        XCTAssertNil(setup.seasonNumber)
        XCTAssertNil(setup.episodeNumber)
        XCTAssertNil(setup.episodeTitle)
        XCTAssertNil(setup.productionCountry)
        XCTAssertNil(setup.language)
        XCTAssertNil(setup.otherAttachmentDescription)
    }

    func test_producerDirectorDeclarant_defaultToNilWhenOmitted() {
        // A brand-new Project (ROADMAP.md D6/T6.2) has no Person/Label in its
        // directory yet to reference, so these three fields must be
        // genuinely representable as absent rather than forced to reference
        // a fabricated placeholder right-holder — see the doc comment on
        // Setup itself and docs/DECISIONS.md.
        let setup = Setup(
            title: "A Swiss Story",
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: MediaDuration(seconds: 600),
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: [.documentaryFilm],
            declarationDate: Date(timeIntervalSince1970: 0)
        )
        XCTAssertNil(setup.producer)
        XCTAssertNil(setup.directorOrPrincipal)
        XCTAssertNil(setup.declarant)
    }

    private struct FullyPopulatedFixture {
        let producer: Party
        let director: Party
        let declarant: Party
        let declarationDate: Date
        let setup: Setup

        init() {
            producer = .person(UUID())
            director = .label(UUID())
            declarant = .person(UUID())
            declarationDate = Date(timeIntervalSince1970: 1_000_000)
            setup = Setup(
                title: "A Swiss Story",
                subtitle: "Part Two",
                producer: producer,
                directorOrPrincipal: director,
                productionRuntime: MediaDuration(seconds: 5400),
                totalMusicRuntime: MediaDuration(seconds: 600),
                productionYear: 2026,
                knownOrFutureBroadcasts: "SRF, premiere at Solothurn",
                containsAdditionalUndeclaredWorks: .notKnown,
                productionTypes: [.documentaryFilm, .tvBroadcast],
                isanNumber: "ISAN-0000-0000-1",
                suisaRegistrationNumber: "SUISA-42",
                seriesTitle: "Bergwelt",
                seasonNumber: 2,
                episodeNumber: 5,
                episodeTitle: "Der Gipfel",
                productionCountry: "Switzerland",
                language: "de",
                timecodeFrameRate: .fps25,
                declarant: declarant,
                declarationDate: declarationDate,
                attachmentTypes: [.score, .other],
                otherAttachmentDescription: "Location release forms"
            )
        }
    }

    func test_fieldsArePreservedExactlyAsInitialized_productionHeader() {
        let fixture = FullyPopulatedFixture()
        let setup = fixture.setup

        XCTAssertEqual(setup.title, "A Swiss Story")
        XCTAssertEqual(setup.subtitle, "Part Two")
        XCTAssertEqual(setup.producer, fixture.producer)
        XCTAssertEqual(setup.directorOrPrincipal, fixture.director)
        XCTAssertEqual(setup.productionRuntime, MediaDuration(seconds: 5400))
        XCTAssertEqual(setup.totalMusicRuntime, MediaDuration(seconds: 600))
        XCTAssertEqual(setup.productionYear, 2026)
        XCTAssertEqual(setup.knownOrFutureBroadcasts, "SRF, premiere at Solothurn")
        XCTAssertEqual(setup.containsAdditionalUndeclaredWorks, .notKnown)
        XCTAssertEqual(setup.productionTypes, [.documentaryFilm, .tvBroadcast])
    }

    func test_fieldsArePreservedExactlyAsInitialized_registrationAndDeclaration() {
        let fixture = FullyPopulatedFixture()
        let setup = fixture.setup

        XCTAssertEqual(setup.isanNumber, "ISAN-0000-0000-1")
        XCTAssertEqual(setup.suisaRegistrationNumber, "SUISA-42")
        XCTAssertEqual(setup.seriesTitle, "Bergwelt")
        XCTAssertEqual(setup.seasonNumber, 2)
        XCTAssertEqual(setup.episodeNumber, 5)
        XCTAssertEqual(setup.episodeTitle, "Der Gipfel")
        XCTAssertEqual(setup.productionCountry, "Switzerland")
        XCTAssertEqual(setup.language, "de")
        XCTAssertEqual(setup.timecodeFrameRate, .fps25)
        XCTAssertEqual(setup.declarant, fixture.declarant)
        XCTAssertEqual(setup.declarationDate, fixture.declarationDate)
        XCTAssertEqual(setup.attachmentTypes, [.score, .other])
        XCTAssertEqual(setup.otherAttachmentDescription, "Location release forms")
    }

    func test_productionTypes_canRepresentMultipleSimultaneousCheckboxes() {
        // A production can legitimately be both .series and .tvBroadcast — the
        // whole reason productionTypes is a Set, not a single value (SPEC.md §4.2.1).
        let setup = Self.makeSetup(productionTypes: [.series, .tvBroadcast])
        XCTAssertTrue(setup.productionTypes.contains(.series))
        XCTAssertTrue(setup.productionTypes.contains(.tvBroadcast))
    }
}

final class AdditionalWorksDeclarationTests: XCTestCase {
    func test_allThreeCasesAreDistinct() {
        XCTAssertNotEqual(AdditionalWorksDeclaration.yes, .no)
        XCTAssertNotEqual(AdditionalWorksDeclaration.yes, .notKnown)
        XCTAssertNotEqual(AdditionalWorksDeclaration.no, .notKnown)
    }
}

final class ProductionTypeTests: XCTestCase {
    func test_allFourteenFormCasesExistAndAreDistinct() {
        let expected: [ProductionType] = [
            .featureFilm, .shortFilmCinema, .tvFeatureFilm, .tvShotFilm, .series,
            .documentaryFilm, .tvBroadcast, .leadInStationID, .educationalFilm,
            .commercial, .corporateFilm, .videoClip, .multimedia, .other,
        ]
        XCTAssertEqual(Set(expected).count, expected.count)
        XCTAssertEqual(ProductionType.allCases.count, expected.count)
    }
}

final class AttachmentTypeTests: XCTestCase {
    func test_allFourFormCasesExistAndAreDistinct() {
        let expected: [AttachmentType] = [.score, .agreement, .soundOrVideoCarrier, .other]
        XCTAssertEqual(Set(expected).count, expected.count)
        XCTAssertEqual(AttachmentType.allCases.count, expected.count)
    }
}
