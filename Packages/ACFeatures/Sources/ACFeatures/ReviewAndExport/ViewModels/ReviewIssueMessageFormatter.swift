import ACCore

/// Turns `ValidateCueSheetUseCase`'s aggregate issue list into concrete,
/// human-readable strings for `ReviewView` (`ROADMAP.md` D11/T11.1) — the
/// same "pull formatting logic out where it can be unit-tested" discipline
/// `CueRightHolderValidationMessageFormatter` (`ROADMAP.md` D10) already
/// establishes, reused here rather than duplicated: every
/// `.cueRightHolderIssue` case is handed off to that existing formatter for
/// its actual wording, so a share-sum/attachment message reads identically
/// whether it's shown in the Royalty Split sheet or here.
///
/// A plain, pure, non-View type — not a View or ViewModel — for the same
/// reason as its D10 counterpart: `ReviewView` itself, like every other View
/// in this codebase, isn't unit-tested (`CONTRIBUTING.md` §5/§7).
enum ReviewIssueMessageFormatter {
    /// One message per issue, in the same order `ValidateCueSheetUseCase
    /// .validate(_:)` returned them.
    static func messages(
        for issues: [CueSheetValidationIssue],
        cues: [Cue],
        people: [Person],
        labels: [Label]
    ) -> [String] {
        issues.map { message(for: $0, cues: cues, people: people, labels: labels) }
    }

    private static func message(
        for issue: CueSheetValidationIssue,
        cues: [Cue],
        people: [Person],
        labels: [Label]
    ) -> String {
        switch issue {
        case let .missingSetupField(field):
            return "Setup: \(field.displayName) is missing."
        case .missingOtherProductionTypeDescription:
            return "Setup: \"Other\" production type is selected but not described."
        case .missingOtherAttachmentDescription:
            return "Setup: \"Other\" attachment type is selected but not described."
        case let .cueHasNoRightHolders(cueID):
            return "\(cueLabel(for: cueID, in: cues)) has no right-holders."
        case let .cueRightHolderIssue(cueID, rightHolderIssue):
            let cue = cues.first { $0.id == cueID }
            let rightHolderMessage = CueRightHolderValidationMessageFormatter.messages(
                for: [rightHolderIssue],
                rightHolders: cue?.rightHolders ?? [],
                people: people,
                labels: labels
            ).first ?? "An unspecified issue."
            return "\(cueLabel(for: cueID, in: cues)): \(rightHolderMessage)"
        }
    }

    /// "Cue N — Title", matching the display number `CueTableView`/the
    /// waveform's "CUE N" label already show (SPEC.md §4.22) — `N` is this
    /// cue's 1-indexed position in `cues`, not a stored field.
    ///
    /// **Widened from `private` at `ROADMAP.md` D12/T12.4** — a real second
    /// caller, `WAFormValidationMessageFormatter`, now needs the identical
    /// cue-labeling logic for its own WA-form-specific issue cases
    /// (`CLAUDE.md` rule 7's promotion bar: a real second use, not a
    /// hypothetical one).
    static func cueLabel(for cueID: Cue.ID, in cues: [Cue]) -> String {
        guard let index = cues.firstIndex(where: { $0.id == cueID }) else { return "A cue" }
        return "Cue \(index + 1) — \(cues[index].title)"
    }
}
