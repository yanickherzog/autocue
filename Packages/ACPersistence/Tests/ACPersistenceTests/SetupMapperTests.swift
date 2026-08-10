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

    func test_nilProducerDirectorDeclarant_roundTripToNilNotAThrownError() throws {
        // Setup.producer/.directorOrPrincipal/.declarant are Party? — a
        // brand-new Project genuinely has none chosen yet (docs/DECISIONS.md,
        // "Setup's three Party fields become optional"). The persisted
        // column pair must round-trip that absence as nil, not as an error.
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
        XCTAssertNil(entity.producerPartyKind)
        XCTAssertNil(entity.producerPartyID)
        XCTAssertNil(entity.directorPartyKind)
        XCTAssertNil(entity.directorPartyID)
        XCTAssertNil(entity.declarantPartyKind)
        XCTAssertNil(entity.declarantPartyID)

        let roundTripped = try SetupMapper.toDomain(entity)
        XCTAssertNil(roundTripped.producer)
        XCTAssertNil(roundTripped.directorOrPrincipal)
        XCTAssertNil(roundTripped.declarant)
    }

    private func makeSetup(
        productionTypes: Set<ProductionType> = [.other],
        attachmentTypes: Set<AttachmentType> = [],
        timecodeFrameRate: TimecodeFrameRate = .fps25,
        containsAdditionalUndeclaredWorks: AdditionalWorksDeclaration = .no
    ) -> Setup {
        let partyID = UUID()
        return Setup(
            title: "Test",
            producer: .person(partyID),
            directorOrPrincipal: .person(partyID),
            productionRuntime: MediaDuration(seconds: 60),
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: containsAdditionalUndeclaredWorks,
            productionTypes: productionTypes,
            otherProductionTypeDescription: productionTypes.contains(.other) ? "n/a" : nil,
            timecodeFrameRate: timecodeFrameRate,
            declarant: .person(partyID),
            declarationDate: Date(timeIntervalSince1970: 1_699_000_000),
            attachmentTypes: attachmentTypes,
            otherAttachmentDescription: attachmentTypes.contains(.other) ? "n/a" : nil
        )
    }
}
