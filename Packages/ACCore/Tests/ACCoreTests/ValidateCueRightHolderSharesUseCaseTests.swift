@testable import ACCore
import XCTest

final class ValidateCueRightHolderSharesUseCaseTests: XCTestCase {
    private func makeCue(rightHolders: [CueRightHolder], isArrangementOfProtectedOriginal: Bool = false) -> Cue {
        Cue(
            title: "Alpine Theme",
            duration: MediaDuration(seconds: 120),
            rightHolders: rightHolders,
            isArrangementOfProtectedOriginal: isArrangementOfProtectedOriginal,
            source: .manual
        )
    }

    // Decimal(string:), not a float literal — a Decimal float literal is
    // converted via Double internally and isn't exact for values like 33.33
    // (SPEC.md §4.6's whole rationale for choosing Decimal over Double
    // depends on constructing it this way).
    private func decimal(_ string: String) throws -> Decimal {
        try XCTUnwrap(Decimal(string: string))
    }

    // MARK: - Share sums

    func test_singleRightHolderAtFullShares_hasNoIssues() {
        let rightHolder = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [rightHolder]))
        XCTAssertTrue(issues.isEmpty)
    }

    func test_unevenLegitimateSplit_33_33_33_33_33_34_sumsToExactly100_hasNoShareIssues() throws {
        let equalShare = try decimal("33.33")
        let remainderShare = try decimal("33.34")
        let rightHolders = [
            CueRightHolder(
                party: .person(UUID()),
                role: .composer,
                performanceBroadcastShare: equalShare,
                mechanicalRightsShare: equalShare
            ),
            CueRightHolder(
                party: .person(UUID()),
                role: .composer,
                performanceBroadcastShare: equalShare,
                mechanicalRightsShare: equalShare
            ),
            CueRightHolder(
                party: .person(UUID()),
                role: .composer,
                performanceBroadcastShare: remainderShare,
                mechanicalRightsShare: remainderShare
            ),
        ]
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: rightHolders))
        XCTAssertTrue(issues.isEmpty)
    }

    func test_performanceBroadcastSharesSummingTo99_99_isFlagged_notToleratedAsRoundingNoise() throws {
        let rightHolder = try CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: decimal("99.99"),
            mechanicalRightsShare: 100
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [rightHolder]))
        XCTAssertEqual(issues, try [.performanceBroadcastSharesDoNotSumTo100(total: decimal("99.99"))])
    }

    func test_mechanicalRightsSharesSummingTo100_01_isFlagged() throws {
        let rightHolder = try CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100,
            mechanicalRightsShare: decimal("100.01")
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [rightHolder]))
        XCTAssertEqual(issues, try [.mechanicalRightsSharesDoNotSumTo100(total: decimal("100.01"))])
    }

    func test_bothShareTypes_areCheckedIndependently_oneWrongDoesNotMaskTheOtherOrFalselyFlagIt() {
        let rightHolder = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 99, mechanicalRightsShare: 100
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [rightHolder]))
        XCTAssertEqual(issues, [.performanceBroadcastSharesDoNotSumTo100(total: 99)])
    }

    func test_emptyRightHolders_flagsBothShareSumsAsZero() {
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: []))
        XCTAssertEqual(issues, [
            .performanceBroadcastSharesDoNotSumTo100(total: 0),
            .mechanicalRightsSharesDoNotSumTo100(total: 0),
        ])
    }

    // MARK: - .performer role exclusion (docs/DECISIONS.md)

    func test_performerRow_isExcludedFromBothShareSums_evenWithNonZeroShareValues() {
        // A .performer row's share values are meaningless (SUISA's WA Film
        // form has no percentage column for performers) — without the
        // exclusion, this 50 would silently count toward the 100% sum
        // alongside the composer's own 100, producing a false "150%" flag.
        let composer = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let performer = CueRightHolder(
            party: .person(UUID()), role: .performer, performanceBroadcastShare: 50, mechanicalRightsShare: 50
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [composer, performer]))
        XCTAssertTrue(issues.isEmpty)
    }

    func test_onlyPerformerRows_stillFlagsBothShareSumsAsZero_conditionAppliesAsIfAbsent() {
        let performer = CueRightHolder(
            party: .person(UUID()), role: .performer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [performer]))
        XCTAssertEqual(issues, [
            .performanceBroadcastSharesDoNotSumTo100(total: 0),
            .mechanicalRightsSharesDoNotSumTo100(total: 0),
        ])
    }

    // MARK: - publishingContractAttached

    func test_publisherRole_withoutAttachedContract_isFlagged() {
        let rightHolder = CueRightHolder(
            party: .label(UUID()), role: .publisher, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [rightHolder]))
        XCTAssertEqual(issues, [.missingPublishingContractAttachment(rightHolderIndex: 0)])
    }

    func test_publisherRole_withAttachedContract_isNotFlagged() {
        let rightHolder = CueRightHolder(
            party: .label(UUID()), role: .publisher, performanceBroadcastShare: 100, mechanicalRightsShare: 100,
            publishingContractAttached: true
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [rightHolder]))
        XCTAssertTrue(issues.isEmpty)
    }

    func test_nonPublisherRole_withoutAttachedContract_isNotFlagged_conditionDoesNotApply() {
        let rightHolder = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [rightHolder]))
        XCTAssertTrue(issues.isEmpty)
    }

    // MARK: - arrangementAuthorizationAttached

    func test_arrangerRole_protectedOriginal_withoutAttachedAuthorization_isFlagged() {
        let rightHolder = CueRightHolder(
            party: .person(UUID()), role: .arranger, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let cue = makeCue(rightHolders: [rightHolder], isArrangementOfProtectedOriginal: true)
        XCTAssertEqual(
            ValidateCueRightHolderSharesUseCase.validate(cue),
            [.missingArrangementAuthorization(rightHolderIndex: 0)]
        )
    }

    func test_arrangerRole_protectedOriginal_withAttachedAuthorization_isNotFlagged() {
        let rightHolder = CueRightHolder(
            party: .person(UUID()), role: .arranger, performanceBroadcastShare: 100, mechanicalRightsShare: 100,
            arrangementAuthorizationAttached: true
        )
        let cue = makeCue(rightHolders: [rightHolder], isArrangementOfProtectedOriginal: true)
        XCTAssertTrue(ValidateCueRightHolderSharesUseCase.validate(cue).isEmpty)
    }

    func test_arrangerRole_notAProtectedOriginal_withoutAttachedAuthorization_isNotFlagged_conditionDoesNotApply() {
        let rightHolder = CueRightHolder(
            party: .person(UUID()), role: .arranger, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let cue = makeCue(rightHolders: [rightHolder], isArrangementOfProtectedOriginal: false)
        XCTAssertTrue(ValidateCueRightHolderSharesUseCase.validate(cue).isEmpty)
    }

    func test_nonArrangerRole_protectedOriginal_withoutAttachedAuthorization_isNotFlagged() {
        let rightHolder = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let cue = makeCue(rightHolders: [rightHolder], isArrangementOfProtectedOriginal: true)
        XCTAssertTrue(ValidateCueRightHolderSharesUseCase.validate(cue).isEmpty)
    }
}
