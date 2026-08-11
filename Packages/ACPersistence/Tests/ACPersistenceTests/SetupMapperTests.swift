@testable import ACCore
@testable import ACPersistence
import XCTest

/// Direct coverage for `SetupMapper`'s enum raw-value tables — specifically
/// that every `CaseIterable` case has an entry and round-trips, since the
/// lookup-table design (chosen over a `switch` to stay under SwiftLint's
/// cyclomatic-complexity threshold — see `SetupMapper`'s doc comments) isn't
/// compiler-checked for exhaustiveness the way a `switch` over an enum is.
/// `ProjectRoundTripTests` already exercises one `ProductionType`/
/// `AttachmentType` value each via the fixture; this test is what actually
/// proves every case works, not just the ones the fixture happens to use.
final class SetupMapperTests: XCTestCase {
    func test_everyProductionTypeCaseRoundTripsThroughSetup() throws {
        for productionType in ProductionType.allCases {
            let setup = makeSetup(productionTypes: [productionType])
            let entity = SetupMapper.toEntity(setup)
            let roundTripped = try SetupMapper.toDomain(entity)
            XCTAssertEqual(roundTripped.productionTypes, [productionType])
        }
    }

    func test_everyAttachmentTypeCaseRoundTripsThroughSetup() throws {
        for attachmentType in AttachmentType.allCases {
            let setup = makeSetup(attachmentTypes: [attachmentType])
            let entity = SetupMapper.toEntity(setup)
            let roundTripped = try SetupMapper.toDomain(entity)
            XCTAssertEqual(roundTripped.attachmentTypes, [attachmentType])
        }
    }

    func test_everyExploitationTypeCaseRoundTripsThroughSetup() throws {
        for exploitationType in ExploitationType.allCases {
            let setup = makeSetup(exploitationTypes: [exploitationType])
            let entity = SetupMapper.toEntity(setup)
            let roundTripped = try SetupMapper.toDomain(entity)
            XCTAssertEqual(roundTripped.exploitationTypes, [exploitationType])
        }
    }

    func test_beitragRoundTripsThroughSetup() throws {
        let setup = makeSetup(beitrag: "Bergwelt, Folge 5")
        let entity = SetupMapper.toEntity(setup)
        let roundTripped = try SetupMapper.toDomain(entity)
        XCTAssertEqual(roundTripped.beitrag, "Bergwelt, Folge 5")
    }

    func test_nilBeitrag_roundTripsToNil() throws {
        let entity = SetupMapper.toEntity(makeSetup(beitrag: nil))
        XCTAssertNil(entity.beitrag)
        XCTAssertNil(try SetupMapper.toDomain(entity).beitrag)
    }

    func test_emptyBroadcastDetails_roundTripsToEmptyNotAThrownError() throws {
        let entity = SetupMapper.toEntity(makeSetup(broadcastDetails: []))
        XCTAssertTrue(entity.broadcastDetails.isEmpty)
        XCTAssertTrue(try SetupMapper.toDomain(entity).broadcastDetails.isEmpty)
    }

    func test_partiallyPopulatedBroadcastDetailsEntry_roundTripsWithOnlyThoseFieldsSet() throws {
        // BroadcastDetails allows partial data (a confirmed broadcaster
        // before an exact date is known) — the mapper must not require every
        // sub-field to be non-nil to reconstruct a valid entry.
        let partial = BroadcastDetails(broadcaster: "SRF", programmeName: nil, date: nil)
        let entity = SetupMapper.toEntity(makeSetup(broadcastDetails: [partial]))
        let roundTripped = try SetupMapper.toDomain(entity)
        XCTAssertEqual(roundTripped.broadcastDetails, [partial])
    }

    func test_multipleBroadcastDetailsEntries_roundTripInOrder() throws {
        // Setup.broadcastDetails is [BroadcastDetails] (explicit reversal
        // from an originally single-instance scoping — docs/DECISIONS.md) —
        // this is what actually proves more than one entry survives a
        // save/fetch round-trip in its original order, not just that the
        // type compiles as a collection.
        let first = BroadcastDetails(
            broadcaster: "SRF",
            programmeName: "Bergwelt",
            date: Date(timeIntervalSince1970: 1_700_002_000)
        )
        let second = BroadcastDetails(broadcaster: "3sat", programmeName: nil, date: nil)
        let entity = SetupMapper.toEntity(makeSetup(broadcastDetails: [first, second]))
        let roundTripped = try SetupMapper.toDomain(entity)
        XCTAssertEqual(roundTripped.broadcastDetails, [first, second])
    }

    func test_nilTimecodeStart_roundTripsToNil() throws {
        let entity = SetupMapper.toEntity(makeSetup(timecodeStart: nil))
        XCTAssertNil(entity.timecodeStartOffsetSeconds)
        XCTAssertNil(try SetupMapper.toDomain(entity).timecodeStart)
    }

