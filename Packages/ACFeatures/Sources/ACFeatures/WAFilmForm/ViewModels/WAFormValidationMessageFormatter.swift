import ACCore

/// Turns `ValidateWAFormUseCase`'s aggregate `[WAFormValidationIssue]` into
/// concrete, human-readable strings for the WA Film tab (`ROADMAP.md`
/// D12/T12.4) — the same "pull formatting logic out where it can be
/// unit-tested" discipline `ReviewIssueMessageFormatter` (D11/T11.1) already
/// establishes, reused here rather than duplicated: every `.cueSheetIssue`
/// case is handed off to that existing formatter so a shared issue (a
/// missing Setup field, a share-sum mismatch) reads identically whether it's
/// shown on the Review & Export screen or here.
enum WAFormValidationMessageFormatter {
    static func messages(
        for issues: [WAFormValidationIssue],
        cues: [Cue],
        people: [Person],
        labels: [Label]
    ) -> [String] {
        issues.map { message(for: $0, cues: cues, people: people, labels: labels) }
    }

    private static func message(
        for issue: WAFormValidationIssue,
        cues: [Cue],
        people: [Person],
        labels: [Label]
    ) -> String {
        switch issue {
        case let .cueSheetIssue(cueSheetIssue):
            return ReviewIssueMessageFormatter.messages(
                for: [cueSheetIssue],
                cues: cues,
                people: people,
                labels: labels
            ).first ?? "An unspecified issue."
        case let .cueExceedsRightHolderCapacity(cueID, rightHolderCount):
            let capacity = ValidateWAFormUseCase.rightHolderCapacityPerWork
            return "\(ReviewIssueMessageFormatter.cueLabel(for: cueID, in: cues)) has \(rightHolderCount) " +
                "right-holders — the WA Film form has room for only \(capacity) per work. Consolidate right-holders " +
                "or submit a manual addendum."
        case let .cueCountExceedsFormCapacity(cueCount, availableCapacity):
            return "This production has \(cueCount) cues, but the imported WA Film template only supports " +
                "\(availableCapacity). Obtain additional continuation pages from SUISA, or reduce the number of " +
                "cues declared on this form."
        }
    }
}
