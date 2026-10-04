import Foundation

/// Aggregates every export-readiness check for the literal SUISA WA Film
/// registration form (`ROADMAP.md` D12/T12.3) — `ValidateCueSheetUseCase`'s
/// existing checks (Setup completeness, per-`Cue` share/attachment rules,
/// all genuinely shared requirements between the two documents) plus two new
/// checks real only to this fixed-capacity paper form: a work's right-holder
/// row limit, and the imported template's own finite page capacity.
///
/// **Deliberately a separate issue type from `CueSheetValidationIssue`, not
/// new cases added to that enum — a real, confirmed architectural
/// requirement, not a style preference.** `ReviewViewModel` (D11/T11.1) calls
/// `ValidateCueSheetUseCase.validate(_:)` directly and surfaces every case of
/// `CueSheetValidationIssue` on the producer-facing Review & Export screen.
/// That screen has no SUISA-form-specific capacity limits — a cue sheet PDF
/// paginates dynamically with no cap this app controls (`CueSheetLayoutComputer`,
/// D11/T11.2) — so a WA-form-only warning appearing there would be actively
/// wrong, not just out of place. Wrapping the existing issues in
/// `.cueSheetIssue(_:)` here, rather than adding cases to the shared enum
/// directly, makes that separation a compile-time property of which type a
/// screen consumes, not a runtime discipline ("just don't call `.map` over
/// the WA-specific cases on that screen") that a future change could
/// silently violate. See `docs/DECISIONS.md`.
///
/// `continuationPagesAvailable: Int?` — `nil` explicitly means "no
/// continuation template page count is known" (no template imported yet, or
/// its page count couldn't be read), not "zero continuation pages always
/// assumed." Per an explicit project-owner decision: in that state, the
/// capacity check still runs, scoped to what the main form alone holds (5
/// works) — never silently skipped and never assumed-zero without being
/// stated as its own case. `instance.validate(_:)`, below, resolves this
/// live value for whichever template is currently imported (if any) via
/// `ExportRepository.continuationTemplatePageCount()`; the pure static
/// `validate(_:continuationPagesAvailable:)` is what's actually
/// directly unit-tested, the same "pure half tested directly, I/O half
/// tested via orchestration" split `ExportCueSheetUseCase.isExportAllowed`
/// already establishes.
public struct ValidateWAFormUseCase: Sendable {
    /// Mirrors `WAFormLayoutComputer`'s own identically-named/-valued
    /// constants (`ACExport`) — duplicated, not shared, since `ACCore` can
    /// never import `ACExport` (`CLAUDE.md`'s Package Dependency Graph). The
    /// same small, deliberate cross-package duplication already established
    /// by `BookmarkAccessMode`'s resolution-options extensions
    /// (`ACAudioKit`/`ACExport`) and `CueSheetLayoutComputer+Formatting`'s
    /// font-name mapping (`ACExport`/`ACFeatures`) — keep these three values
    /// in sync with `WAFormLayoutComputer`'s own if either ever changes.
    ///
    /// **`public`, not `internal`** — `WAFormValidationMessageFormatter`
    /// (`ACFeatures`, D12/T12.4) quotes `rightHolderCapacityPerWork` directly
    /// in its own message text rather than hardcoding the number `3` a
    /// second time.
    public static let rightHolderCapacityPerWork = 3
    public static let worksOnMainForm = 5
    public static let worksPerContinuationPage = 4

    private let exportRepository: ExportRepository

    public init(exportRepository: ExportRepository) {
        self.exportRepository = exportRepository
    }

    /// Resolves whichever template is currently imported's real, live
    /// continuation-page count via `ExportRepository` before running the
    /// pure check below (`nil` if none is imported at all — not an error) —
    /// the one place in this type that can throw, for the same real
    /// file-I/O reasons `ExportRepository.continuationTemplatePageCount()`
    /// already documents.
    public func validate(_ project: Project) throws -> [WAFormValidationIssue] {
        let continuationPagesAvailable = try exportRepository.continuationTemplatePageCount()
        return Self.validate(project, continuationPagesAvailable: continuationPagesAvailable)
    }

    /// The pure check, directly unit-testable with no Repository/fake
    /// needed — `continuationPagesAvailable: nil` is the explicit "not yet
    /// known" state described above.
    public static func validate(_ project: Project, continuationPagesAvailable: Int?) -> [WAFormValidationIssue] {
        var issues: [WAFormValidationIssue] = ValidateCueSheetUseCase.validate(project).map { .cueSheetIssue($0) }

        for cue in project.cues {
            let nonPerformerCount = cue.rightHolders.filter { $0.role != .performer }.count
            if nonPerformerCount > rightHolderCapacityPerWork {
                issues.append(.cueExceedsRightHolderCapacity(cueID: cue.id, rightHolderCount: nonPerformerCount))
            }
        }

        let availableCapacity = worksOnMainForm + worksPerContinuationPage * (continuationPagesAvailable ?? 0)
        if project.cues.count > availableCapacity {
            issues.append(.cueCountExceedsFormCapacity(
                cueCount: project.cues.count,
                availableCapacity: availableCapacity
            ))
        }

        return issues
    }

    /// Whether a WA Form reporting `issues` may be exported under
    /// `strictness` — the same pure, stateless shape
    /// `ExportCueSheetUseCase.isExportAllowed(issues:strictness:)` already
    /// establishes, so a ViewModel's preemptive button-enabling and
    /// `ExportWAFormUseCase`'s own real enforcement share one rule rather
    /// than each defining it independently (`CLAUDE.md` rule 7).
    public static func isExportAllowed(issues: [WAFormValidationIssue], strictness: ShareValidationStrictness) -> Bool {
        issues.isEmpty || strictness == .warnOnly
    }
}

/// One reason a `Project` isn't yet ready to export as a WA Film registration
/// form — either a generic cue-sheet-level issue (`.cueSheetIssue`, shared
/// with D11's Review screen) or one of the two checks real only to this
/// fixed-capacity paper form.
public enum WAFormValidationIssue: Equatable, Sendable {
    /// Wraps a `CueSheetValidationIssue` unchanged — see
    /// `ValidateWAFormUseCase`'s own doc comment for why this is a wrapped
    /// case rather than the two types being merged into one enum.
    case cueSheetIssue(CueSheetValidationIssue)
    /// The real form has exactly 3 blank right-holder rows per work
    /// (`docs/DECISIONS.md`, 2026-10-02) — `rightHolderCount` is the cue's
    /// actual non-`.performer` count, always `>
    /// ValidateWAFormUseCase.rightHolderCapacityPerWork` whenever this case
    /// appears.
    case cueExceedsRightHolderCapacity(cueID: Cue.ID, rightHolderCount: Int)
    /// The main form (5 works) plus whatever continuation pages the user's
    /// imported template actually has can't hold every `Cue` in this
    /// `Project` — `availableCapacity` is the real computed ceiling (5 when
    /// no continuation page count is known at all, per
    /// `ValidateWAFormUseCase`'s own doc comment).
    case cueCountExceedsFormCapacity(cueCount: Int, availableCapacity: Int)
}
