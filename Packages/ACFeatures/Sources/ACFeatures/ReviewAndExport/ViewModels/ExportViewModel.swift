import ACCore
import Foundation

/// Backs `ExportPanelView` (`ROADMAP.md` D11/T11.5) — the export-controls
/// half of the combined Review & Export destination. Holds only the export
/// action's own transient state (format selection, progress, last result);
/// deliberately does **not** hold its own live `issues`/`Project`
/// subscription — `ReviewAndExportViewModel` already has a `ReviewViewModel`
/// with exactly that, and reconstructing a second copy here would be the
/// same "second variable that has to be kept in sync manually" `CLAUDE.md`'s
/// Single Source of Truth section warns against. Callers pass the current
/// `issues` in at the point of checking/exporting instead.
///
/// **`shareValidationStrictness` is a deliberate, temporary interim value**
/// (`ROADMAP.md` D11/T11.5, `docs/DECISIONS.md`) — `Settings` has no
/// `SettingsRepository` yet (`ROADMAP.md` D15/T15.1), so `DependencyContainer`
/// currently supplies `Settings()`'s own default (`.warnOnly`) at
/// construction rather than a real persisted value. Replacing this with a
/// live-read `Settings` is D15's job, not a silent assumption made here.
@Observable
@MainActor
public final class ExportViewModel {
    public let projectID: Project.ID
    /// Defaults to `.pdf` — the only format `ExportPanelView` currently
    /// offers a control for (`docs/DECISIONS.md`, 2026-10-02). `.xlsx`/
    /// `.both` are still fully real, correct, and directly testable by
    /// setting this property or calling `exportBoth` directly; nothing in
    /// this type enforces `.pdf`-only, only the UI above it currently does.
    public var selectedFormat: ExportFormat = .pdf
    public private(set) var isExporting = false
    public private(set) var progressMessage: String?
    public private(set) var progressFraction: Double?
    public private(set) var lastExportSucceeded = false
    public var errorMessage: String?

    private let exportCueSheetUseCase: ExportCueSheetUseCase
    private let shareValidationStrictness: ShareValidationStrictness

    public init(
        projectID: Project.ID,
        exportCueSheetUseCase: ExportCueSheetUseCase,
        shareValidationStrictness: ShareValidationStrictness
    ) {
        self.projectID = projectID
        self.exportCueSheetUseCase = exportCueSheetUseCase
        self.shareValidationStrictness = shareValidationStrictness
    }

    /// Whether the current `issues` (the caller's already-live
    /// `ReviewViewModel.issues`) permit export right now — the same rule
    /// `export(to:issues:)`/`exportBoth(pdfDestination:xlsxDestination:issues:)`
    /// themselves enforce, exposed separately so `ExportPanelView` can
    /// preemptively disable its Export control rather than let the user
    /// trigger a call that's certain to fail.
    public func canExport(givenIssues issues: [CueSheetValidationIssue]) -> Bool {
        ExportCueSheetUseCase.isExportAllowed(issues: issues, strictness: shareValidationStrictness)
    }

    /// `selectedFormat` must be `.pdf` or `.xlsx` — `ExportPanelView` never
    /// calls this for `.both` (see `exportBoth` below).
    public func export(to destination: URL, issues: [CueSheetValidationIssue]) async {
        await runGuarded(issues: issues) {
            try await self.runExport(format: self.selectedFormat, to: destination)
        }
    }

    /// **`.both` needs two independently-granted destinations, not one
    /// derived from the other — a real, confirmed finding, not an
    /// assumption.** The original design derived the XLSX sibling path by
    /// swapping the PDF destination's extension (`url.deletingPathExtension()
    /// .appendingPathExtension("xlsx")`). That failed in a real sandboxed
    /// run (`ROADMAP.md` D11/T11.5 manual verification, confirmed via a real
    /// `NSSavePanel` round-trip and the exact `ExportRepositoryImpl
    /// .ExportError` this produced): the security-scoped access
    /// `NSSavePanel`/Powerbox grants covers only the *exact* file URL the
    /// user picked, never a sibling path constructed afterward, even in the
    /// same folder — App Sandbox authorizes the chosen file, not the
    /// directory it lives in. The fix: `ExportPanelView` presents two
    /// `NSSavePanel`s for `.both` (PDF, then XLSX, defaulting to the same
    /// folder), each independently Powerbox-granted exactly like the single-
    /// format case already correctly is, and passes both real destinations
    /// in here.
    public func exportBoth(pdfDestination: URL, xlsxDestination: URL, issues: [CueSheetValidationIssue]) async {
        await runGuarded(issues: issues) {
            try await self.runExport(format: .pdf, to: pdfDestination)
            try await self.runExport(format: .xlsx, to: xlsxDestination)
        }
    }

    private func runGuarded(issues: [CueSheetValidationIssue], _ body: () async throws -> Void) async {
        guard canExport(givenIssues: issues) else {
            errorMessage = "Resolve the outstanding issues above before exporting."
            return
        }

        isExporting = true
        lastExportSucceeded = false
        errorMessage = nil
        progressMessage = nil
        progressFraction = nil
        defer { isExporting = false }

        do {
            try await body()
            lastExportSucceeded = true
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func runExport(format: ExportFormat, to destination: URL) async throws {
        for try await progress in exportCueSheetUseCase.export(
            projectID: projectID,
            format: format,
            to: destination,
            shareValidationStrictness: shareValidationStrictness
        ) {
            if case let .progress(update) = progress {
                progressFraction = update.fractionCompleted
                progressMessage = update.message
            }
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case let ExportCueSheetUseCase.Failure.validationIssuesPresent(issues):
            "Export blocked — \(issues.count) outstanding issue\(issues.count == 1 ? "" : "s")."
        case is ProjectNotFoundError:
            "This project may have been deleted."
        default:
            "Export failed: \(error.localizedDescription)"
        }
    }
}
