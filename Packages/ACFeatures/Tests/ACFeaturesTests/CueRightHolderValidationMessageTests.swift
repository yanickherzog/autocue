import ACCore
@testable import ACFeatures
import XCTest

/// `CueRightHolderValidationMessageFormatter` (`ROADMAP.md` D10) — a plain,
/// non-View type, so unlike `CueRowDetailView` itself it's directly
/// unit-testable (`CONTRIBUTING.md` §5/§7).
final class CueRightHolderValidationMessageTests: XCTestCase {
    /// The exact regression scenario reported and confirmed with real
    /// runtime evidence: both pools genuinely sum to 100%, but a Publisher's
    /// "Publishing contract attached" checkbox is unset. The formatter must
    /// show only the attachment message — never a share-sum message, since
    /// no share-sum issue exists in this case.
    func test_validSharesButMissingPublishingContract_showsOnlyTheAttachmentMessage_neverAShareSumMessage() {
        let composer1 = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 34, mechanicalRightsShare: 67
        )
        let composer2 = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 25, mechanicalRightsShare: 22
        )
        let publisherID = UUID()
        let publisher = CueRightHolder(
            party: .label(publisherID), role: .publisher, performanceBroadcastShare: 41, mechanicalRightsShare: 11
        )
        let rightHolders = [composer1, composer2, publisher]
        let cue = Cue(
            title: "Test Cue",
            duration: MediaDuration(seconds: 60),
            rightHolders: rightHolders,
            source: .manual
        )

        // Real issues, from the real Use Case — not fabricated, to prove
        // this test would actually catch a regression in either type.
        let issues = ValidateCueRightHolderSharesUseCase.validate(cue)
        XCTAssertEqual(issues, [.missingPublishingContractAttachment(rightHolderIndex: 2)])

        let label = Label(
            id: publisherID, name: "Warner Brothers",
            address: PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
        )
        let messages = CueRightHolderValidationMessageFormatter.messages(
            for: issues, rightHolders: rightHolders, people: [], labels: [label]
        )

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first, "Warner Brothers is missing \"Publishing contract attached.\"")
        XCTAssertFalse(messages.contains { $0.contains("sum to") })
    }

    func test_performanceBroadcastShareSumIssue_namesTheRealPoolAndTotal() {
        let issues: [CueRightHolderValidationIssue] = [
            .performanceBroadcastSharesDoNotSumTo100(pool: .creatorAndPublisher, total: 92),
        ]
        let messages = CueRightHolderValidationMessageFormatter.messages(
            for: issues, rightHolders: [], people: [], labels: []
        )
        XCTAssertEqual(
            messages,
            ["Broadcast shares for the combined Composer/Author/Publisher pool sum to 92%, not 100%."]
        )
    }

    func test_mechanicalRightsShareSumIssue_forArrangerPool_namesArrangerSpecifically() {
        let issues: [CueRightHolderValidationIssue] = [
            .mechanicalRightsSharesDoNotSumTo100(pool: .arranger, total: 60),
        ]
        let messages = CueRightHolderValidationMessageFormatter.messages(
            for: issues, rightHolders: [], people: [], labels: []
        )
        XCTAssertEqual(messages, ["Mechanical shares for the Arranger pool sum to 60%, not 100%."])
    }

    func test_missingArrangementAuthorization_namesTheRealRightHolder() {
        let personID = UUID()
        let arranger = CueRightHolder(
            party: .person(personID), role: .arranger, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let person = Person(id: personID, firstName: "Hans", lastName: "Zimmer")
        let issues: [CueRightHolderValidationIssue] = [.missingArrangementAuthorization(rightHolderIndex: 0)]

        let messages = CueRightHolderValidationMessageFormatter.messages(
            for: issues, rightHolders: [arranger], people: [person], labels: []
        )

        XCTAssertEqual(messages, ["Hans Zimmer is missing \"Arrangement authorization attached.\""])
    }

    /// Every real issue gets its own message — not just the first — so a
    /// second, unrelated problem is visible in the same pass.
    func test_multipleSimultaneousIssues_areAllListed_notJustTheFirst() {
        let issues: [CueRightHolderValidationIssue] = [
            .performanceBroadcastSharesDoNotSumTo100(pool: .creatorAndPublisher, total: 92),
            .mechanicalRightsSharesDoNotSumTo100(pool: .arranger, total: 60),
            .missingPublishingContractAttachment(rightHolderIndex: 0),
        ]
        let publisherID = UUID()
        let publisher = CueRightHolder(
            party: .label(publisherID), role: .publisher, performanceBroadcastShare: 92, mechanicalRightsShare: 92
        )
        let label = Label(
            id: publisherID, name: "Warner Brothers",
            address: PostalAddress(street: "Bahnhofstrasse 1", postalCode: "8001", city: "Zürich", country: "CH")
        )

        let messages = CueRightHolderValidationMessageFormatter.messages(
            for: issues, rightHolders: [publisher], people: [], labels: [label]
        )

        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(
            messages[0],
            "Broadcast shares for the combined Composer/Author/Publisher pool sum to 92%, not 100%."
        )
        XCTAssertEqual(messages[1], "Mechanical shares for the Arranger pool sum to 60%, not 100%.")
        XCTAssertEqual(messages[2], "Warner Brothers is missing \"Publishing contract attached.\"")
    }

    func test_emptyIssues_producesNoMessages() {
        let messages = CueRightHolderValidationMessageFormatter.messages(
            for: [], rightHolders: [], people: [], labels: []
        )
        XCTAssertTrue(messages.isEmpty)
    }
}
