@testable import ACCore
import XCTest

/// Corrected at D10, third round: Composer, Author, and Publisher combine
/// into one shared 100% pool (`CueRightHolderSharePool.creatorAndPublisher`);
/// Arranger remains its own, separate pool — see
/// `ValidateCueRightHolderSharesUseCase`'s own doc comment for the full
/// account, including why the second-round "every role is independent"
/// model was itself still wrong for Publisher specifically.
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

    // MARK: - Two pools: creator+publisher combined, arranger separate

    /// The exact case both the pre-D10 combined-pool bug and the D10
    /// second-round per-role-pool model got wrong in opposite directions: a
    /// composer and a publisher on the same cue, together summing to 100%,
    /// is genuinely valid — one shared pool, not two independent ones each
    /// needing its own 100%.
    func test_composerAndPublisherCombine_togetherSummingTo100_hasNoIssues() {
        let composer = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 70, mechanicalRightsShare: 70
        )
        let publisher = CueRightHolder(
            party: .label(UUID()), role: .publisher, performanceBroadcastShare: 30, mechanicalRightsShare: 30,
            publishingContractAttached: true
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [composer, publisher]))
        XCTAssertTrue(issues.isEmpty)
    }

    /// The second-round regression this round fixes: composer alone at 100%
    /// plus a publisher independently also at 100% must now be flagged — the
    /// combined pool sums to 200%, which is exactly the real-world case a
    /// per-role-independent model would have wrongly accepted.
    func test_composerAt100PlusPublisherAt100Independently_isFlaggedAs200PercentCombinedTotal() {
        let composer = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let publisher = CueRightHolder(
            party: .label(UUID()), role: .publisher, performanceBroadcastShare: 100, mechanicalRightsShare: 100,
            publishingContractAttached: true
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [composer, publisher]))
        XCTAssertEqual(issues, [
            .performanceBroadcastSharesDoNotSumTo100(pool: .creatorAndPublisher, total: 200),
            .mechanicalRightsSharesDoNotSumTo100(pool: .creatorAndPublisher, total: 200),
        ])
    }

    /// Author joins the same combined pool as Composer/Publisher — confirmed
    /// directly, even though `.author` is hidden from the role picker
    /// (SPEC.md §4.22) and so won't normally appear in new data.
    func test_composerAuthorAndPublisherAllThreeCombine_togetherSummingTo100_hasNoIssues() {
        let composer = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 40, mechanicalRightsShare: 40
        )
        let author = CueRightHolder(
            party: .person(UUID()), role: .author, performanceBroadcastShare: 40, mechanicalRightsShare: 40
        )
        let publisher = CueRightHolder(
            party: .label(UUID()), role: .publisher, performanceBroadcastShare: 20, mechanicalRightsShare: 20,
            publishingContractAttached: true
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(
            makeCue(rightHolders: [composer, author, publisher])
        )
        XCTAssertTrue(issues.isEmpty)
    }

    /// Arranger stays genuinely separate — unaffected by whether the
    /// creator/publisher pool is valid or broken.
    func test_oneComposerAt100AndOneArrangerAt100_bothPoolsIndependentlyValid_hasNoIssues() {
        let composer = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let arranger = CueRightHolder(
            party: .person(UUID()), role: .arranger, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [composer, arranger]))
        XCTAssertTrue(issues.isEmpty)
    }

    /// The creator/publisher pool alone can be broken while the arranger
    /// pool stays valid — each is checked and reported independently.
    func test_brokenCreatorAndPublisherPool_doesNotAffectAValidArrangerPool() {
        let composer = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 60, mechanicalRightsShare: 60
        )
        let arranger = CueRightHolder(
            party: .person(UUID()), role: .arranger, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [composer, arranger]))
        XCTAssertEqual(issues, [
            .performanceBroadcastSharesDoNotSumTo100(pool: .creatorAndPublisher, total: 60),
            .mechanicalRightsSharesDoNotSumTo100(pool: .creatorAndPublisher, total: 60),
        ])
    }

    /// A pool with zero members has no pool to validate at all — an
    /// arranger-only cue is never flagged for a missing creator/publisher
    /// pool, and vice versa.
    func test_poolWithNoRightHolders_hasNoPoolToValidate() {
        let arranger = CueRightHolder(
            party: .person(UUID()), role: .arranger, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [arranger]))
        XCTAssertTrue(issues.isEmpty)
    }

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
        XCTAssertEqual(
            issues,
            try [.performanceBroadcastSharesDoNotSumTo100(pool: .creatorAndPublisher, total: decimal("99.99"))]
        )
    }

    func test_mechanicalRightsSharesSummingTo100_01_isFlagged() throws {
        let rightHolder = try CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100,
            mechanicalRightsShare: decimal("100.01")
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [rightHolder]))
        XCTAssertEqual(
            issues,
            try [.mechanicalRightsSharesDoNotSumTo100(pool: .creatorAndPublisher, total: decimal("100.01"))]
        )
    }

    func test_bothShareTypes_areCheckedIndependently_oneWrongDoesNotMaskTheOtherOrFalselyFlagIt() {
        let rightHolder = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 99, mechanicalRightsShare: 100
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [rightHolder]))
        XCTAssertEqual(issues, [.performanceBroadcastSharesDoNotSumTo100(pool: .creatorAndPublisher, total: 99)])
    }

    func test_emptyRightHolders_hasNoIssues_nothingToValidate() {
        // With zero right-holders, both pools are empty, and an empty pool
        // has nothing to check (see test_poolWithNoRightHolders_... above).
        // Whether a Cue needs ≥1 right-holder at all is a required-field
        // check, D11's job (`ValidateCueSheetUseCase`), not this
        // cross-field share-sum Use Case's.
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: []))
        XCTAssertTrue(issues.isEmpty)
    }

    // MARK: - .performer role exclusion (docs/DECISIONS.md)

    func test_performerRow_isExcludedFromBothShareSums_evenWithNonZeroShareValues() {
        // A .performer row's share values are meaningless (SUISA's WA Film
        // form has no percentage column for performers) — without the
        // exclusion, this 50 would count toward the creator/publisher pool,
        // which it has no membership in at all.
        let composer = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let performer = CueRightHolder(
            party: .person(UUID()), role: .performer, performanceBroadcastShare: 50, mechanicalRightsShare: 50
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [composer, performer]))
        XCTAssertTrue(issues.isEmpty)
    }

    func test_onlyPerformerRows_hasNoIssues_performerHasNoPoolAtAll() {
        let performer = CueRightHolder(
            party: .person(UUID()), role: .performer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(makeCue(rightHolders: [performer]))
        XCTAssertTrue(issues.isEmpty)
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
