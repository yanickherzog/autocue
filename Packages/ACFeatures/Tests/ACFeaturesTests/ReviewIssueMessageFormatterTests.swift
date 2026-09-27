import ACCore
@testable import ACFeatures
import XCTest

final class ReviewIssueMessageFormatterTests: XCTestCase {
    private func makeCue(
        id: Cue.ID = UUID(),
        title: String = "Opening Theme",
        rightHolders: [CueRightHolder] = []
    ) -> Cue {
        Cue(id: id, title: title, duration: MediaDuration(seconds: 60), rightHolders: rightHolders, source: .manual)
    }

    func test_missingSetupField_usesItsDisplayName() {
        let messages = ReviewIssueMessageFormatter.messages(
            for: [.missingSetupField(.declarant)],
            cues: [],
            people: [],
            labels: []
        )
        XCTAssertEqual(messages, ["Setup: Declarant is missing."])
    }

    func test_missingOtherProductionTypeDescription_hasItsOwnMessage() {
        let messages = ReviewIssueMessageFormatter.messages(
            for: [.missingOtherProductionTypeDescription],
            cues: [],
            people: [],
            labels: []
        )
        XCTAssertEqual(messages, ["Setup: \"Other\" production type is selected but not described."])
    }

    func test_missingOtherAttachmentDescription_hasItsOwnMessage() {
        let messages = ReviewIssueMessageFormatter.messages(
            for: [.missingOtherAttachmentDescription],
            cues: [],
            people: [],
            labels: []
        )
        XCTAssertEqual(messages, ["Setup: \"Other\" attachment type is selected but not described."])
    }

    func test_cueHasNoRightHolders_namesTheCueByPositionAndTitle() {
        let cueID = UUID()
        let cue = makeCue(id: cueID, title: "End Credits")
        let messages = ReviewIssueMessageFormatter.messages(
            for: [.cueHasNoRightHolders(cueID: cueID)],
            cues: [cue],
            people: [],
            labels: []
        )
        XCTAssertEqual(messages, ["Cue 1 — End Credits has no right-holders."])
    }

    func test_cueRightHolderIssue_delegatesWordingToTheExistingD10Formatter_prefixedWithTheCueLabel() {
        let cueID = UUID()
        let rightHolder = CueRightHolder(
            party: .person(UUID()),
            role: .composer,
            performanceBroadcastShare: 60,
            mechanicalRightsShare: 100
        )
        let cue = makeCue(id: cueID, title: "Opening Theme", rightHolders: [rightHolder])
        let issue = CueRightHolderValidationIssue.performanceBroadcastSharesDoNotSumTo100(
            pool: .creatorAndPublisher,
            total: 60
        )

        let messages = ReviewIssueMessageFormatter.messages(
            for: [.cueRightHolderIssue(cueID: cueID, issue: issue)],
            cues: [cue],
            people: [],
            labels: []
        )

        let expected = "Cue 1 — Opening Theme: Broadcast shares for the combined Composer/Author/Publisher pool " +
            "sum to 60%, not 100%."
        XCTAssertEqual(messages, [expected])
    }

    func test_multipleIssues_eachGetsItsOwnMessage_inTheSameOrder() {
        let emptyCueID = UUID()
        let emptyCue = makeCue(id: emptyCueID, title: "No Right-Holders")

        let messages = ReviewIssueMessageFormatter.messages(
            for: [.missingSetupField(.producer), .cueHasNoRightHolders(cueID: emptyCueID)],
            cues: [emptyCue],
            people: [],
            labels: []
        )

        XCTAssertEqual(messages, [
            "Setup: Producer*in is missing.",
            "Cue 1 — No Right-Holders has no right-holders.",
        ])
    }

    func test_unknownCueID_fallsBackToAGenericLabel_ratherThanCrashing() {
        let messages = ReviewIssueMessageFormatter.messages(
            for: [.cueHasNoRightHolders(cueID: UUID())],
            cues: [],
            people: [],
            labels: []
        )
        XCTAssertEqual(messages, ["A cue has no right-holders."])
    }
}