    func test_timecodeStart_roundTripsExactly() throws {
        let timecodeStart = Timecode(offsetSeconds: 35992)
        let entity = SetupMapper.toEntity(makeSetup(timecodeStart: timecodeStart))
        let roundTripped = try SetupMapper.toDomain(entity)
        XCTAssertEqual(roundTripped.timecodeStart, timecodeStart)
    }

    func test_everyTimecodeFrameRateCaseRoundTripsThroughSetup() throws {
        for frameRate in TimecodeFrameRate.allCases {
            let setup = makeSetup(timecodeFrameRate: frameRate)
            let entity = SetupMapper.toEntity(setup)
            let roundTripped = try SetupMapper.toDomain(entity)
            XCTAssertEqual(roundTripped.timecodeFrameRate, frameRate)
        }
    }

    func test_everyAdditionalWorksDeclarationCaseRoundTripsThroughSetup() throws {
        for declaration: AdditionalWorksDeclaration in [.yes, .no, .notKnown] {
            let setup = makeSetup(containsAdditionalUndeclaredWorks: declaration)
            let entity = SetupMapper.toEntity(setup)
            let roundTripped = try SetupMapper.toDomain(entity)
            XCTAssertEqual(roundTripped.containsAdditionalUndeclaredWorks, declaration)
        }
    }

    func test_emptyProducerDirector_nilDeclarant_roundTripToTheirOwnUnsetValuesNotAThrownError() throws {
        // Setup.producer/.directorOrPrincipal are [Party] (ROADMAP.md D7,
        // later round) — an empty array is their own honest "not yet
        // chosen" value, the same as Set<ProductionType>'s []. declarant
        // stays Party? — a brand-new Project genuinely has none chosen yet
        // (docs/DECISIONS.md, "Setup's three Party fields become optional").
        // Both shapes must round-trip their own unset value without error.
        let setup = Setup(
            title: "Test",
            productionRuntime: MediaDuration(seconds: 60),
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: [.other],
            otherProductionTypeDescription: "n/a",
            declarationDate: Date(timeIntervalSince1970: 1_699_000_000)
        )
        let entity = SetupMapper.toEntity(setup)
        XCTAssertEqual(entity.producerPartyKinds, [])
        XCTAssertEqual(entity.producerPartyIDs, [])
        XCTAssertEqual(entity.directorPartyKinds, [])
        XCTAssertEqual(entity.directorPartyIDs, [])
        XCTAssertNil(entity.declarantPartyKind)
        XCTAssertNil(entity.declarantPartyID)

        let roundTripped = try SetupMapper.toDomain(entity)
        XCTAssertEqual(roundTripped.producer, [])
        XCTAssertEqual(roundTripped.directorOrPrincipal, [])
        XCTAssertNil(roundTripped.declarant)
    }

    func test_multipleProducersAndDirectors_roundTripInOrder() throws {
        let firstProducer = UUID()
        let secondProducer = UUID()
        let director = UUID()
        let setup = Setup(
            title: "Test",
            producer: [.person(firstProducer), .label(secondProducer)],
            directorOrPrincipal: [.person(director)],
            productionRuntime: MediaDuration(seconds: 60),
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: [.other],
            otherProductionTypeDescription: "n/a",
            declarationDate: Date(timeIntervalSince1970: 1_699_000_000)
        )

        let entity = SetupMapper.toEntity(setup)
        let roundTripped = try SetupMapper.toDomain(entity)

        XCTAssertEqual(roundTripped.producer, [.person(firstProducer), .label(secondProducer)])
        XCTAssertEqual(roundTripped.directorOrPrincipal, [.person(director)])
    }

    private func makeSetup(
        productionTypes: Set<ProductionType> = [.other],
        attachmentTypes: Set<AttachmentType> = [],
        timecodeFrameRate: TimecodeFrameRate = .fps25,
        containsAdditionalUndeclaredWorks: AdditionalWorksDeclaration = .no,
        exploitationTypes: Set<ExploitationType> = [],
        beitrag: String? = nil,
        broadcastDetails: [BroadcastDetails] = [],
        timecodeStart: Timecode? = nil
    ) -> Setup {
        let partyID = UUID()
        return Setup(
            title: "Test",
            producer: [.person(partyID)],
            directorOrPrincipal: [.person(partyID)],
            productionRuntime: MediaDuration(seconds: 60),
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: containsAdditionalUndeclaredWorks,
            productionTypes: productionTypes,
            otherProductionTypeDescription: productionTypes.contains(.other) ? "n/a" : nil,
            timecodeFrameRate: timecodeFrameRate,
            timecodeStart: timecodeStart,
            declarant: .person(partyID),
            declarationDate: Date(timeIntervalSince1970: 1_699_000_000),
            attachmentTypes: attachmentTypes,
            otherAttachmentDescription: attachmentTypes.contains(.other) ? "n/a" : nil,
            beitrag: beitrag,
            exploitationTypes: exploitationTypes,
            otherExploitationTypeDescription: exploitationTypes.contains(.other) ? "n/a" : nil,
            broadcastDetails: broadcastDetails
        )
    }
}
