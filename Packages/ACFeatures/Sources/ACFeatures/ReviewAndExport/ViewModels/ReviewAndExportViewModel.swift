import ACCore
import Foundation

/// Composes the three already-independently-built pieces of the combined
/// Review & Export destination (`CLAUDE.md`'s Navigation Model: "a single
/// persistent screen showing both the validation summary and the export
/// controls... together, inline") into one root the hosting View binds to —
/// `ReviewViewModel` (`ROADMAP.md` D11/T11.1), `CueSheetPreviewViewModel`
/// (D11/T11.2), and the new `ExportViewModel` (D11/T11.5).
///
/// **Deliberately thin — no logic of its own.** The actual export-readiness
/// coordination (does `reviewViewModel.issues` currently permit exporting)
/// is a pure function of state each child already owns
/// (`ExportViewModel.canExport(givenIssues:)`), computed by `ExportPanelView`
/// at the point it needs it — this type exists only so
/// `DependencyContainer` has exactly one factory method for this screen, per
/// `CLAUDE.md`'s Dependency Injection Pattern, not three.
@Observable
@MainActor
public final class ReviewAndExportViewModel {
    public let reviewViewModel: ReviewViewModel
    public let cueSheetPreviewViewModel: CueSheetPreviewViewModel
    public let exportViewModel: ExportViewModel

    public init(
        reviewViewModel: ReviewViewModel,
        cueSheetPreviewViewModel: CueSheetPreviewViewModel,
        exportViewModel: ExportViewModel
    ) {
        self.reviewViewModel = reviewViewModel
        self.cueSheetPreviewViewModel = cueSheetPreviewViewModel
        self.exportViewModel = exportViewModel
    }
}
