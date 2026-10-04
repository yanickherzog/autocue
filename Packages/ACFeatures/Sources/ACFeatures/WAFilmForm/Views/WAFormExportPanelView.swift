import ACDesignSystem
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The WA Film tab's export action (`ROADMAP.md` D12/T12.5) — a real
/// `NSSavePanel`, mirroring `ExportPanelView`'s own D11/T11.5 pattern
/// exactly: SwiftUI's `.fileExporter` has no overload that simply hands back
/// a destination `URL` to write to (every overload needs a `FileDocument`/
/// `Transferable`), confirmed against the real SDK at D11/T11.5, not
/// reassumed here. Always exactly one panel, one output file — unlike
/// D11/T11.5's `.both` case, a WA Film export (`WAFormRenderer`) always
/// produces a single combined PDF regardless of how many of the user's own
/// template pages it draws onto.
public struct WAFormExportPanelView: View {
    @Bindable private var viewModel: WAFilmFormViewModel

    public init(viewModel: WAFilmFormViewModel) {
        _viewModel = Bindable(viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Divider().overlay(Theme.Surface.reversed.foreground.opacity(0.2))

            HStack(spacing: Theme.Spacing.md) {
                Spacer(minLength: Theme.Spacing.sm)
                trailingControl
            }

            if !viewModel.canExport {
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
        .errorAlert(message: $viewModel.exportErrorMessage)
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
            .disabled(!viewModel.canExport || viewModel.currentTemplate == nil)
        }
    }

    /// `NSSavePanel.begin(completionHandler:)`, not `.runModal()` — the
    /// non-blocking form, consistent with `ExportPanelView`'s own
    /// established pattern.
    private func presentSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "WA Film.pdf"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await viewModel.export(to: url) }
        }
    }
}
