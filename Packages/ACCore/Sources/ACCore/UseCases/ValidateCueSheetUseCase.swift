import Foundation

/// Aggregates every SPEC.md §4.6 export-readiness check across a whole
/// `Project` — `Setup` completeness plus every `Cue`'s right-holder
/// validation — for `ROADMAP.md` D11/T11.1's Review section.
///
/// A pure function of a `Project` value, no Repository dependency — the same
/// "pure static helper" shape `ValidateCueRightHolderSharesUseCase`/
/// `PartyResolver`/`RecalculateTotalMusicRuntimeUseCase` already establish.
/// Reuses rather than duplicates two already-built pieces: `Setup
/// .missingRequiredFields` (`ROADMAP.md` D7 — that type's own doc comment
/// names this Use Case as its intended consumer) for the Setup-completeness
/// half, and `ValidateCueRightHolderSharesUseCase.validate(_:)` (`ROADMAP.md`
/// D2/D10) for each `Cue`'s share/attachment rules.
///
/// **Does not apply `Settings.shareValidationStrictness`.** SPEC.md §4.6:
/// "Whether a failed rule blocks export or only warns is controlled by
/// `Settings.shareValidationStrictness`" — that's a policy decision about
/// what to *do* with a reported issue, not part of detecting one. This Use
/// Case only reports facts; `ROADMAP.md` D11/T11.5's export flow is where the
/// strictness setting decides whether a reported issue blocks the export.
public enum ValidateCueSheetUseCase {
    /// Every issue currently present on `project`, or an empty array if it's
    /// fully export-ready. Order: `Setup`-level issues first (in
    /// `SPEC.md` §4.6's own listed order), then per-`Cue` issues in
    /// `project.cues`'s display order, each cue's own issues in
    /// `ValidateCueRightHolderSharesUseCase`'s existing order.
    public static func validate(_ project: Project) -> [CueSheetValidationIssue] {
        var issues: [CueSheetValidationIssue] = setupIssues(for: project.setup)

        for cue in project.cues {
            if cue.rightHolders.isEmpty {
                issues.append(.cueHasNoRightHolders(cueID: cue.id))
            }
            for rightHolderIssue in ValidateCueRightHolderSharesUseCase.validate(cue) {
                issues.append(.cueRightHolderIssue(cueID: cue.id, issue: rightHolderIssue))
            }
        }

        return issues
    }

    private static func setupIssues(for setup: Setup) -> [CueSheetValidationIssue] {
        var issues: [CueSheetValidationIssue] = setup.missingRequiredFields.map { .missingSetupField($0) }

        if setup.productionTypes.contains(.other), isBlank(setup.otherProductionTypeDescription) {
            issues.append(.missingOtherProductionTypeDescription)
        }

        if setup.attachmentTypes.contains(.other), isBlank(setup.otherAttachmentDescription) {
            issues.append(.missingOtherAttachmentDescription)
        }

        return issues
    }

    private static func isBlank(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One reason a `Project` isn't yet export-ready (SPEC.md §4.6).
///
/// `cueID`/`rightHolderIndex` (the latter nested inside
/// `CueRightHolderValidationIssue`) identify the offending `Cue`/row
/// precisely enough for `ReviewViewModel` to report a distinct, identifiable
/// issue per occurrence — never a single collapsed "something's wrong" flag.
public enum CueSheetValidationIssue: Equatable, Sendable {
    case missingSetupField(SetupRequiredField)
    case missingOtherProductionTypeDescription
    case missingOtherAttachmentDescription
    /// `SPEC.md` §4.3: `Cue.rightHolders` is required, ≥1 — a cue with none
    /// has nothing for `ValidateCueRightHolderSharesUseCase` to validate (an
    /// empty pool has nothing to sum), so that Use Case alone would silently
    /// treat a rightHolder-less cue as valid. This case closes that gap.
    case cueHasNoRightHolders(cueID: Cue.ID)
    case cueRightHolderIssue(cueID: Cue.ID, issue: CueRightHolderValidationIssue)
}
