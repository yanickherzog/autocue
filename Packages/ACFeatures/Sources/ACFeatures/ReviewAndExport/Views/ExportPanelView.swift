import ACCore
import ACDesignSystem
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The export-controls half of the combined Review & Export screen
/// (`ROADMAP.md` D11/T11.5) — Export button, progress, and the real save
/// destination picker. Receives its ViewModel and the current `issues` (from
/// the sibling `ReviewViewModel` — see `ExportViewModel`'s own doc comment
/// for why this View isn't given a second, independent subscription) as
/// plain initializer parameters, per `CLAUDE.md`'s Dependency Injection
/// Pattern.
///
/// **PDF-only, deliberately (`docs/DECISIONS.md`, 2026-10-02).** This View
/// no longer offers a format picker — `ExportViewModel.selectedFormat`
/// defaults to, and is never changed from, `.pdf` by anything in this View.
/// `.xlsx`/`.both` are fully implemented and tested one layer down
/// (`ExportCueSheetUseCase`, `ExportRepositoryImpl`, `XLSXCueSheetWriter`)
/// and remain directly reachable by setting `selectedFormat`/calling
/// `exportBoth` outside this View (as the ViewModel-level tests do) — only
/// this screen's own UI surface was narrowed, not the underlying export
/// pipeline. `contentTypes`/`defaultFilenameExtension`/`presentSavePanel`'s
/// `.xlsx`/`.both` branches are kept for exactly that reason, not dead code.
///
/// **A real `NSSavePanel`, not `.fileExporter` — a genuine, confirmed
/// SwiftUI gap, not an assumption.** The T11.5 plan originally assumed
/// `.fileExporter` would work symmetrically with `AudioImportView`'s
/// `.fileImporter` (hand back a destination `URL`, this app writes the
/// bytes itself via `ExportRepositoryImpl`). That assumption was checked
/// against the real SDK (`SwiftUI.swiftinterface`, Xcode 26.3) rather than
/// trusted by symmetry, and turned out to be wrong: **every**
/// `View.fileExporter` overload in SwiftUI requires either a
/// `FileDocument`/`ReferenceFileDocument` (whose `fileWrapper(configuration:)`
/// SwiftUI itself calls to obtain the bytes) or a `Transferable` item — there
/// is no overload that simply hands back a Powerbox-granted `URL` for the
/// caller to write to, the way `.fileImporter` hands back one to read from.
/// Neither shape fits this app's export pipeline: the PDF/XLSX bytes are
/// produced by `ExportRepositoryImpl` writing directly to a `URL` via Core
/// Graphics/`libxlsxwriter` (`CLAUDE.md`, "Export Architecture") — reshaping
/// that into an in-memory `FileDocument.fileWrapper` or a `Transferable`
/// would mean holding a full rendered PDF/XLSX in memory and duplicating the
/// write path, for no real benefit. `NSSavePanel` is exactly `CLAUDE.md`'s
/// AppKit-interop escape hatch for this: it still is Powerbox-mediated (the
/// sandbox brokers the panel and grants access to whatever the user picks,
/// same as `.fileExporter` would), it just hands back the destination `URL`
/// directly, which is the one shape this app's export pipeline actually
/// needs.
public struct ExportPanelView: View {
    @Bindable private var viewModel: ExportViewModel
    let issues: [CueSheetValidationIssue]

    public init(viewModel: ExportViewModel, issues: [CueSheetValidationIssue]) {
        _viewModel = Bindable(viewModel)
        self.issues = issues
    }

    private var canExport: Bool {
        viewModel.canExport(givenIssues: issues)
    }

    /// Only ever consulted for `.pdf`/`.xlsx` — `.both` presents its own two
    /// panels directly (`presentBothSavePanels`), each with its own fixed
    /// content type, never through this computed property.
    private var contentTypes: [UTType] {
        switch viewModel.selectedFormat {
        case .pdf, .both:
            [.pdf]
        case .xlsx:
            [Self.xlsxContentType]
        }
    }

