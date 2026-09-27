@testable import ACCore
import XCTest

final class ValidateCueSheetUseCaseTests: XCTestCase {
    private static func makeValidCue(id: UUID = UUID()) -> Cue {
        Cue(
            id: id,
            title: "Opening Theme",
            duration: MediaDuration(seconds: 60),
            rightHolders: [
                CueRightHolder(
                    party: .person(UUID()),
                    role: .composer,
                    performanceBroadcastShare: 100,
                    mechanicalRightsShare: 100
                ),
            ],
            source: .manual
        )
    }

    private static func makeValidSetup(
        productionTypes: Set<ProductionType> = [.documentaryFilm],
        otherProductionTypeDescription: String? = nil,
        attachmentTypes: Set<AttachmentType> = [],
        otherAttachmentDescription: String? = nil,
        producer: [Party] = [.person(UUID())],
        directorOrPrincipal: [Party] = [.person(UUID())],
        declarant: Party? = .person(UUID())
    ) -> Setup {
        Setup(
            title: "A Swiss Story",
            producer: producer,
            directorOrPrincipal: directorOrPrincipal,
            productionRuntime: MediaDuration(seconds: 5400),
            totalMusicRuntime: MediaDuration(seconds: 600),
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: productionTypes,
            otherProductionTypeDescription: otherProductionTypeDescription,
            declarant: declarant,
            declarationDate: Date(timeIntervalSince1970: 0),
            attachmentTypes: attachmentTypes,
            otherAttachmentDescription: otherAttachmentDescription
        )
    }

    private static func makeProject(setup: Setup, cues: [Cue] = []) -> Project {
        Project(name: "Reel One", createdAt: Date(), updatedAt: Date(), setup: setup, cues: cues)
    }

    func test_fullyValidProject_noCues_reportsNoIssues() {
        let project = Self.makeProject(setup: Self.makeValidSetup())
        XCTAssertEqual(ValidateCueSheetUseCase.validate(project), [])
    }

    func test_fullyValidProject_withValidCues_reportsNoIssues() {
        let project = Self.makeProject(setup: Self.makeValidSetup(), cues: [Self.makeValidCue()])
        XCTAssertEqual(ValidateCueSheetUseCase.validate(project), [])
    }

    func test_missingDeclarant_reportsMissingSetupFieldDeclarant() {
        let project = Self.makeProject(setup: Self.makeValidSetup(declarant: nil))
        XCTAssertEqual(ValidateCueSheetUseCase.validate(project), [.missingSetupField(.declarant)])
    }

    func test_missingProducer_reportsMissingSetupFieldProducer() {
        let project = Self.makeProject(setup: Self.makeValidSetup(producer: []))
        XCTAssertEqual(ValidateCueSheetUseCase.validate(project), [.missingSetupField(.producer)])
    }

    func test_missingDirectorOrPrincipal_reportsMissingSetupFieldDirectorOrPrincipal() {
        let project = Self.makeProject(setup: Self.makeValidSetup(directorOrPrincipal: []))
        XCTAssertEqual(ValidateCueSheetUseCase.validate(project), [.missingSetupField(.directorOrPrincipal)])
    }

    func test_emptyProductionTypes_reportsMissingSetupFieldProductionTypes() {
        let project = Self.makeProject(setup: Self.makeValidSetup(productionTypes: []))
        XCTAssertEqual(ValidateCueSheetUseCase.validate(project), [.missingSetupField(.productionTypes)])
    }

    func test_otherProductionTypeSelected_withNoDescription_reportsMissingOtherProductionTypeDescription() {
        let project = Self.makeProject(setup: Self.makeValidSetup(productionTypes: [.other]))
        XCTAssertEqual(ValidateCueSheetUseCase.validate(project), [.missingOtherProductionTypeDescription])
    }

    func test_otherProductionTypeSelected_withBlankWhitespaceDescription_stillReportsMissing() {
        let project = Self.makeProject(
            setup: Self.makeValidSetup(productionTypes: [.other], otherProductionTypeDescription: "   ")
        )
        XCTAssertEqual(ValidateCueSheetUseCase.validate(project), [.missingOtherProductionTypeDescription])
    }

    func test_otherProductionTypeSelected_withRealDescription_reportsNoIssue() {
        let project = Self.makeProject(
            setup: Self.makeValidSetup(productionTypes: [.other], otherProductionTypeDescription: "A web series")
        )
        XCTAssertEqual(ValidateCueSheetUseCase.validate(project), [])
    }

    func test_otherAttachmentTypeSelected_withNoDescription_reportsMissingOtherAttachmentDescription() {
        let project = Self.makeProject(setup: Self.makeValidSetup(attachmentTypes: [.other]))
        XCTAssertEqual(ValidateCueSheetUseCase.validate(project), [.missingOtherAttachmentDescription])
    }