    private var defaultFilenameExtension: String {
        switch viewModel.selectedFormat {
        case .pdf, .both: "pdf"
        case .xlsx: "xlsx"
        }
    }

    private static let xlsxContentType = UTType(filenameExtension: "xlsx") ?? .data

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Divider().overlay(Theme.Surface.reversed.foreground.opacity(0.2))

            HStack(spacing: Theme.Spacing.md) {
                Spacer(minLength: Theme.Spacing.sm)

                trailingControl
            }

            if !canExport {
                Text("Resolve the issues above before exporting.")
                    .font(Theme.Typography.font(.regular, size: 12))
                    .foregroundStyle(Theme.Surface.reversed.foreground.opacity(0.6))
            } else if viewModel.lastExportSucceeded {
                Text("Export complete.")
                    .font(Theme.Typography.font(.regular, size: 12))
                    .foregroundStyle(Theme.Surface.reversed.foreground.opacity(0.6))
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Surface.reversed.background)
        .errorAlert(message: $viewModel.errorMessage)
    }

    @ViewBuilder
    private var trailingControl: some View {
        if viewModel.isExporting {
            ProgressBanner(
                message: viewModel.progressMessage ?? "Exporting…",
                fractionCompleted: viewModel.progressFraction,
                surface: .reversed
            )
        } else {
            Button("Export…") {
                presentSavePanel()
            }
            .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: .reversed))
            .disabled(!canExport)
        }
    }

    /// `NSSavePanel.begin(completionHandler:)`, not `.runModal()` — the
    /// non-blocking form, consistent with this app never using blocking
    /// AppKit calls from a SwiftUI action closure. Not attached to a
    /// specific `NSWindow` (no `beginSheetModal(for:)`) since this View has
    /// no direct handle on its hosting window and a standalone panel is
    /// standard, fully-supported AppKit behavior — it still blocks
    /// interaction with the app the same way a sheet would.
    ///
    /// **`.both` presents two save panels, one per format — not one panel
    /// plus a derived sibling path.** See `ExportViewModel.exportBoth`'s doc
    /// comment for the real, confirmed reason: App Sandbox authorizes only
    /// the exact file the user picks, never a sibling path constructed
    /// afterward. The second panel defaults to the first's folder
    /// (`directoryURL`) so the common case — both files in one place — is
    /// still just two quick confirmations, not real re-navigation.
    private func presentSavePanel() {
        switch viewModel.selectedFormat {
        case .pdf, .xlsx:
            let panel = NSSavePanel()
            panel.allowedContentTypes = contentTypes
            panel.nameFieldStringValue = "Cue Sheet.\(defaultFilenameExtension)"
            panel.canCreateDirectories = true
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                Task { await viewModel.export(to: url, issues: issues) }
            }
        case .both:
            presentBothSavePanels()
        }
    }

    private func presentBothSavePanels() {
        let pdfPanel = NSSavePanel()
        pdfPanel.allowedContentTypes = [.pdf]
        pdfPanel.nameFieldStringValue = "Cue Sheet.pdf"
        pdfPanel.canCreateDirectories = true
        pdfPanel.begin { pdfResponse in
            guard pdfResponse == .OK, let pdfURL = pdfPanel.url else { return }

            let xlsxPanel = NSSavePanel()
            xlsxPanel.allowedContentTypes = [Self.xlsxContentType]
            xlsxPanel.nameFieldStringValue = "Cue Sheet.xlsx"
            xlsxPanel.directoryURL = pdfURL.deletingLastPathComponent()
            xlsxPanel.canCreateDirectories = true
            xlsxPanel.begin { xlsxResponse in
                guard xlsxResponse == .OK, let xlsxURL = xlsxPanel.url else { return }
                Task { await viewModel.exportBoth(pdfDestination: pdfURL, xlsxDestination: xlsxURL, issues: issues) }
            }
        }
    }
}