    func test_otherAttachmentTypeSelected_withRealDescription_reportsNoIssue() {
        let project = Self.makeProject(
            setup: Self.makeValidSetup(attachmentTypes: [.other], otherAttachmentDescription: "Score excerpt")
        )
        XCTAssertEqual(ValidateCueSheetUseCase.validate(project), [])
    }

    func test_cueWithNoRightHolders_reportsCueHasNoRightHolders() {
        let cueID = UUID()
        let cue = Cue(
            id: cueID,
            title: "Silence",
            duration: MediaDuration(seconds: 10),
            rightHolders: [],
            source: .manual
        )
        let project = Self.makeProject(setup: Self.makeValidSetup(), cues: [cue])
        XCTAssertEqual(ValidateCueSheetUseCase.validate(project), [.cueHasNoRightHolders(cueID: cueID)])
    }

    func test_cueWithSharesNotSummingTo100_reportsWrappedCueRightHolderIssue_identifyingTheCue() {
        let cueID = UUID()
        let cue = Cue(
            id: cueID,
            title: "Broken Split",
            duration: MediaDuration(seconds: 60),
            rightHolders: [
                // mechanicalRightsShare is a valid 100 so only the broadcast
                // pool fails — isolating exactly one issue, not two.
                CueRightHolder(
                    party: .person(UUID()),
                    role: .composer,
                    performanceBroadcastShare: 60,
                    mechanicalRightsShare: 100
                ),
            ],
            source: .manual
        )
        let project = Self.makeProject(setup: Self.makeValidSetup(), cues: [cue])

        let expectedRightHolderIssue = CueRightHolderValidationIssue.performanceBroadcastSharesDoNotSumTo100(
            pool: .creatorAndPublisher,
            total: 60
        )
        XCTAssertEqual(
            ValidateCueSheetUseCase.validate(project),
            [.cueRightHolderIssue(cueID: cueID, issue: expectedRightHolderIssue)]
        )
    }

    func test_multipleCuesWithDifferentIssues_eachReportedDistinctly_identifyingItsOwnCue() {
        let brokenCueID = UUID()
        let emptyCueID = UUID()
        let validCueID = UUID()

        let brokenCue = Cue(
            id: brokenCueID,
            title: "Broken Split",
            duration: MediaDuration(seconds: 60),
            rightHolders: [
                // mechanicalRightsShare is a valid 100 so only the broadcast
                // pool fails — one issue from this cue, not two.
                CueRightHolder(
                    party: .person(UUID()),
                    role: .composer,
                    performanceBroadcastShare: 60,
                    mechanicalRightsShare: 100
                ),
            ],
            source: .manual
        )
        let emptyCue = Cue(
            id: emptyCueID,
            title: "No Right-Holders",
            duration: MediaDuration(seconds: 10),
            rightHolders: [],
            source: .manual
        )
        let validCue = Self.makeValidCue(id: validCueID)

        let project = Self.makeProject(setup: Self.makeValidSetup(), cues: [brokenCue, emptyCue, validCue])
        let issues = ValidateCueSheetUseCase.validate(project)

        XCTAssertEqual(issues.count, 2)
        XCTAssertTrue(issues.contains(where: {
            if case let .cueRightHolderIssue(cueID, _) = $0 {
                cueID == brokenCueID
            } else {
                false
            }
        }))
        XCTAssertTrue(issues.contains(.cueHasNoRightHolders(cueID: emptyCueID)))
        XCTAssertFalse(issues.contains { issue in
            switch issue {
            case let .cueRightHolderIssue(cueID, _): cueID == validCueID
            case let .cueHasNoRightHolders(cueID): cueID == validCueID
            default: false
            }
        })
    }

    func test_multipleSetupIssues_eachReportedAsItsOwnDistinctCase() {
        let project = Self.makeProject(setup: Self.makeValidSetup(productionTypes: [], declarant: nil))
        let issues = ValidateCueSheetUseCase.validate(project)

        XCTAssertEqual(issues.count, 2)
        XCTAssertTrue(issues.contains(.missingSetupField(.productionTypes)))
        XCTAssertTrue(issues.contains(.missingSetupField(.declarant)))
    }

    func test_setupIssuesOrderedBeforeCueIssues() {
        let cueID = UUID()
        let emptyCue = Cue(
            id: cueID,
            title: "Empty",
            duration: MediaDuration(seconds: 10),
            rightHolders: [],
            source: .manual
        )
        let project = Self.makeProject(setup: Self.makeValidSetup(declarant: nil), cues: [emptyCue])
        let issues = ValidateCueSheetUseCase.validate(project)

        XCTAssertEqual(issues, [.missingSetupField(.declarant), .cueHasNoRightHolders(cueID: cueID)])
    }
}
